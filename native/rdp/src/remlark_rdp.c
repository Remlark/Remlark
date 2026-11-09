/*
 * Remlark RDP 胶水库：连接管理、画面合成、输入、动态分辨率与证书校验。
 * 剪贴板逻辑见 rmk_clipboard.c，H.264 解码配置见 rmk_h264.c。
 */
#include <stdlib.h>
#include <string.h>

#include <freerdp/gdi/gdi.h>
#include <freerdp/channels/channels.h>
#include <freerdp/channels/disp.h>
#include <freerdp/client/cmdline.h>
#include <freerdp/crypto/certificate.h>
#include <freerdp/error.h>
#include <freerdp/version.h>
#include <freerdp/channels/cliprdr.h>
#include <winpr/crt.h>
#include <winpr/interlocked.h>

#include "rmk_internal.h"

/* 从 FreeRDP 实例取得会话 */
static RmkRdp* rmk_from_instance(freerdp* instance)
{
	if (!instance || !instance->context)
		return NULL;
	return ((RmkContext*)instance->context)->owner;
}

static RmkRdp* rmk_from_context(rdpContext* context)
{
	return context ? ((RmkContext*)context)->owner : NULL;
}

void rmk_emit(RmkRdp* rdp, int32_t type, int32_t a, int32_t b, int32_t c, int32_t d,
              const char* str)
{
	if (!rdp || !rdp->callback)
		return;
	rdp->callback(rdp->id, type, a, b, c, d, str ? _strdup(str) : NULL);
}

/* 释放并替换字符串 */
static void rmk_set_str(char** dst, const char* src)
{
	free(*dst);
	*dst = (src && src[0]) ? _strdup(src) : NULL;
}

/* ---------- 画面 ---------- */

/* 确保画面副本尺寸与 GDI 一致（重新分配后需整屏刷新） */
static void rmk_ensure_frame(RmkRdp* rdp, UINT32 w, UINT32 h)
{
	if (rdp->frame && rdp->frame_width == w && rdp->frame_height == h)
		return;
	free(rdp->frame);
	rdp->frame = calloc((size_t)w * h, 4);
	rdp->frame_width = rdp->frame ? w : 0;
	rdp->frame_height = rdp->frame ? h : 0;
	rdp->dirty_full = TRUE;
	rdp->ndirty = 0;
}

/* 两个矩形的外接矩形 */
static RmkRect rmk_rect_union(RmkRect a, RmkRect b)
{
	const INT32 l = a.x < b.x ? a.x : b.x;
	const INT32 t = a.y < b.y ? a.y : b.y;
	const INT32 r = (a.x + a.w) > (b.x + b.w) ? (a.x + a.w) : (b.x + b.w);
	const INT32 btm = (a.y + a.h) > (b.y + b.h) ? (a.y + a.h) : (b.y + b.h);
	RmkRect u = { l, t, r - l, btm - t };
	return u;
}

/* 两个矩形是否相交或相邻（相邻也合并，减少碎块） */
static BOOL rmk_rect_touch(RmkRect a, RmkRect b)
{
	return a.x <= b.x + b.w && b.x <= a.x + a.w && a.y <= b.y + b.h && b.y <= a.y + a.h;
}

/* 记录变化区域（调用方持有 frame_lock，区域已裁剪）：与已有区域相交则合并，块数超限合并为外接矩形，
 * 总面积超过半屏改为整屏 */
static void rmk_add_dirty(RmkRdp* rdp, RmkRect r)
{
	if (rdp->dirty_full || r.w <= 0 || r.h <= 0)
		return;
	for (int i = 0; i < rdp->ndirty;)
	{
		if (rmk_rect_touch(rdp->dirty[i], r))
		{
			/* 合并后从列表移除，继续与其余区域比较 */
			r = rmk_rect_union(rdp->dirty[i], r);
			rdp->dirty[i] = rdp->dirty[--rdp->ndirty];
			i = 0;
			continue;
		}
		i++;
	}
	if (rdp->ndirty == RMK_MAX_DIRTY)
	{
		for (int i = 0; i < rdp->ndirty; i++)
			r = rmk_rect_union(rdp->dirty[i], r);
		rdp->ndirty = 0;
	}
	rdp->dirty[rdp->ndirty++] = r;
	int64_t area = 0;
	for (int i = 0; i < rdp->ndirty; i++)
		area += (int64_t)rdp->dirty[i].w * rdp->dirty[i].h;
	if (area * 2 > (int64_t)rdp->frame_width * rdp->frame_height)
	{
		rdp->dirty_full = TRUE;
		rdp->ndirty = 0;
	}
}

/* 把 GDI 缓冲区中 [x, y, w, h] 区域拷贝到画面副本，并把 alpha 置为 255 */
static void rmk_copy_region(RmkRdp* rdp, rdpGdi* gdi, INT32 x, INT32 y, INT32 w, INT32 h)
{
	EnterCriticalSection(&rdp->frame_lock);
	rmk_ensure_frame(rdp, gdi->width, gdi->height);
	if (rdp->frame)
	{
		if (x < 0) { w += x; x = 0; }
		if (y < 0) { h += y; y = 0; }
		if (x + w > (INT32)gdi->width) w = (INT32)gdi->width - x;
		if (y + h > (INT32)gdi->height) h = (INT32)gdi->height - y;
		const size_t dstStride = (size_t)gdi->width * 4;
		for (INT32 row = 0; row < h; row++)
		{
			const BYTE* src = gdi->primary_buffer + (size_t)(y + row) * gdi->stride + (size_t)x * 4;
			BYTE* dst = rdp->frame + (size_t)(y + row) * dstStride + (size_t)x * 4;
			memcpy(dst, src, (size_t)w * 4);
			for (INT32 col = 0; col < w; col++)
				dst[col * 4 + 3] = 0xFF;
		}
		RmkRect r = { x, y, w, h };
		rmk_add_dirty(rdp, r);
	}
	LeaveCriticalSection(&rdp->frame_lock);
	/* 合并通知：Dart 拷贝之前不重复发送 */
	if (InterlockedCompareExchange(&rdp->frame_pending, 1, 0) == 0)
		rmk_emit(rdp, RMK_EV_FRAME, 0, 0, 0, 0, NULL);
}

static BOOL rmk_begin_paint(rdpContext* context)
{
	rdpGdi* gdi = context->gdi;
	if (gdi && gdi->primary && gdi->primary->hdc && gdi->primary->hdc->hwnd &&
	    gdi->primary->hdc->hwnd->invalid)
		gdi->primary->hdc->hwnd->invalid->null = TRUE;
	return TRUE;
}

static BOOL rmk_end_paint(rdpContext* context)
{
	RmkRdp* rdp = rmk_from_context(context);
	rdpGdi* gdi = context->gdi;
	if (!rdp || !gdi || !gdi->primary || !gdi->primary->hdc || !gdi->primary->hdc->hwnd)
		return TRUE;
	HGDI_WND hwnd = gdi->primary->hdc->hwnd;
	if (!hwnd->invalid || hwnd->invalid->null)
		return TRUE;
	rmk_copy_region(rdp, gdi, hwnd->invalid->x, hwnd->invalid->y, hwnd->invalid->w,
	                hwnd->invalid->h);
	return TRUE;
}

static BOOL rmk_desktop_resize(rdpContext* context)
{
	RmkRdp* rdp = rmk_from_context(context);
	rdpSettings* settings = context->settings;
	const UINT32 w = freerdp_settings_get_uint32(settings, FreeRDP_DesktopWidth);
	const UINT32 h = freerdp_settings_get_uint32(settings, FreeRDP_DesktopHeight);
	if (!gdi_resize(context->gdi, w, h))
		return FALSE;
	EnterCriticalSection(&rdp->frame_lock);
	rmk_ensure_frame(rdp, w, h);
	LeaveCriticalSection(&rdp->frame_lock);
	rmk_emit(rdp, RMK_EV_RESIZE, (int32_t)w, (int32_t)h, 0, 0, NULL);
	rmk_copy_region(rdp, context->gdi, 0, 0, (INT32)w, (INT32)h);
	return TRUE;
}

/* ---------- 通道 ---------- */

/* 发送待处理的分辨率调整 */
static void rmk_apply_pending_resize(RmkRdp* rdp)
{
	if (!rdp->disp || !rdp->disp_caps_received || !rdp->connected || rdp->pending_width == 0)
		return;
	DISPLAY_CONTROL_MONITOR_LAYOUT layout = { 0 };
	layout.Flags = DISPLAY_CONTROL_MONITOR_PRIMARY;
	layout.Width = rdp->pending_width;
	layout.Height = rdp->pending_height;
	layout.Orientation = ORIENTATION_LANDSCAPE;
	layout.DesktopScaleFactor = 100;
	layout.DeviceScaleFactor = 100;
	rdp->pending_width = rdp->pending_height = 0;
	(void)rdp->disp->SendMonitorLayout(rdp->disp, 1, &layout);
}

/* 通道建立不代表服务端已就绪；能力协商完成后由连接线程发送最新的待处理尺寸。 */
static UINT rmk_display_control_caps(DispClientContext* context, UINT32 max_monitors,
                                     UINT32 area_factor_a, UINT32 area_factor_b)
{
	WINPR_UNUSED(area_factor_a);
	WINPR_UNUSED(area_factor_b);
	RmkRdp* rdp = (RmkRdp*)context->custom;
	if (rdp && rdp->disp == context)
		rdp->disp_caps_received = max_monitors > 0;
	return CHANNEL_RC_OK;
}

/* 注册通道回调，每次重定向或重连都重新等待能力消息。 */
static void rmk_on_channel_connected(void* ctx, const ChannelConnectedEventArgs* e)
{
	RmkContext* context = (RmkContext*)ctx;
	RmkRdp* rdp = context->owner;
	if (strcmp(e->name, CLIPRDR_SVC_CHANNEL_NAME) == 0)
	{
		if (rdp->clipboard_enabled)
			rmk_clip_attach(rdp->clip, (CliprdrClientContext*)e->pInterface);
	}
	else if (strcmp(e->name, DISP_DVC_CHANNEL_NAME) == 0)
	{
		rdp->disp_caps_received = FALSE;
		rdp->disp = (DispClientContext*)e->pInterface;
		rdp->disp->custom = rdp;
		rdp->disp->DisplayControlCaps = rmk_display_control_caps;
	}
	else
	{
		freerdp_client_OnChannelConnectedEventHandler(ctx, e);
		/* GDI 注册 GFX 回调之后再接管表面命令，用实际视频流校验硬件解码 */
		if (strcmp(e->name, RDPGFX_DVC_CHANNEL_NAME) == 0)
			rmk_h264_attach_gfx(rdp, (RdpgfxClientContext*)e->pInterface);
	}
}

/* 断开显示通道时清除旧能力，避免下次连接提前发送布局。 */
static void rmk_on_channel_disconnected(void* ctx, const ChannelDisconnectedEventArgs* e)
{
	RmkContext* context = (RmkContext*)ctx;
	RmkRdp* rdp = context->owner;
	if (strcmp(e->name, CLIPRDR_SVC_CHANNEL_NAME) == 0)
		rmk_clip_detach(rdp->clip);
	else if (strcmp(e->name, DISP_DVC_CHANNEL_NAME) == 0)
	{
		rdp->disp_caps_received = FALSE;
		rdp->disp = NULL;
	}
	else
		freerdp_client_OnChannelDisconnectedEventHandler(ctx, e);
}

/* ---------- 连接回调 ---------- */

static BOOL rmk_pre_connect(freerdp* instance)
{
	rdpContext* context = instance->context;
	if (!freerdp_settings_set_uint32(context->settings, FreeRDP_OsMajorType, OSMAJORTYPE_UNIX))
		return FALSE;
	PubSub_SubscribeChannelConnected(context->pubSub, rmk_on_channel_connected);
	PubSub_SubscribeChannelDisconnected(context->pubSub, rmk_on_channel_disconnected);
	return TRUE;
}

static BOOL rmk_post_connect(freerdp* instance)
{
	RmkRdp* rdp = rmk_from_instance(instance);
	if (!gdi_init(instance, PIXEL_FORMAT_BGRA32))
		return FALSE;
	rdpContext* context = instance->context;
	context->update->BeginPaint = rmk_begin_paint;
	context->update->EndPaint = rmk_end_paint;
	context->update->DesktopResize = rmk_desktop_resize;
	rdpGdi* gdi = context->gdi;
	EnterCriticalSection(&rdp->frame_lock);
	rmk_ensure_frame(rdp, gdi->width, gdi->height);
	LeaveCriticalSection(&rdp->frame_lock);
	rdp->connected = TRUE;
	rmk_emit(rdp, RMK_EV_CONNECTED, (int32_t)gdi->width, (int32_t)gdi->height, 0, 0, NULL);
	return TRUE;
}

static void rmk_post_disconnect(freerdp* instance)
{
	if (!instance || !instance->context)
		return;
	PubSub_UnsubscribeChannelConnected(instance->context->pubSub, rmk_on_channel_connected);
	PubSub_UnsubscribeChannelDisconnected(instance->context->pubSub, rmk_on_channel_disconnected);
	gdi_free(instance);
}

/* 凭据缺失时不弹出交互（由 Dart 侧负责询问密码），直接失败 */
static BOOL rmk_authenticate(freerdp* instance, char** username, char** password, char** domain,
                             rdp_auth_reason reason)
{
	WINPR_UNUSED(instance);
	WINPR_UNUSED(domain);
	WINPR_UNUSED(reason);
	return (*username && **username && *password && **password);
}

/* 证书校验（TOFU）：首次记录指纹，之后指纹变化则拒绝并通知 Dart 由用户决定 */
static int rmk_verify_x509(freerdp* instance, const BYTE* data, size_t length,
                           const char* hostname, UINT16 port, DWORD flags)
{
	WINPR_UNUSED(length);
	WINPR_UNUSED(hostname);
	WINPR_UNUSED(port);
	WINPR_UNUSED(flags);
	RmkRdp* rdp = rmk_from_instance(instance);
	rdpCertificate* cert = freerdp_certificate_new_from_pem((const char*)data);
	if (!cert)
		return -1;
	char* fp = freerdp_certificate_get_fingerprint_by_hash(cert, "sha256");
	freerdp_certificate_free(cert);
	if (!fp)
		return -1;
	int result = 1;
	if (!rdp->known_fingerprint)
		rmk_emit(rdp, RMK_EV_CERTIFICATE, 0, 0, 0, 0, fp);
	else if (_stricmp(rdp->known_fingerprint, fp) != 0)
	{
		rmk_emit(rdp, RMK_EV_CERTIFICATE, 1, 0, 0, 0, fp);
		result = 0;
	}
	free(fp);
	return result;
}

static int rmk_logon_error(freerdp* instance, UINT32 data, UINT32 type)
{
	WINPR_UNUSED(instance);
	WINPR_UNUSED(data);
	WINPR_UNUSED(type);
	return 1;
}

static BOOL rmk_client_new(freerdp* instance, rdpContext* context)
{
	WINPR_UNUSED(context);
	instance->PreConnect = rmk_pre_connect;
	instance->PostConnect = rmk_post_connect;
	instance->PostDisconnect = rmk_post_disconnect;
	instance->AuthenticateEx = rmk_authenticate;
	instance->VerifyX509Certificate = rmk_verify_x509;
	instance->LogonErrorInfo = rmk_logon_error;
	return TRUE;
}

static void rmk_client_free(freerdp* instance, rdpContext* context)
{
	WINPR_UNUSED(instance);
	WINPR_UNUSED(context);
}

static int rmk_client_start(rdpContext* context)
{
	WINPR_UNUSED(context);
	return 0;
}

static int rmk_client_stop(rdpContext* context)
{
	WINPR_UNUSED(context);
	return 0;
}

/* 是否为认证失败类错误 */
static BOOL rmk_is_auth_error(UINT32 code)
{
	switch (code)
	{
		case FREERDP_ERROR_AUTHENTICATION_FAILED:
		case FREERDP_ERROR_CONNECT_LOGON_FAILURE:
		case FREERDP_ERROR_CONNECT_WRONG_PASSWORD:
		case FREERDP_ERROR_CONNECT_NO_OR_MISSING_CREDENTIALS:
			return TRUE;
		default:
			return FALSE;
	}
}

/* 连接线程：建立连接后循环处理事件，直到断开 */
static DWORD WINAPI rmk_thread_proc(LPVOID arg)
{
	RmkRdp* rdp = (RmkRdp*)arg;
	freerdp* instance = rdp->context->instance;
	UINT32 error = 0;

	if (!freerdp_connect(instance))
	{
		error = freerdp_get_last_error(rdp->context);
		if (rmk_is_auth_error(error))
			rmk_emit(rdp, RMK_EV_AUTH_FAILED, (int32_t)error, 0, 0, 0,
			         freerdp_get_last_error_string(error));
		goto out;
	}

	rmk_apply_pending_resize(rdp);
	while (!freerdp_shall_disconnect_context(rdp->context))
	{
		HANDLE handles[MAXIMUM_WAIT_OBJECTS] = { 0 };
		const DWORD count = freerdp_get_event_handles(rdp->context, handles, ARRAYSIZE(handles));
		if (count == 0)
			break;
		if (WaitForMultipleObjects(count, handles, FALSE, 100) == WAIT_FAILED)
			break;
		if (!freerdp_check_event_handles(rdp->context))
			break;
		/* disp 通道就绪后发送待处理的分辨率调整 */
		if (rdp->pending_width)
			rmk_apply_pending_resize(rdp);
	}
	error = freerdp_get_last_error(rdp->context);

out:
	rdp->connected = FALSE;
	freerdp_disconnect(instance);
	rmk_emit(rdp, RMK_EV_DISCONNECTED, (int32_t)error, 0, 0, 0,
	         error ? freerdp_get_last_error_string(error) : NULL);
	return 0;
}

/* ---------- 导出接口 ---------- */

RmkRdp* rmk_rdp_new(int64_t id, RmkEventCallback callback)
{
	RmkRdp* rdp = calloc(1, sizeof(RmkRdp));
	if (!rdp)
		return NULL;
	rdp->id = id;
	rdp->callback = callback;
	rdp->hwdec_enabled = TRUE;
	rdp->audio_enabled = TRUE;
	InitializeCriticalSection(&rdp->frame_lock);
	rdp->clip = rmk_clip_new(rdp);
	return rdp;
}

/* 远程声音：开启时 freerdp_client_load_addins 按 AudioPlayback 加载 rdpsnd 静态与动态通道（并开启依赖的 rdpdr），
 * 不指定播放后端，由 FreeRDP 按编译进来的后端依次尝试：macOS mac（AudioToolbox）、Windows winmm、
 * Linux pulse → alsa，全部不可用时退回 fake（静音，连接不受影响）。
 * 关闭时登录信息带 INFO_NOAUDIOPLAYBACK，服务器不发送声音；rdpdr 开启时 FreeRDP 仍会加载 sys:fake 的 rdpsnd 满足协议要求 */
static BOOL rmk_apply_audio(rdpSettings* s, BOOL enabled)
{
	return freerdp_settings_set_bool(s, FreeRDP_AudioPlayback, enabled);
}

/* 设置字符串参数，空值跳过 */
static BOOL rmk_set_setting(rdpSettings* s, FreeRDP_Settings_Keys_String key, const char* v)
{
	return (!v || !v[0]) ? TRUE : freerdp_settings_set_string(s, key, v);
}

int32_t rmk_rdp_connect(RmkRdp* rdp, const char* host, int32_t port, const char* username,
                        const char* password, const char* domain, int32_t width, int32_t height,
                        const char* shared_dir, int32_t clipboard, const char* known_fingerprint,
                        const char* temp_dir)
{
	if (!rdp || rdp->thread)
		return -1;
	RDP_CLIENT_ENTRY_POINTS entry = { 0 };
	entry.Version = RDP_CLIENT_INTERFACE_VERSION;
	entry.Size = sizeof(RDP_CLIENT_ENTRY_POINTS_V1);
	entry.ContextSize = sizeof(RmkContext);
	entry.ClientNew = rmk_client_new;
	entry.ClientFree = rmk_client_free;
	entry.ClientStart = rmk_client_start;
	entry.ClientStop = rmk_client_stop;
	rdp->context = freerdp_client_context_new(&entry);
	if (!rdp->context)
		return -2;
	((RmkContext*)rdp->context)->owner = rdp;

	rmk_set_str(&rdp->known_fingerprint, known_fingerprint);
	rmk_set_str(&rdp->temp_dir, temp_dir);
	rdp->clipboard_enabled = clipboard != 0;
	rdp->pending_width = rdp->pending_height = 0;

	rdpSettings* s = rdp->context->settings;
	const UINT32 w = (UINT32)(width > 0 ? width : 1280) & ~1u;
	const UINT32 h = (UINT32)(height > 0 ? height : 800);
	BOOL ok = freerdp_settings_set_string(s, FreeRDP_ServerHostname, host) &&
	          freerdp_settings_set_uint32(s, FreeRDP_ServerPort, (UINT32)(port > 0 ? port : 3389)) &&
	          rmk_set_setting(s, FreeRDP_Username, username) &&
	          rmk_set_setting(s, FreeRDP_Password, password) &&
	          rmk_set_setting(s, FreeRDP_Domain, domain) &&
	          freerdp_settings_set_string(s, FreeRDP_ClientHostname, "remlark") &&
	          freerdp_settings_set_uint32(s, FreeRDP_DesktopWidth, w) &&
	          freerdp_settings_set_uint32(s, FreeRDP_DesktopHeight, h) &&
	          freerdp_settings_set_uint32(s, FreeRDP_ColorDepth, 32) &&
	          freerdp_settings_set_bool(s, FreeRDP_SupportGraphicsPipeline, TRUE) &&
	          rmk_h264_apply(s, rdp->hwdec_enabled) &&
	          freerdp_settings_set_bool(s, FreeRDP_RemoteFxCodec, TRUE) &&
	          freerdp_settings_set_bool(s, FreeRDP_NSCodec, TRUE) &&
	          freerdp_settings_set_bool(s, FreeRDP_SupportDisplayControl, TRUE) &&
	          freerdp_settings_set_bool(s, FreeRDP_DynamicResolutionUpdate, TRUE) &&
	          freerdp_settings_set_bool(s, FreeRDP_NetworkAutoDetect, TRUE) &&
	          freerdp_settings_set_bool(s, FreeRDP_ExternalCertificateManagement, TRUE) &&
	          freerdp_settings_set_bool(s, FreeRDP_RedirectClipboard, clipboard != 0) &&
	          rmk_apply_audio(s, rdp->audio_enabled);
	/* 出口代理：未配置时忽略 http_proxy 等环境变量，避免被系统代理影响 */
	if (ok && rdp->proxy_type && rdp->proxy_host)
	{
		ok = freerdp_settings_set_uint32(s, FreeRDP_ProxyType,
		                                 rdp->proxy_type == 1 ? PROXY_TYPE_HTTP : PROXY_TYPE_SOCKS) &&
		     freerdp_settings_set_string(s, FreeRDP_ProxyHostname, rdp->proxy_host) &&
		     freerdp_settings_set_uint16(s, FreeRDP_ProxyPort, rdp->proxy_port) &&
		     rmk_set_setting(s, FreeRDP_ProxyUsername, rdp->proxy_user) &&
		     rmk_set_setting(s, FreeRDP_ProxyPassword, rdp->proxy_pass);
	}
	else if (ok)
		ok = freerdp_settings_set_uint32(s, FreeRDP_ProxyType, PROXY_TYPE_IGNORE);
	if (ok && shared_dir && shared_dir[0])
	{
		const char* params[] = { "drive", "Remlark", shared_dir };
		ok = freerdp_settings_set_bool(s, FreeRDP_DeviceRedirection, TRUE) &&
		     freerdp_client_add_device_channel(s, 3, params);
	}
	if (!ok)
	{
		freerdp_client_context_free(rdp->context);
		rdp->context = NULL;
		return -3;
	}
	rdp->thread = CreateThread(NULL, 0, rmk_thread_proc, rdp, 0, NULL);
	return rdp->thread ? 0 : -4;
}

void rmk_rdp_set_proxy(RmkRdp* rdp, int32_t type, const char* host, int32_t port,
                       const char* username, const char* password)
{
	if (!rdp)
		return;
	rdp->proxy_type = (UINT32)(type == 1 || type == 2 ? type : 0);
	rmk_set_str(&rdp->proxy_host, host);
	rdp->proxy_port = (UINT16)port;
	rmk_set_str(&rdp->proxy_user, username);
	rmk_set_str(&rdp->proxy_pass, password);
}

/* 记录是否播放远程声音，连接时生效 */
void rmk_rdp_set_audio(RmkRdp* rdp, int32_t enabled)
{
	if (rdp)
		rdp->audio_enabled = enabled != 0;
}

/* 记录是否允许 H.264 硬件解码，连接时生效 */
void rmk_rdp_set_hwdec(RmkRdp* rdp, int32_t enabled)
{
	if (rdp)
		rdp->hwdec_enabled = enabled != 0;
}

void rmk_rdp_disconnect(RmkRdp* rdp)
{
	if (!rdp || !rdp->context)
		return;
	freerdp_abort_connect_context(rdp->context);
	if (rdp->thread)
	{
		WaitForSingleObject(rdp->thread, INFINITE);
		CloseHandle(rdp->thread);
		rdp->thread = NULL;
	}
	rmk_clip_detach(rdp->clip);
	rdp->disp_caps_received = FALSE;
	rdp->disp = NULL;
	freerdp_client_context_free(rdp->context);
	rdp->context = NULL;
}

void rmk_rdp_free(RmkRdp* rdp)
{
	if (!rdp)
		return;
	rmk_rdp_disconnect(rdp);
	rmk_clip_free(rdp->clip);
	DeleteCriticalSection(&rdp->frame_lock);
	free(rdp->frame);
	free(rdp->known_fingerprint);
	free(rdp->temp_dir);
	free(rdp->proxy_host);
	free(rdp->proxy_user);
	free(rdp->proxy_pass);
	free(rdp);
}

int32_t rmk_rdp_take_frame(RmkRdp* rdp, uint8_t* dst, int32_t dst_size, int32_t* width,
                           int32_t* height, int32_t* rects, int32_t* nrects, int32_t* full)
{
	*nrects = 0;
	*full = 0;
	if (!rdp)
		return 0;
	EnterCriticalSection(&rdp->frame_lock);
	*width = (int32_t)rdp->frame_width;
	*height = (int32_t)rdp->frame_height;
	/* 先清除通知标志：之后到达的变化会重新通知 */
	InterlockedExchange(&rdp->frame_pending, 0);
	if (!rdp->frame || (!rdp->dirty_full && rdp->ndirty == 0))
	{
		LeaveCriticalSection(&rdp->frame_lock);
		return 0;
	}
	RmkRect list[RMK_MAX_DIRTY];
	int n = rdp->ndirty;
	if (rdp->dirty_full)
	{
		RmkRect all = { 0, 0, (INT32)rdp->frame_width, (INT32)rdp->frame_height };
		list[0] = all;
		n = 1;
	}
	else
		memcpy(list, rdp->dirty, sizeof(RmkRect) * (size_t)n);
	int64_t need = 0;
	for (int i = 0; i < n; i++)
		need += (int64_t)list[i].w * list[i].h * 4;
	if (need > dst_size)
	{
		LeaveCriticalSection(&rdp->frame_lock);
		return (int32_t)-need;
	}
	/* 按区域逐行拷贝，像素紧密排列 */
	const size_t stride = (size_t)rdp->frame_width * 4;
	uint8_t* out = dst;
	for (int i = 0; i < n; i++)
	{
		const RmkRect r = list[i];
		const size_t rowBytes = (size_t)r.w * 4;
		for (INT32 row = 0; row < r.h; row++)
		{
			memcpy(out, rdp->frame + (size_t)(r.y + row) * stride + (size_t)r.x * 4, rowBytes);
			out += rowBytes;
		}
		rects[i * 4] = r.x;
		rects[i * 4 + 1] = r.y;
		rects[i * 4 + 2] = r.w;
		rects[i * 4 + 3] = r.h;
	}
	*nrects = n;
	*full = rdp->dirty_full ? 1 : 0;
	rdp->ndirty = 0;
	rdp->dirty_full = FALSE;
	LeaveCriticalSection(&rdp->frame_lock);
	return (int32_t)need;
}

void rmk_rdp_send_key(RmkRdp* rdp, int32_t scancode, int32_t down, int32_t repeat)
{
	if (rdp && rdp->connected)
		(void)freerdp_input_send_keyboard_event_ex(rdp->context->input, down != 0, repeat != 0,
		                                           (UINT32)scancode);
}

void rmk_rdp_send_unicode(RmkRdp* rdp, int32_t codepoint, int32_t down)
{
	if (rdp && rdp->connected && codepoint > 0 && codepoint <= 0xFFFF)
		(void)freerdp_input_send_unicode_keyboard_event(rdp->context->input,
		                                                down ? 0 : KBD_FLAGS_RELEASE,
		                                                (UINT16)codepoint);
}

void rmk_rdp_send_mouse(RmkRdp* rdp, int32_t flags, int32_t x, int32_t y)
{
	if (rdp && rdp->connected)
		(void)freerdp_input_send_mouse_event(rdp->context->input, (UINT16)flags,
		                                     (UINT16)(x < 0 ? 0 : x), (UINT16)(y < 0 ? 0 : y));
}

void rmk_rdp_resize(RmkRdp* rdp, int32_t width, int32_t height)
{
	if (!rdp || width < 200 || height < 200)
		return;
	/* 宽度需为偶数，范围 200~8192；实际发送在连接线程中进行 */
	rdp->pending_height = (UINT32)(height > 8192 ? 8192 : height);
	rdp->pending_width = ((UINT32)(width > 8192 ? 8192 : width)) & ~1u;
}

void rmk_rdp_set_clipboard_text(RmkRdp* rdp, const char* utf8)
{
	if (rdp)
		rmk_clip_set_text(rdp->clip, utf8);
}

void rmk_rdp_set_clipboard_files(RmkRdp* rdp, const char* paths)
{
	if (rdp)
		rmk_clip_set_files(rdp->clip, paths);
}

void rmk_rdp_free_string(char* str)
{
	free(str);
}

const char* rmk_rdp_version(void)
{
	return freerdp_get_version_string();
}
