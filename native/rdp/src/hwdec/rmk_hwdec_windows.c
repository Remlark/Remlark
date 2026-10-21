/*
 * H.264 硬件解码（Windows）：D3D11VA。FreeRDP 在 Windows 上默认使用 DXVA2（D3D9），
 * D3D11VA 在 Windows 10 / 11 与 ARM64 显卡驱动上支持更好，因此显式指定。
 */
#include <stdlib.h>

#include "rmk_hwdec.h"

/* D3D11VA 设备类型 */
const char* rmk_hwdec_type(void)
{
	return "d3d11va";
}

/* 使用系统默认显卡 */
const char* rmk_hwdec_device(void)
{
	return NULL;
}

/* 写入设备类型（不覆盖用户设置）；FreeRDP 静态链接在同一 DLL 内，与本文件共用 CRT 环境变量 */
void rmk_hwdec_prepare(void)
{
	if (!getenv("FREERDP_HWCTX_TYPE"))
		_putenv_s("FREERDP_HWCTX_TYPE", rmk_hwdec_type());
}
