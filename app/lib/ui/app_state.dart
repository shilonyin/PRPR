import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/post.dart';
import '../services/app_settings.dart';
import '../services/history_store.dart';
import '../services/wallpaper_engine.dart';
import '../services/yande_client.dart';

/// 全局应用状态。
///
/// 原 UWP 版把状态散在 `Params`、`YandeSettings`、`SuspensionManager` 三处，
/// 页面之间靠 `Frame.Navigate` 传参。Flutter 侧统一收进一个 `ChangeNotifier`，
/// 由 `provider` 注入，页面只读它、不互相持有引用。
///
/// 职责边界：
/// - 持有 `AppSettings` / `HistoryStore` / `YandeClient` / `WallpaperEngine` 四个长生命周期对象；
/// - 提供帖子分页拉取与缓存；
/// - 提供自动换壁纸的定时器。
///
/// 不负责：UI 状态（例如当前 tab、对话框开关），那些留在各页面的 `State` 里。
class AppState extends ChangeNotifier {
  AppState({
    required this.settings,
    required this.history,
    required this.client,
    required this.engine,
  });

  final AppSettings settings;
  final HistoryStore history;
  final YandeClient client;
  final WallpaperEngine engine;

  static Future<AppState> create() async {
    final settings = await AppSettings.load();
    final history = await HistoryStore.load();
    final client = YandeClient(host: settings.host);
    final engine = WallpaperEngine(
      client: client,
      settings: settings,
      history: history,
    );
    final state = AppState(
      settings: settings,
      history: history,
      client: client,
      engine: engine,
    );
    state._syncAutoChange();
    settings.addListener(state._onSettingsChanged);
    return state;
  }

  // ---------- 帖子列表 ----------

  /// 已加载的帖子（按搜索串缓存）。
  final Map<String, List<Post>> _pages = <String, List<Post>>{};

  /// 各搜索串已加载到第几页。
  final Map<String, int> _loadedPage = <String, int>{};

  /// 各搜索串的总条数。
  final Map<String, int> _totalCount = <String, int>{};

  /// 当前搜索串。
  String _query = '';

  String get query => _query;

  List<Post> postsFor(String query) => _pages[query] ?? const <Post>[];

  /// 该搜索串在站点上的总条数。
  int totalFor(String query) => _totalCount[query] ?? 0;

  bool isLoading = false;

  /// 加载失败的错误信息，供 UI 直接展示。
  String? error;

  /// 是否还有下一页。
  bool hasMoreFor(String query) {
    final loaded = _loadedPage[query] ?? 0;
    final total = _totalCount[query] ?? 0;
    if (total == 0) return false;
    return loaded * 100 < total;
  }

  /// 搜索并重置列表。
  ///
  /// 对应原 `HomeViewModel.SearchAsync`。原版有两条校验：
  /// 1. 标签数超过 6 个不搜（站点限制）；
  /// 2. 含 `rating:` 元标签时解锁分级过滤并提示。
  ///
  /// 这里保留第一条，第二条改为直接放行 —— 桌面端用户明确输入了
  /// `rating:` 就是想按分级搜，弹窗打断反而更烦。
  Future<void> search(String query, {bool force = false}) async {
    final trimmed = query.trim();
    _query = trimmed;

    if (!force && _pages.containsKey(trimmed) && _pages[trimmed]!.isNotEmpty) {
      notifyListeners();
      return;
    }

    final tagCount = trimmed.split(' ').where((e) => e.isNotEmpty).length;
    if (tagCount > 6) {
      error = '最多只支持 6 个标签';
      notifyListeners();
      return;
    }

    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final uri = trimmed.isEmpty
          ? '/post.xml?'
          : '/post.xml?tags=${Uri.encodeQueryComponent(trimmed)}&';
      final page = await client.downloadPosts(uri: uri, page: 1);

      _pages[trimmed] = List<Post>.from(page.items);
      _loadedPage[trimmed] = 1;
      _totalCount[trimmed] = page.totalCount;
    } catch (e) {
      error = describeError(e);
      _pages[trimmed] = <Post>[];
      _loadedPage[trimmed] = 0;
      _totalCount[trimmed] = 0;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// 追加下一页。
  Future<void> loadMore(String query) async {
    if (isLoading) return;
    final loaded = _loadedPage[query] ?? 0;
    if (!hasMoreFor(query)) return;

    isLoading = true;
    notifyListeners();
    try {
      final trimmed = query.trim();
      final uri = trimmed.isEmpty
          ? '/post.xml?'
          : '/post.xml?tags=${Uri.encodeQueryComponent(trimmed)}&';
      final page = await client.downloadPosts(uri: uri, page: loaded + 1);
      final existing = _pages[trimmed] ?? <Post>[];
      // 站点偶尔会重复返回，按 id 去重
      final ids = existing.map((p) => p.id).toSet();
      existing.addAll(page.items.where((p) => !ids.contains(p.id)));
      _pages[trimmed] = existing;
      _loadedPage[trimmed] = loaded + 1;
      _totalCount[trimmed] = page.totalCount;
    } catch (e) {
      error = describeError(e);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// 把异常翻译成给用户看的一句话。
  ///
  /// [YandeException] 的 message 本来就是人话，但它的 toString() 会加上
  /// 'YandeException: ' 前缀 —— 直接显示在界面上很丑，所以单独取 message。
  static String describeError(Object e) =>
      e is YandeException ? e.message : e.toString();

  // ---------- 收藏 ----------

  List<Post> favoritePosts = <Post>[];

  bool isLoadingFavorites = false;

  /// 收藏排序方式。原 `HomeViewModel.FavoriteSortingMode`。
  static const List<String> favoriteSortModes = <String>[
    'order:vote',
    'order:id_asc',
    'order:id',
    'order:score',
    'order:score_asc',
  ];

  static const List<String> favoriteSortLabels = <String>[
    '按收藏时间',
    '按 ID 升序',
    '按 ID 降序',
    '按分数升序',
    '按分数降序',
  ];

  int favoriteSortIndex = 0;

  Future<void> loadFavorites() async {
    final userName = settings.userName;
    if (userName == null || userName.isEmpty) {
      favoritePosts = <Post>[];
      notifyListeners();
      return;
    }

    isLoadingFavorites = true;
    notifyListeners();
    try {
      final sort = favoriteSortModes[favoriteSortIndex];
      final uri = '/post.xml?tags=vote%3A3%3A$userName+$sort&';
      final page = await client.downloadPosts(uri: uri, page: 1);
      favoritePosts = page.items;
    } catch (e) {
      favoritePosts = <Post>[];
      error = describeError(e);
    } finally {
      isLoadingFavorites = false;
      notifyListeners();
    }
  }

  // ---------- 壁纸 ----------

  ChangeStage? currentStage;

  /// 换一张壁纸。[tags] 为空时用设置里的默认标签。
  Future<ChangeResult> changeWallpaper({String? tags}) async {
    currentStage = ChangeStage.fetching;
    notifyListeners();
    try {
      final result = await engine.changeWallpaper(
        tags: tags,
        onStage: (stage) {
          currentStage = stage;
          notifyListeners();
        },
      );
      return result;
    } finally {
      currentStage = null;
      notifyListeners();
    }
  }

  /// 把指定帖子设为壁纸。
  Future<ChangeResult> applyPost(Post post) async {
    final result = await engine.applyPost(post);
    notifyListeners();
    return result;
  }

  // ---------- 自动换壁纸 ----------

  Timer? _autoTimer;

  void _syncAutoChange() {
    _autoTimer?.cancel();
    _autoTimer = null;
    if (!settings.autoChangeEnabled) return;

    final minutes = settings.autoChangeMinutes;
    _autoTimer = Timer.periodic(Duration(minutes: minutes), (_) async {
      if (engine.isBusy) return;
      final result = await engine.changeWallpaper();
      lastAutoResult = result;
      notifyListeners();
    });
  }

  ChangeResult? lastAutoResult;

  void _onSettingsChanged() {
    if (client.host != settings.host) {
      client.host = settings.host;
    }
    _syncAutoChange();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    settings.removeListener(_onSettingsChanged);
    engine.dispose();
    super.dispose();
  }
}
