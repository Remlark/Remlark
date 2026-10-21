/*
 * H.264 硬件解码平台接口：每个平台在 rmk_hwdec_<平台>.c 中各自实现，由 CMake 按平台选择编译。
 * FreeRDP 通过 FFmpeg hwcontext 解码，设备类型与路径经环境变量 FREERDP_HWCTX_TYPE /
 * FREERDP_HWCTX_DEVICE 传给 FreeRDP（用户已手动设置时保留用户的值）。
 */
#ifndef RMK_HWDEC_H
#define RMK_HWDEC_H

/* 当前平台的 FFmpeg 硬件设备类型名（av_hwdevice_find_type_by_name 可识别） */
const char* rmk_hwdec_type(void);

/* 当前平台的硬件设备路径；NULL 表示使用系统默认设备 */
const char* rmk_hwdec_device(void);

/* 把设备类型与路径写入 FreeRDP 读取的环境变量（不覆盖已有值），连接前调用 */
void rmk_hwdec_prepare(void);

#endif
