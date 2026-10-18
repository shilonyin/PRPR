import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// 设置结果。
enum WallpaperResult {
  success('已设置'),
  unsupportedPlatform('当前平台不支持'),
  fileMissing('图片文件不存在'),
  apiFailed('系统调用失败'),
  notImplemented('此功能在当前版本尚未实现');

  const WallpaperResult(this.message);
  final String message;

  bool get isSuccess => this == WallpaperResult.success;
}

/// Windows 桌面壁纸设置。
///
/// 原 UWP 版用 `UserProfilePersonalizationSettings.Current.TrySetWallpaperImageAsync`，
/// 那是 UWP 沙箱专属 API，Win32 桌面程序不可用。这里改走：
///
/// `SystemParametersInfoW(SPI_SETDESKWALLPAPER, 0, path, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE)`
///
/// 并配合注册表 `HKCU\\Control Panel\\Desktop` 的 `WallpaperStyle` /
/// `TileWallpaper` 决定「填充 / 适应 / 拉伸 / 平铺 / 居中」。
///
/// 关于锁屏：Win32 没有公开的稳定接口（`SystemData\\...\\LockScreen.jpg`
/// 需要 SYSTEM 权限；WinRT 的 `UserProfilePersonalizationSettings` 在纯 Dart
/// 进程里没有可用的 COM 投影）。因此锁屏在本版本标记为未实现，
/// 而不是静默失败 —— 见 [setLockScreen]。
class WallpaperService {
  /// 桌面壁纸显示方式。
  static const int fitCenter = 0;
  static const int fitTile = 1;
  static const int fitStretch = 2;
  static const int fitFit = 3;
  static const int fitFill = 4;

  static const Map<int, String> fitModeLabels = <int, String>{
    fitFill: '填充',
    fitFit: '适应',
    fitStretch: '拉伸',
    fitCenter: '居中',
    fitTile: '平铺',
  };

  /// 设置桌面壁纸。返回结果枚举而非 bool，便于 UI 给出准确提示。
  WallpaperResult setWallpaper(String imagePath, {int fitMode = fitFill}) {
    if (!Platform.isWindows) return WallpaperResult.unsupportedPlatform;
    if (!File(imagePath).existsSync()) return WallpaperResult.fileMissing;

    // 先写注册表，否则 SystemParametersInfo 会沿用旧的显示方式
    _writeDesktopRegistry(fitMode);

    final pathPtr = imagePath.toNativeUtf16();
    try {
      final result = SystemParametersInfo(
        SPI_SETDESKWALLPAPER,
        0,
        pathPtr,
        SPIF_UPDATEINIFILE | SPIF_SENDCHANGE,
      );
      return result != 0 ? WallpaperResult.success : WallpaperResult.apiFailed;
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// 设置锁屏背景。
  ///
  /// 当前恒返回 [WallpaperResult.notImplemented]：桌面 Win32 没有可靠的锁屏设置途径。
  /// 保留此方法是为了让 UI 与调用链完整，未来若接入 WinRT 投影可直接替换实现。
  WallpaperResult setLockScreen(String imagePath) {
    if (!Platform.isWindows) return WallpaperResult.unsupportedPlatform;
    return WallpaperResult.notImplemented;
  }

  /// 读取当前壁纸路径，用于确认是否真的生效。
  String? currentWallpaper() {
    if (!Platform.isWindows) return null;
    const bufferChars = 1024;
    final buffer = calloc<Uint16>(bufferChars);
    try {
      final result = SystemParametersInfo(
        SPI_GETDESKWALLPAPER,
        bufferChars,
        buffer.cast(),
        0,
      );
      if (result == 0) return null;
      final path = buffer.cast<Utf16>().toDartString();
      return path.isEmpty ? null : path;
    } finally {
      calloc.free(buffer);
    }
  }

  /// fitMode → (WallpaperStyle, TileWallpaper)。
  ///
  /// 对应 Windows「个性化 → 背景 → 选择契合度」的注册表取值：
  /// - 填充 10/0，适应 6/0，拉伸 2/0，居中 0/0，平铺 0/1
  (String, String) _registryStyleFor(int fitMode) {
    switch (fitMode) {
      case fitCenter:
        return ('0', '0');
      case fitTile:
        return ('0', '1');
      case fitStretch:
        return ('2', '0');
      case fitFit:
        return ('6', '0');
      case fitFill:
      default:
        return ('10', '0');
    }
  }

  void _writeDesktopRegistry(int fitMode) {
    final (style, tile) = _registryStyleFor(fitMode);
    final hKeyPtr = calloc<IntPtr>();
    final subKeyPtr = r'Control Panel\\Desktop'.toNativeUtf16();
    try {
      final status = RegOpenKeyEx(
        HKEY_CURRENT_USER,
        subKeyPtr,
        0,
        KEY_SET_VALUE,
        hKeyPtr,
      );
      if (status != ERROR_SUCCESS) return;

      final hKey = hKeyPtr.value;
      try {
        _setRegString(hKey, 'WallpaperStyle', style);
        _setRegString(hKey, 'TileWallpaper', tile);
      } finally {
        RegCloseKey(hKey);
      }
    } finally {
      calloc.free(subKeyPtr);
      calloc.free(hKeyPtr);
    }
  }

  void _setRegString(int hKey, String name, String value) {
    final namePtr = name.toNativeUtf16();
    final valuePtr = value.toNativeUtf16();
    try {
      // cbData 是字节数，UTF-16 每字符 2 字节，含结尾 0
      final byteLength = (value.length + 1) * 2;
      RegSetValueEx(
        hKey,
        namePtr,
        0,
        REG_SZ,
        valuePtr.cast<Uint8>(),
        byteLength,
      );
    } finally {
      calloc.free(namePtr);
      calloc.free(valuePtr);
    }
  }
}
