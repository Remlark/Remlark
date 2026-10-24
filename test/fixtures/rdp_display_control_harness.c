/* P-21：替换 FreeRDP 类型和发送函数，运行生产代码验证协议消息时序。 */
#include <assert.h>
#include <stddef.h>
typedef unsigned int UINT;
typedef unsigned int UINT32;
typedef int BOOL;
#define TRUE 1
#define FALSE 0
#define WINPR_UNUSED(x) (void)(x)
#define CHANNEL_RC_OK 0
#define DISPLAY_CONTROL_MONITOR_PRIMARY 1
#define ORIENTATION_LANDSCAPE 0
typedef struct {
    UINT32 Flags, Width, Height, Orientation, DesktopScaleFactor, DeviceScaleFactor;
} DISPLAY_CONTROL_MONITOR_LAYOUT;
typedef struct DispClientContext DispClientContext;
struct DispClientContext {
    void* custom;
    UINT (*SendMonitorLayout)(DispClientContext*, UINT32, DISPLAY_CONTROL_MONITOR_LAYOUT*);
};
typedef struct {
    DispClientContext* disp;
    BOOL disp_caps_received, connected;
    UINT32 pending_width, pending_height;
} RmkRdp;
static int sent;
/* 假服务端检查实际发送的尺寸与显示器数量。 */
static UINT record_layout(DispClientContext* ctx, UINT32 count, DISPLAY_CONTROL_MONITOR_LAYOUT* layout)
{
    WINPR_UNUSED(ctx);
    assert(count == 1);
    assert(layout->Width == 1600 && layout->Height == 900);
    sent++;
    return CHANNEL_RC_OK;
}
/* PRODUCTION_FUNCTIONS */
/* 验证协商前不发送、尺寸合并、断线隔离与重新协商。 */
int main(void)
{
    DispClientContext channel = { NULL, record_layout };
    RmkRdp rdp = { &channel, FALSE, TRUE, 1280, 800 };
    channel.custom = &rdp;
    rmk_apply_pending_resize(&rdp);
    assert(sent == 0 && rdp.pending_width == 1280);
    rdp.pending_width = 1600;
    rdp.pending_height = 900;
    rmk_apply_pending_resize(&rdp);
    assert(sent == 0);
    rmk_display_control_caps(&channel, 1, 8192, 8192);
    rmk_apply_pending_resize(&rdp);
    assert(sent == 1 && rdp.pending_width == 0);
    rmk_apply_pending_resize(&rdp);
    assert(sent == 1);
    rdp.pending_width = 1600;
    rdp.pending_height = 900;
    rdp.disp = NULL;
    rdp.disp_caps_received = FALSE;
    rmk_display_control_caps(&channel, 1, 8192, 8192);
    assert(!rdp.disp_caps_received);
    rmk_apply_pending_resize(&rdp);
    assert(sent == 1 && rdp.pending_width == 1600);
    rdp.disp = &channel;
    rmk_apply_pending_resize(&rdp);
    assert(sent == 1);
    rmk_display_control_caps(&channel, 0, 8192, 8192);
    rmk_apply_pending_resize(&rdp);
    assert(sent == 1);
    rmk_display_control_caps(&channel, 1, 8192, 8192);
    rdp.connected = FALSE;
    rmk_apply_pending_resize(&rdp);
    assert(sent == 1);
    rdp.connected = TRUE;
    rmk_apply_pending_resize(&rdp);
    assert(sent == 2 && rdp.pending_width == 0);
    /* 能力先于窗口调整到达：正常服务端仍可随后调整尺寸。 */
    rdp.disp_caps_received = FALSE;
    rmk_display_control_caps(&channel, 16, 8192, 8192);
    rmk_apply_pending_resize(&rdp);
    assert(sent == 2);
    rdp.pending_width = 1600;
    rdp.pending_height = 900;
    rmk_apply_pending_resize(&rdp);
    assert(sent == 3);
    /* 不提供显示控制能力：只保留待调整尺寸，不阻塞或断开已连接的会话。 */
    rdp.disp_caps_received = FALSE;
    rdp.pending_width = 1600;
    rdp.pending_height = 900;
    for (int i = 0; i < 100; i++)
        rmk_apply_pending_resize(&rdp);
    assert(sent == 3 && rdp.connected && rdp.pending_width == 1600);
    return 0;
}
