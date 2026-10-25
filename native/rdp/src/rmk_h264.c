/*
 * H.264（AVC420 / AVC444）解码：探测 FFmpeg 解码器与平台硬件解码，并据此配置连接参数。
 * 硬件设备由 hwdec/ 下的平台实现提供。探测时用硬件实际解码一帧内置画面并校验颜色：
 * 部分环境（虚拟机、驱动异常）能创建设备但无法解码，FreeRDP 此时不会回退，因此只有解码成功才启用硬件。
 * 内置画面能解码不代表服务端的视频流也能解码（例如 Intel Mac 的 VideoToolbox 拒绝部分 High 档次 1080p 流），
 * 因此连接中每个表面的首个 H.264 命令还会用实际码流再校验一次，失败则本次会话改用软件解码。
 */
#include <freerdp/codec/color.h>
#include <freerdp/codec/h264.h>
#include <freerdp/gdi/gfx.h>
#include <libavcodec/avcodec.h>
#include <libavutil/hwcontext.h>
#include <stdlib.h>
#include <winpr/synch.h>

#include "hwdec/rmk_hwdec.h"
#include "rmk_h264_probe_frame.h"
#include "rmk_internal.h"

static INIT_ONCE rmk_h264_once = INIT_ONCE_STATIC_INIT;
static int32_t rmk_h264_caps_value = 0;

/* 用与连接相同的 FreeRDP AVC420 流程把一帧 H.264 解码为 BGRA；hardware 为 TRUE 时使用平台硬件设备。
 * rects 为需要输出的区域（NULL 时为整帧），必须在解码画面范围内 */
static INT32 rmk_h264_decode(const BYTE* data, UINT32 size, UINT32 width, UINT32 height,
                             BOOL hardware, BYTE* bgra, const RECTANGLE_16* rects, UINT32 nrects)
{
	H264_CONTEXT* h264 = h264_context_new(FALSE);
	if (!h264)
		return -102;
	INT32 rc = -103;
	/* 与 gdi/gfx.c 相同：HW_ACCEL 为 TRUE 时 FFmpeg 使用硬件设备 */
	if (h264_context_set_option(h264, H264_CONTEXT_OPTION_HW_ACCEL, hardware) &&
	    h264_context_reset(h264, width, height))
	{
		const RECTANGLE_16 full = { 0, 0, (UINT16)width, (UINT16)height };
		rc = avc420_decompress(h264, data, size, bgra, PIXEL_FORMAT_BGRA32, width * 4, width,
		                       height, rects ? rects : &full, rects ? nrects : 1);
	}
	h264_context_free(h264);
	return rc;
}

/* 像素 (x, y) 是否接近期望颜色（RGB，允许 YUV 转换误差） */
static BOOL rmk_pixel_near(const BYTE* bgra, UINT32 x, UINT32 y, UINT32 rgb)
{
	const BYTE* p = bgra + ((size_t)y * RMK_PROBE_WIDTH + x) * 4;
	const int expected[3] = { (int)(rgb & 0xFF), (int)((rgb >> 8) & 0xFF), (int)((rgb >> 16) & 0xFF) };
	for (int c = 0; c < 3; c++)
	{
		if (abs((int)p[c] - expected[c]) > 12)
			return FALSE;
	}
	return TRUE;
}

/* 用硬件实际解码内置画面（左半 #E04020、右半 #3080C0），解码成功且颜色正确才认为硬件可用 */
static BOOL rmk_h264_hardware_works(void)
{
	BYTE* bgra = calloc((size_t)RMK_PROBE_WIDTH * RMK_PROBE_HEIGHT, 4);
	if (!bgra)
		return FALSE;
	const BOOL ok = rmk_h264_decode(rmk_probe_frame, sizeof(rmk_probe_frame), RMK_PROBE_WIDTH,
	                                RMK_PROBE_HEIGHT, TRUE, bgra, NULL, 0) >= 0 &&
	                rmk_pixel_near(bgra, 40, 120, 0xE04020) &&
	                rmk_pixel_near(bgra, 280, 120, 0x3080C0);
	free(bgra);
	return ok;
}

/* 实际探测（只执行一次）：写入 FreeRDP 环境变量，检查 H.264 解码器，创建硬件设备并实际硬件解码一帧 */
static BOOL CALLBACK rmk_h264_probe_once(PINIT_ONCE once, PVOID param, PVOID* context)
{
	WINPR_UNUSED(once);
	WINPR_UNUSED(param);
	WINPR_UNUSED(context);
	rmk_hwdec_prepare();
	int32_t caps = 0;
	if (avcodec_find_decoder(AV_CODEC_ID_H264))
		caps |= RMK_H264_DECODER;
	const enum AVHWDeviceType type = av_hwdevice_find_type_by_name(rmk_hwdec_type());
	AVBufferRef* device = NULL;
	if ((caps & RMK_H264_DECODER) && type != AV_HWDEVICE_TYPE_NONE &&
	    av_hwdevice_ctx_create(&device, type, rmk_hwdec_device(), NULL, 0) >= 0)
	{
		av_buffer_unref(&device);
		/* 设备可创建不代表能解码（例如虚拟机中的 VideoToolbox、异常的 VAAPI 驱动） */
		if (rmk_h264_hardware_works())
			caps |= RMK_H264_HARDWARE;
	}
	rmk_h264_caps_value = caps;
	return TRUE;
}

/* 取得 H.264 解码能力，首次调用时探测 */
int32_t rmk_h264_caps(void)
{
	InitOnceExecuteOnce(&rmk_h264_once, rmk_h264_probe_once, NULL, NULL);
	return rmk_h264_caps_value;
}

/* 按探测结果开启 H.264 能力协商；hw_enabled 为用户设置（关闭时只用软件解码） */
BOOL rmk_h264_apply(rdpSettings* settings, BOOL hw_enabled)
{
	const int32_t caps = rmk_h264_caps();
	const BOOL h264 = (caps & RMK_H264_DECODER) != 0;
	const BOOL hardware = hw_enabled && (caps & RMK_H264_HARDWARE) != 0;
	/* SoftwareGdi 为 FALSE 时 FreeRDP 为每个 H.264 表面启用 FFmpeg 硬件解码；
	 * 硬件不可用或用户关闭时保持软件解码，避免每个表面重复尝试创建设备 */
	return freerdp_settings_set_bool(settings, FreeRDP_GfxH264, h264) &&
	       freerdp_settings_set_bool(settings, FreeRDP_GfxAVC444, h264) &&
	       freerdp_settings_set_bool(settings, FreeRDP_GfxAVC444v2, h264) &&
	       freerdp_settings_set_bool(settings, FreeRDP_SoftwareGdi, !hardware);
}

/* 用实际码流检查硬件解码：1 硬件可解码（硬件不可用时按软件解码），0 硬件失败但软件成功，-1 都失败
 * （码流缺少 SPS / IDR 等数据问题，换软件解码也无济于事）。rects 为命令的更新区域，NULL 时为整帧：
 * 表面高度按 16 对齐（如 1088），实际画面可能更小（如 1080），整表面区域会被 FreeRDP 判为越界 */
static int32_t rmk_h264_check_stream(const BYTE* data, UINT32 size, UINT32 width, UINT32 height,
                                     const RECTANGLE_16* rects, UINT32 nrects)
{
	BYTE* bgra = calloc((size_t)width * height, 4);
	if (!bgra)
		return -1;
	int32_t result = 1;
	if (rmk_h264_decode(data, size, width, height, TRUE, bgra, rects, nrects) < 0)
		result = rmk_h264_decode(data, size, width, height, FALSE, bgra, rects, nrects) >= 0 ? 0 : -1;
	free(bgra);
	return result;
}

/* 取得 H.264 命令的主码流；AVC444 只含色度辅助流（LC = 2）时没有可单独校验的主码流 */
static const RDPGFX_AVC420_BITMAP_STREAM* rmk_h264_main_stream(const RDPGFX_SURFACE_COMMAND* cmd)
{
	switch (cmd->codecId)
	{
		case RDPGFX_CODECID_AVC420:
			return (const RDPGFX_AVC420_BITMAP_STREAM*)cmd->extra;
		case RDPGFX_CODECID_AVC444:
		case RDPGFX_CODECID_AVC444v2:
		{
			const RDPGFX_AVC444_BITMAP_STREAM* avc444 = (const RDPGFX_AVC444_BITMAP_STREAM*)cmd->extra;
			return (avc444 && avc444->LC != 2) ? &avc444->bitstream[0] : NULL;
		}
		default:
			return NULL;
	}
}

/* 表面首个 H.264 命令到达、FreeRDP 尚未为表面创建解码器时，用该命令的实际码流校验硬件解码；
 * 硬件失败而软件成功时打开 SoftwareGdi，FreeRDP 随后为该表面及之后的表面创建软件解码器 */
static void rmk_h264_verify_stream(RmkRdp* rdp, RdpgfxClientContext* gfx,
                                   const RDPGFX_SURFACE_COMMAND* cmd)
{
	rdpSettings* settings = rdp->context->settings;
	if (freerdp_settings_get_bool(settings, FreeRDP_SoftwareGdi))
		return;
	const RDPGFX_AVC420_BITMAP_STREAM* bs = rmk_h264_main_stream(cmd);
	if (!bs || !bs->data || bs->length == 0 || !bs->meta.regionRects ||
	    bs->meta.numRegionRects == 0 || !gfx->GetSurfaceData)
		return;
	gdiGfxSurface* surface =
	    (gdiGfxSurface*)gfx->GetSurfaceData(gfx, (UINT16)MIN(UINT16_MAX, cmd->surfaceId));
	/* 解码器已创建说明已校验或已在使用；同尺寸表面已校验通过则不重复校验（调整分辨率会重建表面） */
	if (!surface || surface->h264 || surface->width == 0 || surface->height == 0 ||
	    (surface->width == rdp->h264_verified_width && surface->height == rdp->h264_verified_height))
		return;
	const int32_t result =
	    rmk_h264_check_stream(bs->data, bs->length, surface->width, surface->height,
	                          bs->meta.regionRects, bs->meta.numRegionRects);
	if (result == 1)
	{
		rdp->h264_verified_width = surface->width;
		rdp->h264_verified_height = surface->height;
	}
	else if (result == 0 && freerdp_settings_set_bool(settings, FreeRDP_SoftwareGdi, TRUE))
		rmk_emit(rdp, RMK_EV_H264_SOFTWARE, (int32_t)surface->width, (int32_t)surface->height, 0, 0,
		         NULL);
}

/* 包装 GDI 的表面命令处理：先校验 H.264 码流，再交给 FreeRDP 处理 */
static UINT rmk_gfx_surface_command(RdpgfxClientContext* gfx, const RDPGFX_SURFACE_COMMAND* cmd)
{
	rdpGdi* gdi = gfx ? (rdpGdi*)gfx->custom : NULL;
	RmkRdp* rdp = (gdi && gdi->context) ? ((RmkContext*)gdi->context)->owner : NULL;
	if (!rdp || !rdp->gfx_surface_command)
		return ERROR_INTERNAL_ERROR;
	if (cmd)
	{
		/* 与 GDI 处理表面命令时使用同一把锁，避免校验期间表面被删除 */
		EnterCriticalSection(&gfx->mux);
		rmk_h264_verify_stream(rdp, gfx, cmd);
		LeaveCriticalSection(&gfx->mux);
	}
	return rdp->gfx_surface_command(gfx, cmd);
}

/* GFX 通道建立后接管表面命令（每次通道重建 GDI 都会重新注册回调，这里随之重新接管） */
void rmk_h264_attach_gfx(RmkRdp* rdp, RdpgfxClientContext* gfx)
{
	if (!rdp || !gfx || !gfx->SurfaceCommand || gfx->SurfaceCommand == rmk_gfx_surface_command)
		return;
	rdp->gfx_surface_command = gfx->SurfaceCommand;
	rdp->h264_verified_width = rdp->h264_verified_height = 0;
	gfx->SurfaceCommand = rmk_gfx_surface_command;
}

/* 导出给 Dart：H.264 解码能力 */
int32_t rmk_rdp_h264_caps(void)
{
	return rmk_h264_caps();
}

/* 导出给 Dart：用 FreeRDP 的 AVC420 解码流程把一帧 H.264 解码为 BGRA（多平台自检测试用） */
int32_t rmk_rdp_h264_self_test(const uint8_t* data, int32_t size, int32_t width, int32_t height,
                               int32_t hardware, uint8_t* bgra)
{
	if (!data || size <= 0 || width <= 0 || height <= 0 || width > 8192 || height > 8192 || !bgra)
		return -100;
	/* 与连接时相同：按探测结果决定，硬件不可用时软件解码 */
	const int32_t caps = rmk_h264_caps();
	if ((caps & RMK_H264_DECODER) == 0)
		return -101;
	const BOOL useHardware = hardware != 0 && (caps & RMK_H264_HARDWARE) != 0;
	return rmk_h264_decode(data, (UINT32)size, (UINT32)width, (UINT32)height, useHardware, bgra,
	                       NULL, 0);
}

/* 导出给 Dart：平台硬件解码设备类型 */
const char* rmk_rdp_h264_hw_type(void)
{
	return rmk_hwdec_type();
}

/* 导出给 Dart：用实际码流检查硬件解码（多平台测试用，与连接中的校验相同） */
int32_t rmk_rdp_h264_stream_check(const uint8_t* data, int32_t size, int32_t width, int32_t height)
{
	if (!data || size <= 0 || width <= 0 || height <= 0 || width > 8192 || height > 8192)
		return -1;
	if ((rmk_h264_caps() & RMK_H264_DECODER) == 0)
		return -1;
	return rmk_h264_check_stream(data, (UINT32)size, (UINT32)width, (UINT32)height, NULL, 0);
}
