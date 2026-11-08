#include "file_drag_source.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <ole2.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <shlwapi.h>

#include <algorithm>
#include <filesystem>
#include <variant>

#include "utils.h"

namespace {

constexpr UINT kStartDragMessage = WM_APP + 0x41;
constexpr UINT kWriteMessage = WM_APP + 0x42;
constexpr wchar_t kWindowClass[] = L"RemlarkFileDragSource";

// 从通道参数中取值（类型不符返回默认值）
template <typename T>
T MapValue(const flutter::EncodableMap& map, const char* key, T fallback) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return fallback;
  if (const T* v = std::get_if<T>(&it->second)) return *v;
  return fallback;
}

// 整数可能以 int32 或 int64 传来
int64_t MapInt(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return 0;
  if (const int32_t* v = std::get_if<int32_t>(&it->second)) return *v;
  if (const int64_t* v = std::get_if<int64_t>(&it->second)) return *v;
  return 0;
}

// 资源管理器使用的虚拟文件数据对象：
// 文件描述与拖动图像等由系统数据对象（SHCreateDataObject）保存，本对象只负责按需提供文件内容；
// 声明支持异步提取，资源管理器在后台线程请求内容，不阻塞界面
class DragDataObject : public IDataObject, public IDataObjectAsyncCapability {
 public:
  DragDataObject(FileDragSource* owner, int session, std::vector<DragOutEntry> entries, IDataObject* inner)
      : owner_(owner), session_(session), entries_(std::move(entries)), inner_(inner),
        written_(entries_.size(), false) {
    inner_->AddRef();
    cf_descriptor_ = static_cast<CLIPFORMAT>(::RegisterClipboardFormatW(CFSTR_FILEDESCRIPTORW));
    cf_contents_ = static_cast<CLIPFORMAT>(::RegisterClipboardFormatW(CFSTR_FILECONTENTS));
    cf_effect_ = static_cast<CLIPFORMAT>(::RegisterClipboardFormatW(CFSTR_PREFERREDDROPEFFECT));
    StoreDescriptors();
    StorePreferredEffect();
  }

  // IUnknown
  IFACEMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
    if (ppv == nullptr) return E_POINTER;
    if (riid == IID_IUnknown || riid == IID_IDataObject) {
      *ppv = static_cast<IDataObject*>(this);
    } else if (riid == IID_IDataObjectAsyncCapability) {
      *ppv = static_cast<IDataObjectAsyncCapability*>(this);
    } else {
      *ppv = nullptr;
      return E_NOINTERFACE;
    }
    AddRef();
    return S_OK;
  }
  IFACEMETHODIMP_(ULONG) AddRef() override { return static_cast<ULONG>(::InterlockedIncrement(&refs_)); }
  IFACEMETHODIMP_(ULONG) Release() override {
    ULONG refs = static_cast<ULONG>(::InterlockedDecrement(&refs_));
    if (refs == 0) delete this;
    return refs;
  }

  // IDataObject：文件内容由本对象提供，其余交给系统数据对象
  IFACEMETHODIMP GetData(FORMATETC* format, STGMEDIUM* medium) override {
    if (format == nullptr || medium == nullptr) return E_INVALIDARG;
    if (format->cfFormat == cf_contents_ && (format->tymed & TYMED_ISTREAM)) {
      return GetContents(format->lindex, medium);
    }
    return inner_->GetData(format, medium);
  }
  IFACEMETHODIMP GetDataHere(FORMATETC* format, STGMEDIUM* medium) override {
    return inner_->GetDataHere(format, medium);
  }
  IFACEMETHODIMP QueryGetData(FORMATETC* format) override {
    if (format != nullptr && format->cfFormat == cf_contents_) {
      return (format->tymed & TYMED_ISTREAM) ? S_OK : DV_E_TYMED;
    }
    return inner_->QueryGetData(format);
  }
  IFACEMETHODIMP GetCanonicalFormatEtc(FORMATETC* in, FORMATETC* out) override {
    return inner_->GetCanonicalFormatEtc(in, out);
  }
  IFACEMETHODIMP SetData(FORMATETC* format, STGMEDIUM* medium, BOOL release) override {
    return inner_->SetData(format, medium, release);
  }
  IFACEMETHODIMP EnumFormatEtc(DWORD direction, IEnumFORMATETC** out) override {
    if (direction != DATADIR_GET) return E_NOTIMPL;
    FORMATETC formats[] = {
        {cf_descriptor_, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL},
        {cf_contents_, nullptr, DVASPECT_CONTENT, -1, TYMED_ISTREAM},
        {cf_effect_, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL},
    };
    return ::SHCreateStdEnumFmtEtc(ARRAYSIZE(formats), formats, out);
  }
  IFACEMETHODIMP DAdvise(FORMATETC*, DWORD, IAdviseSink*, DWORD*) override { return OLE_E_ADVISENOTSUPPORTED; }
  IFACEMETHODIMP DUnadvise(DWORD) override { return OLE_E_ADVISENOTSUPPORTED; }
  IFACEMETHODIMP EnumDAdvise(IEnumSTATDATA**) override { return OLE_E_ADVISENOTSUPPORTED; }

  // IDataObjectAsyncCapability：支持异步提取
  IFACEMETHODIMP SetAsyncMode(BOOL async) override {
    async_ = async;
    return S_OK;
  }
  IFACEMETHODIMP GetAsyncMode(BOOL* async) override {
    if (async == nullptr) return E_POINTER;
    *async = async_;
    return S_OK;
  }
  IFACEMETHODIMP StartOperation(IBindCtx*) override {
    in_operation_ = TRUE;
    return S_OK;
  }
  IFACEMETHODIMP InOperation(BOOL* in) override {
    if (in == nullptr) return E_POINTER;
    *in = in_operation_;
    return S_OK;
  }
  IFACEMETHODIMP EndOperation(HRESULT, IBindCtx*, DWORD) override {
    in_operation_ = FALSE;
    return S_OK;
  }

 private:
  ~DragDataObject() { inner_->Release(); }

  // 写入文件描述：每项一条，目录带目录属性，文件带大小以显示进度
  void StoreDescriptors() {
    const size_t count = entries_.size();
    const size_t bytes = sizeof(FILEGROUPDESCRIPTORW) + (count > 0 ? count - 1 : 0) * sizeof(FILEDESCRIPTORW);
    HGLOBAL global = ::GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, bytes);
    if (global == nullptr) return;
    auto* group = static_cast<FILEGROUPDESCRIPTORW*>(::GlobalLock(global));
    group->cItems = static_cast<UINT>(count);
    for (size_t i = 0; i < count; i++) {
      const DragOutEntry& e = entries_[i];
      FILEDESCRIPTORW& d = group->fgd[i];
      d.dwFlags = FD_ATTRIBUTES | FD_FILESIZE | FD_PROGRESSUI | FD_UNICODE;
      d.dwFileAttributes = e.is_dir ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_NORMAL;
      d.nFileSizeHigh = static_cast<DWORD>(e.size >> 32);
      d.nFileSizeLow = static_cast<DWORD>(e.size & 0xFFFFFFFF);
      // 名称超过 MAX_PATH 时截断（资源管理器的虚拟文件名称上限）
      wcsncpy_s(d.cFileName, e.path.c_str(), _TRUNCATE);
    }
    ::GlobalUnlock(global);
    FORMATETC format = {cf_descriptor_, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
    STGMEDIUM medium = {};
    medium.tymed = TYMED_HGLOBAL;
    medium.hGlobal = global;
    if (FAILED(inner_->SetData(&format, &medium, TRUE))) ::GlobalFree(global);
  }

  // 默认操作为复制
  void StorePreferredEffect() {
    HGLOBAL global = ::GlobalAlloc(GMEM_MOVEABLE, sizeof(DWORD));
    if (global == nullptr) return;
    *static_cast<DWORD*>(::GlobalLock(global)) = DROPEFFECT_COPY;
    ::GlobalUnlock(global);
    FORMATETC format = {cf_effect_, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
    STGMEDIUM medium = {};
    medium.tymed = TYMED_HGLOBAL;
    medium.hGlobal = global;
    if (FAILED(inner_->SetData(&format, &medium, TRUE))) ::GlobalFree(global);
  }

  // 第 index 个文件的内容：请求 Dart 下载到临时文件，再以只读流返回
  HRESULT GetContents(LONG index, STGMEDIUM* medium) {
    if (index < 0 || static_cast<size_t>(index) >= entries_.size()) return DV_E_LINDEX;
    const size_t i = static_cast<size_t>(index);
    if (entries_[i].is_dir) return DV_E_LINDEX;
    std::wstring name = entries_[i].path;
    const size_t slash = name.find_last_of(L'\\');
    if (slash != std::wstring::npos) name = name.substr(slash + 1);
    const std::wstring path =
        FileDragSource::SessionTempDir(session_) + L"\\" + std::to_wstring(index) + L"\\" + name;
    // 同一文件重复请求时复用已下载的临时文件
    if (!written_[i]) {
      if (!owner_->RequestWrite(session_, static_cast<int>(index), path)) return E_FAIL;
      written_[i] = true;
    }
    IStream* stream = nullptr;
    HRESULT hr = ::SHCreateStreamOnFileEx(path.c_str(), STGM_READ | STGM_SHARE_DENY_NONE, FILE_ATTRIBUTE_NORMAL,
                                          FALSE, nullptr, &stream);
    if (FAILED(hr)) return hr;
    medium->tymed = TYMED_ISTREAM;
    medium->pstm = stream;
    medium->pUnkForRelease = nullptr;
    return S_OK;
  }

  LONG refs_ = 1;
  FileDragSource* owner_;
  int session_;
  std::vector<DragOutEntry> entries_;
  IDataObject* inner_;
  std::vector<bool> written_;
  CLIPFORMAT cf_descriptor_ = 0;
  CLIPFORMAT cf_contents_ = 0;
  CLIPFORMAT cf_effect_ = 0;
  BOOL async_ = TRUE;
  BOOL in_operation_ = FALSE;
};

}  // namespace

// 写入请求：由数据对象创建，在平台线程调用 Dart，完成后置位事件
struct FileDragSource::WriteRequest {
  int session = 0;
  int index = 0;
  std::wstring path;
  HANDLE done = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
  bool ok = false;

  ~WriteRequest() {
    if (done != nullptr) ::CloseHandle(done);
  }
};

FileDragSource::FileDragSource(flutter::BinaryMessenger* messenger, HWND view)
    : view_(view), platform_thread_(::GetCurrentThreadId()) {
  // 系统拖动需要 OLE（main.cpp 只初始化了 COM）
  ::OleInitialize(nullptr);

  WNDCLASSW wc = {};
  wc.lpfnWndProc = WndProc;
  wc.hInstance = ::GetModuleHandleW(nullptr);
  wc.lpszClassName = kWindowClass;
  ::RegisterClassW(&wc);
  window_ = ::CreateWindowExW(0, kWindowClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, wc.hInstance, nullptr);
  ::SetWindowLongPtrW(window_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "remlark/file_drag", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "start") {
      HandleStart(call.arguments(), std::move(result));
    } else {
      result->NotImplemented();
    }
  });
}

FileDragSource::~FileDragSource() {
  channel_->SetMethodCallHandler(nullptr);
  if (window_ != nullptr) ::DestroyWindow(window_);
  ::OleUninitialize();
}

std::wstring FileDragSource::SessionTempDir(int session) {
  wchar_t temp[MAX_PATH + 1] = {};
  ::GetTempPathW(MAX_PATH + 1, temp);
  return std::wstring(temp) + L"Remlark-drag\\" + std::to_wstring(session);
}

LRESULT CALLBACK FileDragSource::WndProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<FileDragSource*>(::GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (self != nullptr) {
    if (message == kStartDragMessage) {
      self->RunDrag();
      return 0;
    }
    if (message == kWriteMessage) {
      // 接管后台线程投递的请求
      std::unique_ptr<std::shared_ptr<WriteRequest>> request(reinterpret_cast<std::shared_ptr<WriteRequest>*>(lparam));
      self->InvokeWrite(*request);
      return 0;
    }
  }
  return ::DefWindowProcW(hwnd, message, wparam, lparam);
}

void FileDragSource::HandleStart(const flutter::EncodableValue* args,
                                 std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* map = args != nullptr ? std::get_if<flutter::EncodableMap>(args) : nullptr;
  // 主按键可能被系统设置为右键
  const int primary = ::GetSystemMetrics(SM_SWAPBUTTON) ? VK_RBUTTON : VK_LBUTTON;
  if (map == nullptr || (::GetAsyncKeyState(primary) & 0x8000) == 0) {
    result->Success(flutter::EncodableValue(false));
    return;
  }
  std::vector<DragOutEntry> entries;
  const auto list = MapValue(*map, "entries", flutter::EncodableList());
  for (const auto& item : list) {
    const auto* e = std::get_if<flutter::EncodableMap>(&item);
    if (e == nullptr) continue;
    DragOutEntry entry;
    entry.path = Utf16FromUtf8(MapValue(*e, "path", std::string()));
    std::replace(entry.path.begin(), entry.path.end(), L'/', L'\\');
    entry.is_dir = MapValue(*e, "isDir", false);
    entry.size = static_cast<uint64_t>(MapInt(*e, "size"));
    entries.push_back(std::move(entry));
  }
  if (entries.empty()) {
    result->Success(flutter::EncodableValue(false));
    return;
  }
  pending_session_ = static_cast<int>(MapInt(*map, "session"));
  pending_entries_ = std::move(entries);
  // 先回复 Dart，再在下一轮消息中开始拖动（拖动期间平台线程处于系统拖动循环）
  result->Success(flutter::EncodableValue(true));
  ::PostMessageW(window_, kStartDragMessage, 0, 0);
}

void FileDragSource::RunDrag() {
  std::vector<DragOutEntry> entries = std::move(pending_entries_);
  pending_entries_.clear();
  const int session = pending_session_;
  if (entries.empty()) return;

  // 清理之前拖动留下的临时文件（仍被资源管理器读取的文件会删除失败，忽略）
  std::error_code ec;
  const std::filesystem::path root = std::filesystem::path(SessionTempDir(session)).parent_path();
  for (const auto& dir : std::filesystem::directory_iterator(root, ec)) {
    std::filesystem::remove_all(dir.path(), ec);
  }

  IDataObject* inner = nullptr;
  if (FAILED(::SHCreateDataObject(nullptr, 0, nullptr, nullptr, IID_PPV_ARGS(&inner)))) return;
  auto* data = new DragDataObject(this, session, std::move(entries), inner);
  inner->Release();
  DWORD effect = DROPEFFECT_NONE;
  // 不传拖动源时由系统提供默认拖动源和拖动图像
  ::SHDoDragDrop(view_, data, nullptr, DROPEFFECT_COPY, &effect);
  data->Release();

  // 系统拖动吃掉了左键松开事件，补发给 Flutter 视图，结束应用内的拖动手势
  POINT pt;
  ::GetCursorPos(&pt);
  ::ScreenToClient(view_, &pt);
  ::PostMessageW(view_, WM_LBUTTONUP, 0, MAKELPARAM(static_cast<short>(pt.x), static_cast<short>(pt.y)));

  channel_->InvokeMethod("ended", std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
                                      {flutter::EncodableValue("session"), flutter::EncodableValue(session)}}));
}

void FileDragSource::InvokeWrite(const std::shared_ptr<WriteRequest>& request) {
  auto args = std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
      {flutter::EncodableValue("session"), flutter::EncodableValue(request->session)},
      {flutter::EncodableValue("index"), flutter::EncodableValue(request->index)},
      {flutter::EncodableValue("path"), flutter::EncodableValue(Utf8FromUtf16(request->path.c_str()))},
  });
  auto on_result = std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
      [request](const flutter::EncodableValue*) {
        request->ok = true;
        ::SetEvent(request->done);
      },
      [request](const std::string&, const std::string&, const flutter::EncodableValue*) {
        ::SetEvent(request->done);
      },
      [request]() { ::SetEvent(request->done); });
  channel_->InvokeMethod("write", std::move(args), std::move(on_result));
}

bool FileDragSource::RequestWrite(int session, int index, const std::wstring& path) {
  auto request = std::make_shared<WriteRequest>();
  request->session = session;
  request->index = index;
  request->path = path;
  if (request->done == nullptr) return false;
  if (::GetCurrentThreadId() != platform_thread_) {
    // 资源管理器在后台线程提取：投递到平台线程调用 Dart，在此等待
    auto* posted = new std::shared_ptr<WriteRequest>(request);
    if (!::PostMessageW(window_, kWriteMessage, 0, reinterpret_cast<LPARAM>(posted))) {
      delete posted;
      return false;
    }
    ::WaitForSingleObject(request->done, INFINITE);
    return request->ok;
  }
  // 同步提取（在平台线程上）：直接调用 Dart，并继续处理消息直到回复（Dart 回调依赖平台线程消息循环）
  InvokeWrite(request);
  while (::WaitForSingleObject(request->done, 0) != WAIT_OBJECT_0) {
    ::MsgWaitForMultipleObjects(1, &request->done, FALSE, INFINITE, QS_ALLINPUT);
    MSG msg;
    while (::PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
      if (msg.message == WM_QUIT) {
        ::PostQuitMessage(static_cast<int>(msg.wParam));
        return false;
      }
      ::TranslateMessage(&msg);
      ::DispatchMessageW(&msg);
    }
  }
  return request->ok;
}
