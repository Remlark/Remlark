/*
 * H.264（AVC420 / AVC444）解码：探测 FFmpeg 解码器与平台硬件解码，并据此配置连接参数。
 * 硬件设备由 hwdec/ 下的平台实现提供。探测时用硬件实际解码一帧内置画面并校验颜色：
 * 部分环境（虚拟机、驱动异常）能创建设备但无法解码，FreeRDP 此时不会回退，因此只有解码成功才启用硬件。
 */
#include <freerdp/codec/color.h>
#include <freerdp/codec/h264.h>
#include <libavcodec/avcodec.h>
#include <libavutil/hwcontext.h>
#include <stdlib.h>
#include <winpr/synch.h>

#include "hwdec/rmk_hwdec.h"
#include "rmk_h264_probe_frame.h"
#include "rmk_internal.h"

static INIT_ONCE rmk_h264_once = INIT_ONCE_STATIC_INIT;
static int32_t rmk_h264_caps_value = 0;

/* 用与连接相同的 FreeRDP AVC420 流程把一帧 H.264 解码为 BGRA；hardware 为 TRUE 时使用平台硬件设备 */
static INT32 rmk_h264_decode(const BYTE* data, UINT32 size, UINT32 width, UINT32 height,
                             BOOL hardware, BYTE* bgra)
{
	H264_CONTEXT* h264 = h264_context_new(FALSE);
	if (!h264)
		return -102;
	INT32 rc = -103;
	/* 与 gdi/gfx.c 相同：HW_ACCEL 为 TRUE 时 FFmpeg 使用硬件设备 */
	if (h264_context_set_option(h264, H264_CONTEXT_OPTION_HW_ACCEL, hardware) &&
	    h264_context_reset(h264, width, height))
	{
		const RECTANGLE_16 rect = { 0, 0, (UINT16)width, (UINT16)height };
		rc = avc420_decompress(h264, data, size, bgra, PIXEL_FORMAT_BGRA32, width * 4, width,
		                       height, &rect, 1);
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
	                                RMK_PROBE_HEIGHT, TRUE, bgra) >= 0 &&
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
	return rmk_h264_decode(data, (UINT32)size, (UINT32)width, (UINT32)height, useHardware, bgra);
}

/* 导出给 Dart：平台硬件解码设备类型 */
const char* rmk_rdp_h264_hw_type(void)
{
	return rmk_hwdec_type();
}
