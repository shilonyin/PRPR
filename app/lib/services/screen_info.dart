import 'dart:io';
import 'dart:ui' show Size;

import 'package:win32/win32.dart';

/// 主显示器物理分辨率。
///
/// 原 UWP 版从 `AppSettings.ScreenWidth/ScreenHeight`（由 `Window.Current.Bounds`
/// 写入）拿尺寸用于裁剪；桌面程序应使用物理像素，
/// 否则高 DPI 下裁剪出的壁纸会被拉伸模糊。
///
/// 这里用 `GetSystemMetrics(SM_CXSCREEN / SM_CYSCREEN)`。
/// 注意：该 API 返回的是 **主显示器** 在系统 DPI 感知上下文下的尺寸；
/// 本项目在 `main.dart` 里启用了 per-monitor DPI awareness，
/// 因此结果是物理像素。
class ScreenInfo {
  ScreenInfo._();

  /// 主显示器尺寸。非 Windows 平台返回常见默认值（便于开发时预览）。
  static Size primaryScreenSize() {
    if (!Platform.isWindows) {
      return const Size(1920, 1080);
    }
    final width = GetSystemMetrics(SM_CXSCREEN);
    final height = GetSystemMetrics(SM_CYSCREEN);
    if (width <= 0 || height <= 0) {
      return const Size(1920, 1080);
    }
    return Size(width.toDouble(), height.toDouble());
  }
}
