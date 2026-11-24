import 'dart:io';

/// 开机自启。只写当前用户的 Run 注册表键，不需要管理员权限，
/// 也不碰注册表以外的任何东西（启动文件夹快捷方式、任务计划都不做）。
///
/// 值名固定 PRPR；值是当前可执行文件的完整路径并带引号 ——
/// 安装路径含空格时，不带引号会被系统按第一个空格截断。
class AutoStartService {
  AutoStartService._();

  static const String _runKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _valueName = 'PRPR';

  /// 注册表里是否已有自启项。reg query 退出码 0 即存在。
  static Future<bool> isEnabled() async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run('reg', ['query', _runKey, '/v', _valueName]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 写入或删除自启项，返回是否达到目标状态。
  static Future<bool> setEnabled(bool enabled) async {
    if (!Platform.isWindows) return false;
    try {
      if (enabled) {
        final result = await Process.run('reg', [
          'add', _runKey,
          '/v', _valueName,
          '/t', 'REG_SZ',
          '/d', '"${Platform.resolvedExecutable}"',
          '/f',
        ]);
        return result.exitCode == 0;
      }
      final result =
          await Process.run('reg', ['delete', _runKey, '/v', _valueName, '/f']);
      if (result.exitCode == 0) return true;
      // 值本来就不存在时 reg delete 也报非零：目标状态（未自启）其实已达成，
      // 不该向用户报「关闭失败」。
      return !await isEnabled();
    } catch (_) {
      return false;
    }
  }
}
