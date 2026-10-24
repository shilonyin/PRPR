import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/painting.dart';

import '../ui/theme.dart';

/// 让 Windows 原生标题栏跟着应用主题一起变。
///
/// Flutter 画不到系统标题栏：深色界面顶一条白带，或者浅色界面顶一条黑带，
/// 沉浸感一秒钟就没了。这里直接调 DWM：
///
/// - `DWMWA_USE_IMMERSIVE_DARK_MODE`（20）告诉系统按深色画标题栏；
/// - `DWMWA_CAPTION_COLOR`（35）/ `TEXT_COLOR`（36）/ `BORDER_COLOR`（34）
///   把标题栏底色、字色、边框换成和内容区完全一样的 token。
///
/// 34/35/36 是 Windows 11 才有的，Windows 10 上会返回 `E_INVALIDARG`，
/// 此时只有 20 生效 —— 标题栏变成系统标准的深色，不会和内容区同色，
/// 但也不难看。所有失败都静默，标题栏配色不该成为启动的前置条件。
///
/// 用 `dart:ffi` 而不是 `window_manager` 的 `setBrightness`：后者在
/// `AppsUseLightTheme == 1`（系统浅色）时会把 `enable_dark_mode` 硬算成 false，
/// 于是「系统浅色 + 应用深色」这一档根本切不暗。自己调没有这个限制。
class WindowTheme {
  WindowTheme._();

  /// Flutter 桌面 runner 写死的窗口类名（`windows/runner/main.cpp`）。
  static const String _windowClass = 'FLUTTER_RUNNER_WIN32_WINDOW';

  // DWM 属性号，见 `dwmapi.h` 的 `DWMWINDOWATTRIBUTE`。
  static const int _dwmUseImmersiveDarkMode = 20;
  static const int _dwmBorderColor = 34;
  static const int _dwmCaptionColor = 35;
  static const int _dwmTextColor = 36;

  static int? _hwnd;

  /// 上一次应用过的配色。主题每帧都可能重建，这里挡住重复的跨语言调用。
  static int _lastSignature = -1;

  /// 按当前色板给标题栏上色。同一套配色重复调用是空操作。
  static void apply(AppPalette c, {required bool dark}) {
    if (!Platform.isWindows) return;
    final signature = Object.hash(dark, c.bg, c.ink, c.line);
    if (signature == _lastSignature) return;
    final hwnd = _hwnd ??= _findWindow();
    if (hwnd == null) return;
    _lastSignature = signature;

    _setAttribute(hwnd, _dwmUseImmersiveDarkMode, dark ? 1 : 0);
    _setAttribute(hwnd, _dwmCaptionColor, _colorRef(c.bg));
    _setAttribute(hwnd, _dwmTextColor, _colorRef(c.ink));
    _setAttribute(hwnd, _dwmBorderColor, _colorRef(c.line));
  }

  /// DWM 要的是 `COLORREF`：`0x00BBGGRR`，与 Flutter 的 ARGB 字节序相反。
  static int _colorRef(Color c) {
    final r = (c.r * 255.0).round() & 0xFF;
    final g = (c.g * 255.0).round() & 0xFF;
    final b = (c.b * 255.0).round() & 0xFF;
    return r | (g << 8) | (b << 16);
  }

  /// 找本进程那个 Flutter 窗口。
  ///
  /// 不能按标题找（用户可能改标题），也不能只按类名找（同时开两个 Flutter
  /// 应用会撞车），所以枚举全部顶层窗口，用「类名 + 属于本进程 + 可见」三重条件筛。
  static int? _findWindow() {
    int? found;
    // 回调返回 int：1 继续、0 停。`NativeCallable` 要求非 void 返回的调用
    // 声明一个「异常时返回什么」，这里给 1（继续枚举），异常中断只是说明没找到窗口。
    final callback = NativeCallable<_EnumWindowsProc>.isolateLocal((
      int hwnd,
      int _,
    ) {
      if (_isWindowVisible(hwnd) == 0) return 1;
      if (_ownerProcessId(hwnd) != _getCurrentProcessId()) return 1;
      if (_className(hwnd) != _windowClass) return 1;
      found = hwnd;
      return 0; // 找到了，停止枚举
    }, exceptionalReturn: 1);
    try {
      _enumWindows(callback.nativeFunction, 0);
    } finally {
      callback.close();
    }
    return found;
  }

  static int _ownerProcessId(int hwnd) {
    final pid = calloc<Uint32>();
    try {
      _getWindowThreadProcessId(hwnd, pid);
      return pid.value;
    } finally {
      calloc.free(pid);
    }
  }

  static String _className(int hwnd) {
    const capacity = 256;
    final buffer = calloc<Uint16>(capacity);
    try {
      final length = _getClassNameW(hwnd, buffer.cast<Utf16>(), capacity);
      if (length <= 0) return '';
      return buffer.cast<Utf16>().toDartString(length: length);
    } finally {
      calloc.free(buffer);
    }
  }

  static void _setAttribute(int hwnd, int attribute, int value) {
    final pointer = calloc<Int32>();
    try {
      pointer.value = value;
      _dwmSetWindowAttribute(hwnd, attribute, pointer.cast<Void>(), 4);
    } finally {
      calloc.free(pointer);
    }
  }

  // ---- FFI 绑定 ----
  //
  // 写成 static final 是懒加载：非 Windows 平台永远不会碰这几个符号。

  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final DynamicLibrary _dwmapi = DynamicLibrary.open('dwmapi.dll');

  static final int Function() _getCurrentProcessId = _kernel32
      .lookupFunction<Uint32 Function(), int Function()>('GetCurrentProcessId');

  static final int Function(int) _isWindowVisible = _user32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'IsWindowVisible',
      );

  static final int Function(int, Pointer<Uint32>) _getWindowThreadProcessId =
      _user32.lookupFunction<
        Uint32 Function(IntPtr, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)
      >('GetWindowThreadProcessId');

  static final int Function(int, Pointer<Utf16>, int) _getClassNameW = _user32
      .lookupFunction<Int32 Function(IntPtr, Pointer<Utf16>, Int32),
          int Function(int, Pointer<Utf16>, int)>('GetClassNameW');

  static final int Function(Pointer<NativeFunction<_EnumWindowsProc>>, int)
  _enumWindows = _user32.lookupFunction<
    Int32 Function(Pointer<NativeFunction<_EnumWindowsProc>>, IntPtr),
    int Function(Pointer<NativeFunction<_EnumWindowsProc>>, int)
  >('EnumWindows');

  static final int Function(int, int, Pointer<Void>, int) _dwmSetWindowAttribute =
      _dwmapi.lookupFunction<
        Int32 Function(IntPtr, Uint32, Pointer<Void>, Uint32),
        int Function(int, int, Pointer<Void>, int)
      >('DwmSetWindowAttribute');
}

/// `WNDENUMPROC`：`BOOL (*)(HWND, LPARAM)`。返回 1 继续枚举，0 停止。
typedef _EnumWindowsProc = Int32 Function(IntPtr hwnd, IntPtr lparam);
