import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/post_filter.dart';

/// 应用设置。对应原 UWP 的 `AppSettings` + `YandeSettings` 两个类。
///
/// 原版通过 `ApplicationData.Current.LocalSettings` 键值对存储，
/// Flutter 侧用 `shared_preferences`（Windows 上落在注册表 / JSON 文件），
/// 语义等价：键值对 + 默认值 + 变更通知。
///
/// 原版大量使用 `[CallerMemberName]` 让「属性名即键名」；
/// 这里显式写死键名，避免重构时静默丢配置。
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  final SharedPreferences _prefs;

  static const String _kHost = 'host';
  static const String _kPasswordHashSalt = 'passwordHashSalt';
  static const String _kUserName = 'userName';
  static const String _kPasswordHash = 'passwordHash';
  static const String _kUserId = 'userId';
  static const String _kFilter = 'postFilter';
  static const String _kCropMethod = 'cropMethod';
  static const String _kQualityLevel = 'qualityLevel';
  static const String _kShuffleWindow = 'shuffleWindow';
  static const String _kAutoChangeEnabled = 'autoChangeEnabled';
  static const String _kAutoChangeMinutes = 'autoChangeMinutes';
  static const String _kDefaultTags = 'defaultTags';
  static const String _kThemeMode = 'themeMode';
  static const String _kFitMode = 'fitMode';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings._(prefs);
  }

  // ---------- 站点 ----------

  /// 站点地址，默认 yande.re。
  String get host => _prefs.getString(_kHost) ?? AppConstants.defaultHost;
  set host(String v) {
    _prefs.setString(_kHost, v);
    notifyListeners();
  }

  /// 密码哈希盐。
  String get passwordHashSalt =>
      _prefs.getString(_kPasswordHashSalt) ?? AppConstants.defaultPasswordHashSalt;
  set passwordHashSalt(String v) {
    _prefs.setString(_kPasswordHashSalt, v);
    notifyListeners();
  }

  // ---------- 登录 ----------

  String? get userName => _prefs.getString(_kUserName);
  set userName(String? v) {
    if (v == null) {
      _prefs.remove(_kUserName);
    } else {
      _prefs.setString(_kUserName, v);
    }
    notifyListeners();
  }

  String? get passwordHash => _prefs.getString(_kPasswordHash);
  set passwordHash(String? v) {
    if (v == null) {
      _prefs.remove(_kPasswordHash);
    } else {
      _prefs.setString(_kPasswordHash, v);
    }
    notifyListeners();
  }

  String? get userId => _prefs.getString(_kUserId);
  set userId(String? v) {
    if (v == null) {
      _prefs.remove(_kUserId);
    } else {
      _prefs.setString(_kUserId, v);
    }
    notifyListeners();
  }

  /// 是否已登录。原版 `IsLoggedIn => UserID != null`。
  bool get isLoggedIn => userId != null;

  void signOut() {
    _prefs.remove(_kUserName);
    _prefs.remove(_kPasswordHash);
    _prefs.remove(_kUserId);
    notifyListeners();
  }

  // ---------- 筛选 ----------

  PostFilter get filter {
    final raw = _prefs.getString(_kFilter);
    if (raw == null) {
      return const PostFilter(tagBlacklist: AppConstants.defaultTagBlacklist);
    }
    try {
      return PostFilter.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const PostFilter(tagBlacklist: AppConstants.defaultTagBlacklist);
    }
  }

  set filter(PostFilter v) {
    _prefs.setString(_kFilter, jsonEncode(v.toJson()));
    notifyListeners();
  }

  // ---------- 壁纸引擎 ----------

  /// 裁剪方式索引，对应 `CropMethod`。
  int get cropMethodIndex => _prefs.getInt(_kCropMethod) ?? 4; // 默认 MostFaces
  set cropMethodIndex(int v) {
    _prefs.setInt(_kCropMethod, v);
    notifyListeners();
  }

  /// 画质等级 0=preview 1=jpeg 2=source。原版 `qualityLevel`。
  int get qualityLevel => _prefs.getInt(_kQualityLevel) ?? 2;
  set qualityLevel(int v) {
    _prefs.setInt(_kQualityLevel, v);
    notifyListeners();
  }

  /// 随机窗口大小。原版 `postShuffle`。
  int get shuffleWindow => _prefs.getInt(_kShuffleWindow) ?? 50;
  set shuffleWindow(int v) {
    _prefs.setInt(_kShuffleWindow, v.clamp(1, AppConstants.maxShuffleWindow));
    notifyListeners();
  }

  /// 是否启用自动换壁纸。
  bool get autoChangeEnabled => _prefs.getBool(_kAutoChangeEnabled) ?? false;
  set autoChangeEnabled(bool v) {
    _prefs.setBool(_kAutoChangeEnabled, v);
    notifyListeners();
  }

  /// 自动换壁纸间隔（分钟）。
  int get autoChangeMinutes => _prefs.getInt(_kAutoChangeMinutes) ?? 60;
  set autoChangeMinutes(int v) {
    _prefs.setInt(_kAutoChangeMinutes, v.clamp(1, 60 * 24 * 7));
    notifyListeners();
  }

  /// 默认拉取用的标签串。
  String get defaultTags => _prefs.getString(_kDefaultTags) ?? '';
  set defaultTags(String v) {
    _prefs.setString(_kDefaultTags, v);
    notifyListeners();
  }

  /// 主题：0=跟随系统 1=浅色 2=深色。对应原 `ThemeSelectedIndex`。
  int get themeModeIndex => _prefs.getInt(_kThemeMode) ?? 0;
  set themeModeIndex(int v) {
    _prefs.setInt(_kThemeMode, v);
    notifyListeners();
  }

  /// 壁纸契合度，见 `WallpaperService.fitMode*`。
  int get fitMode => _prefs.getInt(_kFitMode) ?? 4;
  set fitMode(int v) {
    _prefs.setInt(_kFitMode, v);
    notifyListeners();
  }
}
