/*
 * Remlark RDP 胶水库：在 FreeRDP 之上提供一组简单的 C 接口，供 Dart FFI 调用。
 * - 连接在独立线程中运行，事件通过回调通知 Dart（回调可能在任意线程触发）
 * - 画面使用 FreeRDP GDI 合成为 BGRA32，Dart 通过 rmk_rdp_take_frame 只取走变化区域
 * - 剪贴板（文本 + 文件）通过 cliprdr 通道实现，文件夹共享通过 rdpdr/drive 通道实现
 */
#ifndef REMLARK_RDP_H
#define REMLARK_RDP_H

#include <stdint.h>

#if defined(_WIN32)
#define RMK_API __declspec(dllexport)
#else
#define RMK_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* 事件类型 */
enum RmkEventType
{
	RMK_EV_CONNECTED = 1,      /* a=宽 b=高 */
	RMK_EV_FRAME = 2,          /* 有新画面可拷贝 */
	RMK_EV_RESIZE = 3,         /* a=宽 b=高 */
	RMK_EV_DISCONNECTED = 4,   /* a=FreeRDP 错误码（0 为正常断开） str=错误描述 */
	RMK_EV_AUTH_FAILED = 5,    /* 用户名或密码错误 str=错误描述 */
	RMK_EV_CERTIFICATE = 6,    /* a=0 首次记录 / a=1 指纹变化已拒绝 str=新指纹 */
	RMK_EV_CLIP_TEXT = 7,      /* 远程复制了文本 str=UTF-8 文本 */
	RMK_EV_CLIP_FILES = 8,     /* 远程复制的文件已下载到本地 str=以 \n 分隔的本地路径 */
	RMK_EV_CLIP_FILES_SKIPPED = 9, /* 远程复制的文件过大未下载 a=文件数 */
	RMK_EV_CLIP_FILES_PROGRESS = 10 /* 远程文件下载进度 a=已完成 KB b=总 KB */
};

/* 事件回调：str 为 malloc 分配的字符串（可能为 NULL），使用后需调用 rmk_rdp_free_string 释放 */
typedef void (*RmkEventCallback)(int64_t id, int32_t type, int32_t a, int32_t b, int32_t c,
                                 int32_t d, char* str);

typedef struct rmk_rdp RmkRdp;

/* 创建实例，id 由 Dart 分配，用于在回调中区分会话 */
RMK_API RmkRdp* rmk_rdp_new(int64_t id, RmkEventCallback callback);

/* 开始连接（异步）。字符串参数可为 NULL；known_fingerprint 为上次记录的证书指纹；
 * shared_dir 为映射到远程的本地目录（远程中显示为 \\tsclient\Remlark）；
 * temp_dir 用于存放从远程剪贴板下载的文件。成功启动返回 0 */
RMK_API int32_t rmk_rdp_connect(RmkRdp* rdp, const char* host, int32_t port, const char* username,
                                const char* password, const char* domain, int32_t width,
                                int32_t height, const char* shared_dir, int32_t clipboard,
                                const char* known_fingerprint, const char* temp_dir);

/* 设置出口代理（在 connect 之前调用）：type 0=不使用（忽略环境变量）1=HTTP 2=SOCKS5 */
RMK_API void rmk_rdp_set_proxy(RmkRdp* rdp, int32_t type, const char* host, int32_t port,
                               const char* username, const char* password);

/* 断开连接并等待连接线程退出 */
RMK_API void rmk_rdp_disconnect(RmkRdp* rdp);

/* 释放实例（会先断开） */
RMK_API void rmk_rdp_free(RmkRdp* rdp);

/* 取出自上次调用以来的变化区域（BGRA）：各区域像素依次紧密写入 dst（每块行距 = 块宽 * 4），
 * rects 依次写入 [x, y, w, h]，*nrects 为块数（rects 至少容纳 RMK_RDP_MAX_RECTS 块），
 * *full 为 1 表示整屏（单块覆盖整个画面）。返回写入字节数；没有变化返回 0；
 * dst 不足时返回所需字节数的负值（变化保留到下次） */
#define RMK_RDP_MAX_RECTS 16
RMK_API int32_t rmk_rdp_take_frame(RmkRdp* rdp, uint8_t* dst, int32_t dst_size, int32_t* width,
                                   int32_t* height, int32_t* rects, int32_t* nrects, int32_t* full);

/* 键盘：scancode 为 RDP 扫描码（扩展键 | 0x100） */
RMK_API void rmk_rdp_send_key(RmkRdp* rdp, int32_t scancode, int32_t down, int32_t repeat);

/* Unicode 字符输入（用于无法映射为扫描码的字符） */
RMK_API void rmk_rdp_send_unicode(RmkRdp* rdp, int32_t codepoint, int32_t down);

/* 鼠标：flags 为 RDP PTR_FLAGS_* 组合 */
RMK_API void rmk_rdp_send_mouse(RmkRdp* rdp, int32_t flags, int32_t x, int32_t y);

/* 请求远程调整分辨率（需要服务器支持 Display Control 通道） */
RMK_API void rmk_rdp_resize(RmkRdp* rdp, int32_t width, int32_t height);

/* 本地剪贴板变为文本 */
RMK_API void rmk_rdp_set_clipboard_text(RmkRdp* rdp, const char* utf8);

/* 本地剪贴板变为文件（paths 以 \n 分隔，可包含目录） */
RMK_API void rmk_rdp_set_clipboard_files(RmkRdp* rdp, const char* paths);

/* 释放回调中传出的字符串 */
RMK_API void rmk_rdp_free_string(char* str);

/* FreeRDP 版本 */
RMK_API const char* rmk_rdp_version(void);

#ifdef __cplusplus
}
#endif

#endif
