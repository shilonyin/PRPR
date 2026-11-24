import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/post.dart';
import '../../models/post_filter.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/app_route.dart';
import '../widgets/app_topbar.dart';
import '../widgets/post_grid.dart';
import '../widgets/state_message.dart';
import 'post_detail_page.dart';

/// 收藏页。对应原 UWP `HomePage` 的「收藏」Pivot。
///
/// 原版只有登录用户才有内容，且排序方式固定为 5 种；
/// 这里保持同样行为，未登录时给出明确提示而不是空白页。
class FavoriteView extends StatefulWidget {
  const FavoriteView({super.key});

  @override
  State<FavoriteView> createState() => _FavoriteViewState();
}

class _FavoriteViewState extends State<FavoriteView> {
  /// 首页发来的「刷新当前页」信号（F5 / Ctrl+R）。
  ValueNotifier<int>? _refreshTick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tick = context.read<AppState>().refreshTick;
    if (identical(_refreshTick, tick)) return;
    _refreshTick?.removeListener(_onRefreshRequested);
    _refreshTick = tick..addListener(_onRefreshRequested);
  }

  @override
  void dispose() {
    _refreshTick?.removeListener(_onRefreshRequested);
    super.dispose();
  }

  void _onRefreshRequested() {
    if (!mounted) return;
    if (context.read<AppState>().currentTab != 2) return;
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    await state.loadFavorites();
  }

  /// 换排序方式：列表内容会整体换掉，但仍然保留旧列表到新数据回来为止。
  /// 清空再显示骨架会让页面闪一下白，且用户看不清「旧的和新的差在哪」。
  bool _switchingSort = false;

  Future<void> _changeSort(int value) async {
    final state = context.read<AppState>();
    state.favoriteSortIndex = value;
    setState(() => _switchingSort = true);
    try {
      await _load();
    } finally {
      if (mounted) setState(() => _switchingSort = false);
    }
  }

  void _open(Post post) {
    Navigator.of(context).push(
      appPageRoute<void>(
        builder: (_) => PostDetailPage(post: post, heroPrefix: 'fav-'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 只订阅本页真正读的字段：watch<AppState> 会让换壁纸的每次
    // stage 通知都重建收藏页，而收藏页根本不关心壁纸进度。
    final isLoggedIn =
        context.select<AppState, bool>((s) => s.settings.isLoggedIn);
    final loadingFavs =
        context.select<AppState, bool>((s) => s.isLoadingFavorites);
    final rawPosts =
        context.select<AppState, List<Post>>((s) => s.favoritePosts);
    // 收藏同样过内容筛选；filter 实例有缓存，identity 稳定，
    // 只有筛选真正变化时才触发重建。
    final filter =
        context.select<AppState, PostFilter>((s) => s.settings.filter);
    final posts = rawPosts.where(filter.apply).toList();
    final c = AppColor.of(context);

    if (!isLoggedIn) {
      return Column(
        children: [
          _topBar(c, count: 0, sortable: false),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.gapXxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: AppTheme.iconXl,
                      color: c.inkFaint,
                    ),
                    const SizedBox(height: AppTheme.gapM),
                    Text(
                      '登录后才能看到自己的收藏',
                      style: AppType.body.copyWith(color: c.ink),
                    ),
                    const SizedBox(height: AppTheme.gapS),
                    Text(
                      '在「设置 → 账号」里填入站点用户名和密码。',
                      style: AppType.caption.copyWith(color: c.inkFaint),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // 首次加载（还没有任何数据）才铺骨架；重新加载保留列表只做淡化，
    // 这样连续点排序不会让整页反复变成空白。
    final firstLoad = loadingFavs && posts.isEmpty;
    if (firstLoad) return const SkeletonGrid();

    return Column(
      children: [
        _topBar(
          c,
          count: posts.length,
          sortable: true,
          refreshing: loadingFavs,
        ),
        Expanded(
          child: Stack(
            children: [
              AnimatedOpacity(
                opacity: _switchingSort || loadingFavs ? 0.55 : 1,
                duration: AppTheme.durFast,
                curve: AppTheme.curveIn,
                child: PostGrid(
                  posts: posts,
                  heroPrefix: 'fav-',
                  emptyText: '还没有收藏任何图片',
                  onOpen: _open,
                ),
              ),
              // 重载时在顶部给一条 2px 的进度线：列表变淡说明「在忙」，
              // 这条线说明「忙的是刷新」而不是「卡住了」。
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _switchingSort || loadingFavs ? 1 : 0,
                    duration: AppTheme.durFast,
                    curve: AppTheme.curveIn,
                    // 见 post_grid.dart 里同一处注释：无限动画的 ticker 不会
                    // 因为外层的 AnimatedOpacity 变成 0 就停下，必须显式禁用。
                    child: TickerMode(
                      enabled: _switchingSort || loadingFavs,
                      child: const LinearProgressIndicator(minHeight: 2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 顶栏：页名 + 收藏数 + 排序 + 刷新。
  ///
  /// 排序在此之前是塞在网格 header 里的 DropdownButton —— 那是全应用唯一
  /// 一个 Material 下拉，在一排自绘控件里显得像个外来件。收进顶栏后，
  /// 页面的操作区只有一条，且和搜索页的操作区位置完全一致。
  Widget _topBar(
    AppPalette c, {
    required int count,
    required bool sortable,
    bool refreshing = false,
  }) {
    final sortIndex =
        context.select<AppState, int>((s) => s.favoriteSortIndex);
    return AppTopBar(
      child: Row(
        children: [
          Text('收藏', style: AppType.section.copyWith(color: c.ink)),
          const SizedBox(width: AppTheme.gapM),
          if (sortable) AppTopBarLabel('$count 张'),
          const Spacer(),
          if (sortable) ...[
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: sortIndex,
                isDense: true,
                dropdownColor: c.surface,
                borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                style: AppType.monoData.copyWith(color: c.inkDim),
                icon: Icon(
                  Icons.arrow_drop_down,
                  size: 15,
                  color: c.inkFaint,
                ),
                items: [
                  for (var i = 0; i < AppState.favoriteSortLabels.length; i++)
                    DropdownMenuItem<int>(
                      value: i,
                      child: Text(AppState.favoriteSortLabels[i]),
                    ),
                ],
                onChanged: (value) async {
                  if (value == null || value == sortIndex) {
                    return;
                  }
                  await _changeSort(value);
                },
              ),
            ),
            const SizedBox(width: AppTheme.gapS),
            IconButton(
              tooltip: '刷新',
              onPressed: refreshing ? null : _load,
              icon: const Icon(Icons.refresh, size: AppTheme.iconXs),
            ),
          ],
        ],
      ),
    );
  }
}
