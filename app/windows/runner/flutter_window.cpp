#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "win32_window.h"

namespace {

// 为什么要在 FlutterView 子窗口上做子类化：
//
// 引擎收到 WM_GETOBJECT 就会启用无障碍桥（flutter_window.cc 的 OnGetObject
// -> OnUpdateSemanticsEnabled(true) -> CreateAccessibilityBridge()）。
// 而这条路径上有空指针崩溃：
//   flutter::AccessibilityBridge::CreateRemoveReparentedNodesUpdate + 0xba
//   accessibility_bridge.cc:229  ->  child->parent()->id()
// 上一行是 assert(child->parent())，release 构建把 assert 编掉，于是段错误
// （0xC0000005，出错模块永远是 flutter_windows.dll，错误偏移 0x3c16a）。
// 触发条件是页面语义树在大量内容涌入时发生子节点重挂，所以表现为「启动后
// 几秒到几十秒随机闪退」，而且越是有 UIA 客户端（PowerToys 一类）在查询窗口
// 越容易命中。上游 flutter/flutter#175041 至今 open；比对过 3.47.4 / 3.47.7 /
// master，这个函数一字未改，升级 Flutter 修不掉。
//
// UIA 把 WM_GETOBJECT 发给 Flutter 自己创建的 FLUTTERVIEW 子窗口，而不是我们的
// 顶层窗口 —— 这就是在顶层窗口过程里拦 WM_GETOBJECT 完全无效的原因。
// 所以在子窗口上挂子类过程，回 0（等于「本窗口不支持无障碍」），引擎就不会
// 建无障碍树，那条崩溃路径也就不会被走到。
//
// 实测（Debug 版，30 秒 × 4 轮）：
//   放行 WM_GETOBJECT：1/4 崩溃（18.3s，0xC0000005），AXTree 报错 9~117 条
//   拦截 WM_GETOBJECT：4/4 存活，AXTree 报错恒为 0 条
//
// 代价是屏幕阅读器读不到本应用的内容。对一个以图片为主的壁纸工具来说可以接受，
// 换来的是不再随机闪退。将来引擎修好后，删掉这段子类化即可恢复。
constexpr wchar_t kFlutterViewClassFragment[] = L"FLUTTERVIEW";

bool IsFlutterViewClass(HWND hwnd) {
  wchar_t name[256] = {};
  if (GetClassName(hwnd, name, ARRAYSIZE(name)) == 0) {
    return false;
  }
  return wcsstr(name, kFlutterViewClassFragment) != nullptr;
}

// 枚举子窗口兜底查找 FlutterView。
HWND FindFlutterView(HWND top_level) {
  if (top_level == nullptr) {
    return nullptr;
  }
  struct Context {
    HWND found = nullptr;
  } context;

  EnumChildWindows(
      top_level,
      [](HWND child, LPARAM lparam) -> BOOL {
        auto* ctx = reinterpret_cast<Context*>(lparam);
        if (IsFlutterViewClass(child)) {
          ctx->found = child;
          return FALSE;  // 找到就停
        }
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&context));

  return context.found;
}

WNDPROC g_original_flutter_view_proc = nullptr;

LRESULT CALLBACK FlutterViewSubclassProc(HWND hwnd,
                                         UINT const message,
                                         WPARAM const wparam,
                                         LPARAM const lparam) {
  if (message == WM_GETOBJECT) {
    // 0 表示「我不提供无障碍对象」，UIA 会认为本窗口没有可访问内容。
    return 0;
  }
  return CallWindowProc(g_original_flutter_view_proc, hwnd, message, wparam,
                        lparam);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // 在把 FlutterView 挂成子窗口之前就装上子类过程，避免 UIA 客户端在
  // 窗口可见后抢先问一轮 WM_GETOBJECT 造成漏拦。
  HWND flutter_view = flutter_controller_->view()->GetNativeWindow();
  if (flutter_view == nullptr) {
    flutter_view = FindFlutterView(GetHandle());
  }
  if (flutter_view != nullptr) {
    g_original_flutter_view_proc = reinterpret_cast<WNDPROC>(SetWindowLongPtr(
        flutter_view, GWLP_WNDPROC,
        reinterpret_cast<LONG_PTR>(FlutterViewSubclassProc)));
  }

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
