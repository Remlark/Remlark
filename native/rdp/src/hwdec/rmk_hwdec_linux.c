/*
 * H.264 硬件解码（Linux）：VAAPI。FreeRDP 默认只尝试 /dev/dri/renderD128，
 * 多显卡或该节点不可用时依次选择第一个可读写的渲染节点。
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "rmk_hwdec.h"

/* VAAPI 设备类型 */
const char* rmk_hwdec_type(void)
{
	return "vaapi";
}

/* 第一个可读写的 DRM 渲染节点（renderD128 ~ renderD135），没有时返回 NULL */
const char* rmk_hwdec_device(void)
{
	static char path[32];
	for (int i = 128; i < 136; i++)
	{
		snprintf(path, sizeof(path), "/dev/dri/renderD%d", i);
		if (access(path, R_OK | W_OK) == 0)
			return path;
	}
	return NULL;
}

/* 写入设备类型与渲染节点（不覆盖用户设置） */
void rmk_hwdec_prepare(void)
{
	setenv("FREERDP_HWCTX_TYPE", rmk_hwdec_type(), 0);
	const char* device = rmk_hwdec_device();
	if (device && !getenv("FREERDP_VAAPI_DEVICE"))
		setenv("FREERDP_HWCTX_DEVICE", device, 0);
}
