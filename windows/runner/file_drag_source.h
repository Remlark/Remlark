#ifndef RUNNER_FILE_DRAG_SOURCE_H_
#define RUNNER_FILE_DRAG_SOURCE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

// 拖出到资源管理器的一项：相对路径（\ 分隔）、是否目录、大小
struct DragOutEntry {
  std::wstring path;
  bool is_dir = false;
  uint64_t size = 0;
};

// 把 SFTP 远程文件拖到资源管理器：应用内拖动离开窗口时由 Dart 调用 start，
// 以 OLE 虚拟文件（CFSTR_FILEDESCRIPTORW + CFSTR_FILECONTENTS）开始系统拖动，
// 放下后资源管理器逐个文件请求内容，再经通道请求 Dart 下载到临时文件。
// 通道 remlark/file_drag（协议与 lib/utils/file_drag_out/file_drag_out_channel.dart 一致）：
// - start(session, entries: [{path, isDir, size}]) -> bool：开始系统拖动（左键需仍按下）
// - write(session, index, path)：原生调 Dart，把第 index 项下载到 path，完成后回复
// - ended(session)：原生调 Dart，拖动结束
class FileDragSource {
 public:
  // |view| 为 Flutter 视图窗口：拖动从该窗口开始，结束后向其补发左键松开
  FileDragSource(flutter::BinaryMessenger* messenger, HWND view);
  ~FileDragSource();

  FileDragSource(const FileDragSource&) = delete;
  FileDragSource& operator=(const FileDragSource&) = delete;

  // 请求 Dart 把第 |index| 项写到 |path|，阻塞到完成，返回是否成功。
  // 可在任意线程调用：后台线程投递到平台线程执行；平台线程上则继续处理消息直到完成
  bool RequestWrite(int session, int index, const std::wstring& path);

  // 本次拖动的临时目录（%TEMP%\Remlark-drag\<session>）
  static std::wstring SessionTempDir(int session);

 private:
  struct WriteRequest;

  // 隐藏消息窗口的窗口过程：在平台线程上开始拖动、执行写入请求
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

  // 处理 start 调用：检查左键状态并保存条目，随后投递消息开始拖动（先回复 Dart）
  void HandleStart(const flutter::EncodableValue* args,
                   std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // 开始系统拖动（阻塞到放下或取消）
  void RunDrag();

  // 在平台线程上调用 Dart 的 write
  void InvokeWrite(const std::shared_ptr<WriteRequest>& request);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND view_ = nullptr;
  HWND window_ = nullptr;
  DWORD platform_thread_ = 0;
  int pending_session_ = 0;
  std::vector<DragOutEntry> pending_entries_;
};

#endif  // RUNNER_FILE_DRAG_SOURCE_H_
