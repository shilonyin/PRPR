import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/post.dart';
import '../../models/tag.dart';
import '../../services/daily_feature.dart';
import '../../services/yande_client.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/app_route.dart';
import '../widgets/post_tile.dart';
import '../widgets/app_topbar.dart';
import '../widgets/section_header.dart';
import '../widgets/state_message.dart';
import 'post_detail_page.dart';

/// 每日精选。对应原 UWP `FeatureView` + `FeatureViewModel`。
///
/// 原版逻辑（已核对 `FeatureViewModel.Update`）：
/// 1. 拉 `rating:s` 第 1 页，以首条时间为准往前推 24 小时为 `dayBefore`；
/// 2. 只要最后一页的最后一条还没早于 `dayBefore`，就继续 `LoadMoreItemsAsync(100)`；
/// 3. 筛出 24 小时内的帖子，按黑名单过滤；
/// 4. 取分数前三 + 统计精选标签。
///
/// 这里把 2 的「继续翻页」限制在最多 5 页 —— 原版在某些日子会一直翻下去，
/// 桌面端启动时不该等那么久。
class FeatureView extends StatefulWidget {
  const FeatureView({super.key});

  @override
  State<FeatureView> createState() => _FeatureViewState();
}

class _FeatureViewState extends State<FeatureView> {
  static const int _maxPages = 5;

  /// 今日高分横排卡片的尺寸。宽度固定、高度由容器限死，
  /// 这样不同比例的图在同一行里高度一致。
  static const double _topCardWidth = 200;
  static const double _topStripHeight = 280;

  DailyFeature? _feature;
  bool _loading = false;
  String? _error;

  /// 标签库的进程内缓存与在途请求。
  ///
  /// 精选标签过滤要靠它把标签名映射到类型 / 别名（见 DailyFeature._featured）。
  /// 标签库变化很慢，拉一次缓存整进程复用；失败降级 null，不阻塞精选。
  static Map<String, TagDetail>? _tagLookupCache;
  static Future<Map<String, TagDetail>?>? _tagLookupInFlight;

  static Future<Map<String, TagDetail>?> _loadTagLookup(YandeClient client) {
    final cached = _tagLookupCache;
    if (cached != null) return Future<Map<String, TagDetail>?>.value(cached);
    return _tagLookupInFlight ??= () async {
      try {
        final db = await client.fetchTagDatabase();
        // TagDatabase.all 里每个 detail.name 与其键一致（含别名），
        // 据此还原成 DailyFeature 需要的 name -> detail 映射。
        final map = <String, TagDetail>{for (final t in db.all) t.name: t};
        _tagLookupCache = map;
        return map;
      } catch (_) {
        return null; // 失败降级：精选照常出，只是不过滤类型 / 别名
      } finally {
        _tagLookupInFlight = null;
      }
    }();
  }

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
    if (context.read<AppState>().currentTab != 1) return;
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final state = context.read<AppState>();
    // 标签库与帖子并行拉：进程内缓存，失败降级 null，不阻塞精选装配。
    final tagLookupFuture = _loadTagLookup(state.client);
    try {
      // 并行拉满 5 页再按页序合并：串行最坏要等 5×12s，而各页之间
      // 没有数据依赖。停止条件语义原样保留——只是从「不发请求」变成
      // 「丢弃结果」：按页序扫描，遇到空页 / 已覆盖 24 小时窗口 /
      // 已取完全站条数就停下，后面的页不再计入。
      final pages = await Future.wait([
        for (var page = 1; page <= _maxPages; page++)
          state.client.downloadPosts(
            uri: '/post.xml?tags=rating%3As&',
            page: page,
          ),
      ]);
      final collected = <Post>[];
      final seen = <int>{};
      for (final result in pages) {
        if (result.items.isEmpty) break;
        // 站点偶尔跨页重复返回，按 id 去重（与 AppState.loadMore 同策）。
        for (final post in result.items) {
          if (seen.add(post.id)) collected.add(post);
        }

        // 已经翻到了 24 小时以外就停
        final oldest = result.items.last.createdAtUnix;
        final newest = collected.first.createdAtUnix;
        if (newest - oldest >= DailyFeature.windowSeconds) break;
        if (collected.length >= result.totalCount) break;
      }

      // 等标签库（已并行启动；为 null 时精选照常出，只是不过滤类型 / 别名）。
      final tagLookup = await tagLookupFuture;
      final feature = DailyFeature.build(
        collected,
        tagLookup: tagLookup,
        // 传完整筛选：精选与搜索页共用同一套谓词。评级查询仍 rating:s，
        // 用户关掉 safe 时这里为空是预期（空态文案会说明）。
        filter: state.settings.filter,
      );
      if (mounted) {
        setState(() {
          _feature = feature;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = AppState.describeError(e);
          _loading = false;
        });
      }
    }
  }

  void _open(Post post) {
    Navigator.of(context).push(
      appPageRoute<void>(
        builder: (_) => PostDetailPage(post: post, heroPrefix: 'feature-'),
      ),
    );
  }

  /// 点精选标签：按该标签跳搜索页铺开帖子，而不是只开封面单帖。
  ///
  /// backToSearchTick 让首页切到搜索页，externalSearchRequest 把标签名
  /// 交给搜索页同步输入框并提交（见 SearchView._onExternalSearch）。
  void _searchTag(String tag) {
    final state = context.read<AppState>();
    state.backToSearchTick.value++;
    state.externalSearchRequest.value = tag;
  }

  @override
  Widget build(BuildContext context) {
    // 三种状态之间都走 [StateMessageSwitcher]：精选页要连翻最多 5 页，
    // 首次加载到内容是这里最长的一段等待，硬切会让等待显得更长。
    final feature = _feature ?? DailyFeature.empty;
    final isEmpty =
        feature.topToday.isEmpty && feature.featuredTags.isEmpty;

    if (_error != null) {
      return StateMessageSwitcher(
        stateKey: 'error',
        child: StateMessage(
          icon: Icons.cloud_off_outlined,
          iconColor: Theme.of(context).colorScheme.error,
          title: '加载失败',
          detail: _error!,
          hint: '如果是国内网络，请确认系统代理已开启',
          actionLabel: '重试',
          actionIcon: Icons.refresh,
          busy: _loading,
          onAction: _load,
        ),
      );
    }

    // 首次加载走骨架：精选页要连翻页，纯转圈的等待感比搜索页更强。
    if (_loading && isEmpty) {
      return StateMessageSwitcher(
        stateKey: 'skeleton',
        child: const SkeletonGrid(tileCount: 12),
      );
    }

    if (isEmpty) {
      // 精选只取 rating:s。用户在设置里关掉 safe 时，这些帖子会被完整
      // 筛选全部挡掉，精选为空是预期而非故障——空态文案要说清原因。
      final safeOff = !context.read<AppState>().settings.filter.isFilterSafe;
      return StateMessageSwitcher(
        stateKey: 'empty',
        child: StateMessage(
          icon: Icons.today_outlined,
          title: '今天还没有新内容',
          hint: safeOff
              ? '精选只收录 safe 分级内容，而当前设置关闭了 safe 过滤，所以这里为空。'
                  '可在设置里重新开启 safe，或到搜索页按分级检索。'
              : '站点今天还没有人上传，过一会儿再来看看。',
          actionLabel: '刷新',
          actionIcon: Icons.refresh,
          busy: _loading,
          onAction: _load,
        ),
      );
    }

    final c = AppColor.of(context);
    return Column(
      children: [
        AppTopBar(
          child: Row(
            children: [
              Text('每日精选', style: AppType.section.copyWith(color: c.ink)),
              const SizedBox(width: AppTheme.gapM),
              AppTopBarLabel('TOP ${feature.topToday.length}'),
              const Spacer(),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: AppTheme.iconXs),
                label: const Text('刷新'),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.pagePadding,
                AppTheme.gapXl,
                AppTheme.pagePadding,
                48,
              ),
              children: [
                const AppSectionHeader('今日高分'),
                const SizedBox(height: AppTheme.gapS),
                _TopStrip(
                  posts: feature.topToday,
                  height: _topStripHeight,
                  cardWidth: _topCardWidth,
                  onOpen: _open,
                ),
                const SizedBox(height: AppTheme.gapXl),
                const AppSectionHeader('值得一看的标签'),
                const SizedBox(height: AppTheme.gapM),
                if (feature.featuredTags.isEmpty)
                  Text(
                    '今天没有出现两次以上的标签',
                    style: AppTheme.hint(context),
                  )
                else
                  Wrap(
                    spacing: AppTheme.gapM,
                    runSpacing: AppTheme.gapM,
                    children: [
                      for (final tag in feature.featuredTags)
                        _TagCard(tag: tag, onTap: () => _searchTag(tag.name)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

}


/// 今日高分的横向条。
///
/// 桌面上横向列表最大的问题是「看不出来还能往右」：鼠标没有横滚手势，
/// 滚轮默认只作用于纵向，用户要么去够滚动条，要么以为只有三张。
/// 这里给左右箭头，并在到边时自动淡出——能滚就是能滚，滚到头就不再暗示。
class _TopStrip extends StatefulWidget {
  const _TopStrip({
    required this.posts,
    required this.height,
    required this.cardWidth,
    required this.onOpen,
  });

  final List<Post> posts;
  final double height;
  final double cardWidth;
  final void Function(Post post) onOpen;

  @override
  State<_TopStrip> createState() => _TopStripState();
}

class _TopStripState extends State<_TopStrip> {
  final ScrollController _controller = ScrollController();

  /// 一屏大概是「卡片宽 + 间距」，箭头一次推一屏而不是一张。
  double get _pageStep => (widget.cardWidth + AppTheme.gapM) * 2;

  bool _canBack = false;
  bool _canForward = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncArrows());
  }

  @override
  void didUpdateWidget(covariant _TopStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.posts.length != widget.posts.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncArrows());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_syncArrows);
    _controller.dispose();
    super.dispose();
  }

  void _syncArrows() {
    if (!mounted || !_controller.hasClients) return;
    final pos = _controller.position;
    final back = pos.pixels > 1;
    final forward = pos.pixels < pos.maxScrollExtent - 1;
    if (back == _canBack && forward == _canForward) return;
    setState(() {
      _canBack = back;
      _canForward = forward;
    });
  }

  void _scrollBy(double delta) {
    if (!_controller.hasClients) return;
    final target = (_controller.position.pixels + delta)
        .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: AppTheme.durSlow,
      curve: AppTheme.curveIn,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          // 鼠标拖动也能滚：桌面用户习惯「按住拖」，不是所有人都会用滚轮。
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: const {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
                PointerDeviceKind.stylus,
              },
            ),
            child: ListView.separated(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: widget.posts.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppTheme.gapM),
              itemBuilder: (context, index) {
                final post = widget.posts[index];
                return SizedBox(
                  width: widget.cardWidth,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: PostTile(
                          post: post,
                          heroPrefix: 'feature-',
                          onTap: () => widget.onOpen(post),
                        ),
                      ),
                      // 徽章放右上：PostTile 的分级圆点常驻左上角，
                      // 两者同位会互相压住。
                      Positioned(
                        right: AppTheme.gapS,
                        top: AppTheme.gapS,
                        child: _rankBadge(AppColor.of(context), index + 1),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          _arrow(
            alignment: Alignment.centerLeft,
            visible: _canBack,
            icon: Icons.chevron_left,
            onTap: () => _scrollBy(-_pageStep),
          ),
          _arrow(
            alignment: Alignment.centerRight,
            visible: _canForward,
            icon: Icons.chevron_right,
            onTap: () => _scrollBy(_pageStep),
          ),
        ],
      ),
    );
  }

  Widget _arrow({
    required Alignment alignment,
    required bool visible,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: AppTheme.durFast,
          curve: AppTheme.curveIn,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.gapS),
            child: IconButton.filledTonal(
              onPressed: onTap,
              tooltip: alignment == Alignment.centerLeft ? '上一组' : '下一组',
              icon: Icon(icon, size: AppTheme.iconSm),
            ),
          ),
        ),
      ),
    );
  }

  /// 名次徽章。前三名用金色，其余用中性描边 —— 只有「今天的第一名」
  /// 值得一块实底，第四名之后还发彩块就是在制造没有信息量的视觉噪声。
  Widget _rankBadge(AppPalette c, int rank) {
    final color = rank <= 3 ? c.gold : c.inkFaint;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.gapS,
        vertical: AppTheme.gapXs,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTheme.chipRadius),
      ),
      child: Text(
        'TOP $rank',
        style: AppType.chip.copyWith(
          color: rank <= 3 ? c.onGold : c.ink,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// 一个精选标签的卡片：封面 + 标签名 + 出现次数。
///
/// 原版是 `GridView` 里一项一项排的，没做点击跳转；
/// 这里点一下按该标签跳搜索页，把该标签下的帖子铺开 —— 封面只是预览，
/// 用户真正要看的是整个标签，所以回跳搜索而不是只开封面单帖。
class _TagCard extends StatelessWidget {
  const _TagCard({required this.tag, required this.onTap});

  final FeaturedTag tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 180,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        ),
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: CachedNetworkImage(
                  imageUrl: tag.cover.urlFor(PostImageVersion.preview),
                  fit: BoxFit.cover,
                  placeholder: (context, _) => ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  errorWidget: (context, _, _) => ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppTheme.gapM),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tag.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: AppTheme.gapXs),
                    Text(
                      '${tag.posts.length} 张',
                      style: AppTheme.hint(context).copyWith(
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
