import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// 找出本机应该走的 HTTP 代理，并把它装到 Dart 的 [HttpClient] 上。
///
/// 为什么需要这个：Dart 的 [HttpClient.findProxyFromEnvironment] **只认环境变量**
/// （HTTP_PROXY / HTTPS_PROXY），完全不看 Windows「设置 → 网络和 Internet → 代理」
/// 里那套 WinINET 配置（注册表里的 ProxyEnable / ProxyServer）。
/// 从桌面快捷方式双击启动时环境变量通常是空的，于是所有请求都直连——
/// 在国内的表现是瀑布流一片空白、图片一直转圈，而且界面上看不到任何错误。
///
/// 顺序：环境变量优先（命令行、脚本、CI 场景），没有再去读注册表。
class SystemProxy {
  SystemProxy._();

  static const String _settingsKey =
      r'Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  /// 环境变量里常见的那几个名字，大小写都试一遍。
  static const List<String> _envNames = [
    'HTTPS_PROXY',
    'https_proxy',
    'HTTP_PROXY',
    'http_proxy',
    'ALL_PROXY',
    'all_proxy',
  ];

  /// 返回形如 `127.0.0.1:7897` 的 `host:port`，没有代理则返回 null。
  ///
  /// 只返回 host:port（不带 scheme），因为 [HttpClient.findProxy] 的返回值
  /// 用的是 `PROXY host:port` 这种格式。
  static String? resolve() {
    final env = Platform.environment;
    for (final name in _envNames) {
      final value = env[name]?.trim();
      if (value != null && value.isNotEmpty) {
        final parsed = _toHostPort(value);
        if (parsed != null) return parsed;
      }
    }
    if (!Platform.isWindows) return null;
    return _fromRegistry();
  }

  /// 把系统代理装到当前进程的所有 [HttpClient] 上。
  ///
  /// 必须在创建任何 [HttpClient] 之前调用（也就是 `main()` 的最开头），
  /// 否则已经建好的客户端不会被影响。CachedNetworkImage、flutter_cache_manager
  /// 这些内部自己 new HttpClient 的库也因此一并被覆盖。
  static void install() {
    final proxy = resolve();
    if (proxy == null) return;
    HttpOverrides.global = _ProxyOverrides(proxy);
  }

  /// 从注册表读 WinINET 代理配置。
  static String? _fromRegistry() {
    final keyPtr = calloc<IntPtr>();
    Pointer<Utf16>? subKey;
    try {
      subKey = _settingsKey.toNativeUtf16();
      final rc = RegOpenKeyEx(
        HKEY_CURRENT_USER,
        subKey,
        0,
        KEY_QUERY_VALUE,
        keyPtr,
      );
      if (rc != ERROR_SUCCESS) return null;
      final hKey = keyPtr.value;

      // ProxyEnable 为 0 时即使填了服务器地址也不生效。
      if (_queryDword(hKey, 'ProxyEnable') != 1) return null;
      final server = _queryString(hKey, 'ProxyServer');
      if (server == null || server.trim().isEmpty) return null;
      return _toHostPort(server);
    } finally {
      if (subKey != null) calloc.free(subKey);
      if (keyPtr.value != 0) RegCloseKey(keyPtr.value);
      calloc.free(keyPtr);
    }
  }

  static int? _queryDword(int hKey, String name) {
    final namePtr = name.toNativeUtf16();
    final dataPtr = calloc<Uint32>();
    final sizePtr = calloc<Uint32>()..value = 4;
    try {
      final rc = RegQueryValueEx(
        hKey,
        namePtr,
        nullptr,
        nullptr,
        dataPtr.cast<Uint8>(),
        sizePtr,
      );
      return rc == ERROR_SUCCESS ? dataPtr.value : null;
    } finally {
      calloc.free(namePtr);
      calloc.free(dataPtr);
      calloc.free(sizePtr);
    }
  }

  static String? _queryString(int hKey, String name) {
    final namePtr = name.toNativeUtf16();
    final sizePtr = calloc<Uint32>();
    try {
      // 先问需要多少字节，再按需分配。
      var rc = RegQueryValueEx(
        hKey,
        namePtr,
        nullptr,
        nullptr,
        nullptr,
        sizePtr,
      );
      if (rc != ERROR_SUCCESS || sizePtr.value == 0) return null;
      final buffer = calloc<Uint8>(sizePtr.value);
      try {
        rc = RegQueryValueEx(
          hKey,
          namePtr,
          nullptr,
          nullptr,
          buffer,
          sizePtr,
        );
        if (rc != ERROR_SUCCESS) return null;
        return buffer.cast<Utf16>().toDartString();
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(namePtr);
      calloc.free(sizePtr);
    }
  }

  /// 把各种写法的代理值收敛成 `host:port`。
  ///
  /// WinINET 允许按协议分列（`http=1.2.3.4:8080;https=1.2.3.4:8080`），
  /// 环境变量则常写成 `http://1.2.3.4:8080`，两种都要认。
  static String? _toHostPort(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;

    if (value.contains('=')) {
      final parts = <String, String>{};
      for (final piece in value.split(';')) {
        final idx = piece.indexOf('=');
        if (idx <= 0) continue;
        final key = piece.substring(0, idx).trim().toLowerCase();
        final val = piece.substring(idx + 1).trim();
        if (key.isNotEmpty && val.isNotEmpty) parts[key] = val;
      }
      if (parts.isEmpty) return null;
      // 优先 https，其次 http，再退到随便哪个协议。
      value = parts['https'] ?? parts['http'] ?? parts.values.first;
    }

    // 去掉 scheme，只留 host:port。
    final schemeIdx = value.indexOf('://');
    if (schemeIdx >= 0) value = value.substring(schemeIdx + 3);
    // 去掉可能存在的路径部分。
    final slashIdx = value.indexOf('/');
    if (slashIdx >= 0) value = value.substring(0, slashIdx);
    value = value.trim();
    return value.isEmpty ? null : value;
  }
}

/// 给每个新建的 [HttpClient] 挂上代理。
class _ProxyOverrides extends HttpOverrides {
  _ProxyOverrides(this.proxy);

  final String proxy;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) {
      // 本机地址不该走代理，否则访问 127.0.0.1 的服务会被代理搅乱。
      final host = uri.host;
      if (host == 'localhost' ||
          host == '127.0.0.1' ||
          host == '::1' ||
          host == '[::1]') {
        return 'DIRECT';
      }
      return 'PROXY $proxy';
    };
    return client;
  }
}
