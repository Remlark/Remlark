/* Remlark RDP 内部定义：会话结构与模块间共享函数 */
#ifndef RMK_INTERNAL_H
#define RMK_INTERNAL_H

#include <freerdp/freerdp.h>
#include <freerdp/client.h>
#include <freerdp/client/cliprdr.h>
#include <freerdp/client/disp.h>
#include <winpr/synch.h>
#include <winpr/thread.h>

#include "remlark_rdp.h"

typedef struct rmk_clip RmkClipboard;

/* 变化区域最多分别记录的块数，超过后合并为外接矩形 */
#define RMK_MAX_DIRTY 16

/* 矩形区域 */
typedef struct
{
	INT32 x, y, w, h;
} RmkRect;

/* 会话 */
struct rmk_rdp
{
	int64_t id;
	RmkEventCallback callback;

	rdpContext* context;
	HANDLE thread;
	volatile BOOL connected;

	/* 画面副本（BGRA，行距 = 宽 * 4），由 frame_lock 保护 */
	CRITICAL_SECTION frame_lock;
	BYTE* frame;
	UINT32 frame_width;
	UINT32 frame_height;
	volatile LONG frame_pending;
	/* 自上次 Dart 取走以来的变化区域（frame_lock 保护）；dirty_full 表示整屏 */
	RmkRect dirty[RMK_MAX_DIRTY];
	int ndirty;
	BOOL dirty_full;

	/* 连接参数 */
	char* known_fingerprint;
	char* temp_dir;
	BOOL clipboard_enabled;
	BOOL hwdec_enabled; /* 是否允许 H.264 硬件解码（用户设置，默认允许） */

	/* 出口代理 */
	UINT32 proxy_type;
	char* proxy_host;
	UINT16 proxy_port;
	char* proxy_user;
	char* proxy_pass;

	/* 动态分辨率 */
	DispClientContext* disp;
	BOOL disp_caps_received; /* 收到服务端能力后才能发送显示布局，每次通道重建均重置 */
	UINT32 pending_width;
	UINT32 pending_height;

	RmkClipboard* clip;
};

/* FreeRDP 客户端上下文：common 必须是第一个成员 */
typedef struct
{
	rdpClientContext common;
	RmkRdp* owner;
} RmkContext;

/* 向 Dart 发送事件（str 会被复制） */
void rmk_emit(RmkRdp* rdp, int32_t type, int32_t a, int32_t b, int32_t c, int32_t d,
              const char* str);

/* H.264 模块（rmk_h264.c）：探测解码能力（结果缓存）并按结果配置连接参数 */
int32_t rmk_h264_caps(void);
BOOL rmk_h264_apply(rdpSettings* settings, BOOL hw_enabled);

/* 剪贴板模块 */
RmkClipboard* rmk_clip_new(RmkRdp* rdp);
void rmk_clip_free(RmkClipboard* clip);
void rmk_clip_attach(RmkClipboard* clip, CliprdrClientContext* cliprdr);
void rmk_clip_detach(RmkClipboard* clip);
void rmk_clip_set_text(RmkClipboard* clip, const char* utf8);
void rmk_clip_set_files(RmkClipboard* clip, const char* paths);

#endif
