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
///
/// ## 为什么要 flush
///
/// `shared_preferences` 的 setter 是「同步改内存缓存 + 异步写磁盘」，写盘返回
/// 的是 Future。以前每次赋值都把这个 Future 丢掉，于是界面上没有任何办法知道
/// 「这次改动到底落盘了没有」—— 设置页想显示一个「已保存」都无从判断。
/// 这里把最近一次写盘 Future 记下来，`flush` 就是它的完成信号。
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

  // ---------- 落盘追踪 ----------

  Future<void> _pending = Future<void>.value();

  /// 每次发起写盘就 +1，供界面显示「已保存」。
  ///
  /// 用独立的 ValueNotifier 而不是 notifyListeners：写盘不代表数据变了
  /// （用户可能把某个值改回原样），而且指示器只想重绘自己那一小块，
  /// 不该让整页设置跟着重建。
  final ValueNotifier<int> saveTick = ValueNotifier<int>(0);

  /// 记录一次写盘。失败也吞掉：设置项写盘失败没有可执行的补救动作，
  /// 抛出去只会变成一条谁也看不懂的红屏。
  void _track(Future<bool> write) {
    _pending = write.then<void>((_) {}, onError: (Object _) {});
    saveTick.value++;
  }

  /// 等待最近一次写盘完成。设置页用它来显示「已保存」。
  Future<void> flush() => _pending;

  // ---------- 站点 ----------

  /// 站点地址，默认 yande.re。
  String get host => _prefs.getString(_kHost) ?? AppConstants.defaultHost;
  set host(String v) {
    _track(_prefs.setString(_kHost, v));
    notifyListeners();
  }

  /// 密码哈希盐。
  String get passwordHashSalt =>
      _prefs.getString(_kPasswordHashSalt) ?? AppConstants.defaultPasswordHashSalt;
  set passwordHashSalt(String v) {
    _track(_prefs.setString(_kPasswordHashSalt, v));
    notifyListeners();
  }

  // ---------- 登录 ----------

  String? get userName => _prefs.getString(_kUserName);
  set userName(String? v) {
    _track(v == null ? _prefs.remove(_kUserName) : _prefs.setString(_kUserName, v));
    notifyListeners();
  }

  String? get passwordHash => _prefs.getString(_kPasswordHash);
  set passwordHash(String? v) {
    _track(
      v == null
          ? _prefs.remove(_kPasswordHash)
          : _prefs.setString(_kPasswordHash, v),
    );
    notifyListeners();
  }

  String? get userId => _prefs.getString(_kUserId);
  set userId(String? v) {
    _track(v == null ? _prefs.remove(_kUserId) : _prefs.setString(_kUserId, v));
    notifyListeners();
  }

  /// 是否已登录。原版 IsLoggedIn => UserID != null。
  bool get isLoggedIn => userId != null;

  void signOut() {
    _track(_prefs.remove(_kUserName));
    _track(_prefs.remove(_kPasswordHash));
    _track(_prefs.remove(_kUserId));
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
    _track(_prefs.setString(_kFilter, jsonEncode(v.toJson())));
    notifyListeners();
  }

  // ---------- 壁纸引擎 ----------

  /// 裁剪方式索引，对应 CropMethod。
  int get cropMethodIndex => _prefs.getInt(_kCropMethod) ?? 4; // 默认 MostFaces
  set cropMethodIndex(int v) {
    _track(_prefs.setInt(_kCropMethod, v));
    notifyListeners();
  }

  /// 画质等级 0=preview 1=jpeg 2=source。原版 qualityLevel。
  int get qualityLevel => _prefs.getInt(_kQualityLevel) ?? 2;
  set qualityLevel(int v) {
    _track(_prefs.setInt(_kQualityLevel, v));
    notifyListeners();
  }

  /// 随机窗口大小。原版 postShuffle。
  int get shuffleWindow => _prefs.getInt(_kShuffleWindow) ?? 50;
  set shuffleWindow(int v) {
    _track(
      _prefs.setInt(_kShuffleWindow, v.clamp(1, AppConstants.maxShuffleWindow)),
    );
    notifyListeners();
  }

  /// 是否启用自动换壁纸。
  bool get autoChangeEnabled => _prefs.getBool(_kAutoChangeEnabled) ?? false;
  set autoChangeEnabled(bool v) {
    _track(_prefs.setBool(_kAutoChangeEnabled, v));
    notifyListeners();
  }

  /// 自动换壁纸间隔（分钟）。
  int get autoChangeMinutes => _prefs.getInt(_kAutoChangeMinutes) ?? 60;
  set autoChangeMinutes(int v) {
    _track(_prefs.setInt(_kAutoChangeMinutes, v.clamp(1, 60 * 24 * 7)));
    notifyListeners();
  }

  /// 默认拉取用的标签串。
  String get defaultTags => _prefs.getString(_kDefaultTags) ?? '';
  set defaultTags(String v) {
    _track(_prefs.setString(_kDefaultTags, v));
    notifyListeners();
  }

  /// 主题：0=跟随系统 1=浅色 2=深色。对应原 ThemeSelectedIndex。
  int get themeModeIndex => _prefs.getInt(_kThemeMode) ?? 0;
  set themeModeIndex(int v) {
    _track(_prefs.setInt(_kThemeMode, v));
    notifyListeners();
  }

  /// 壁纸契合度，见 WallpaperService.fitMode*。
  int get fitMode => _prefs.getInt(_kFitMode) ?? 4;
  set fitMode(int v) {
    _track(_prefs.setInt(_kFitMode, v));
    notifyListeners();
  }
}
