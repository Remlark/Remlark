/* H.264 硬件解码（macOS）：VideoToolbox，系统自带，无需指定设备 */
#include <stdlib.h>

#include "rmk_hwdec.h"

/* VideoToolbox 设备类型 */
const char* rmk_hwdec_type(void)
{
	return "videotoolbox";
}

/* VideoToolbox 没有设备路径 */
const char* rmk_hwdec_device(void)
{
	return NULL;
}

/* 写入设备类型（不覆盖用户设置） */
void rmk_hwdec_prepare(void)
{
	setenv("FREERDP_HWCTX_TYPE", rmk_hwdec_type(), 0);
}
