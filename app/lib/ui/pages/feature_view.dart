import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/post.dart';
import '../../services/daily_feature.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/app_route.dart';
import '../widgets/post_tile.dart';
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
    try {
      final collected = <Post>[];
      for (var page = 1; page <= _maxPages; page++) {
        final result = await state.client.downloadPosts(
          uri: '/post.xml?tags=rating%3As&',
          page: page,
        );
        if (result.items.isEmpty) break;
        collected.addAll(result.items);

        // 已经翻到了 24 小时以外就停
        final oldest = result.items.last.createdAtUnix;
        final newest = collected.first.createdAtUnix;
        if (newest - oldest >= DailyFeature.windowSeconds) break;
        if (collected.length >= result.totalCount) break;
      }

      final feature = DailyFeature.build(
        collected,
        tagBlacklist: state.settings.filter.tagBlacklist,
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
      return StateMessageSwitcher(
        stateKey: 'empty',
        child: StateMessage(
          icon: Icons.today_outlined,
          title: '今天还没有新内容',
          hint: '站点今天还没有人上传，过一会儿再来看看。',
          actionLabel: '刷新',
          actionIcon: Icons.refresh,
          busy: _loading,
          onAction: _load,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppTheme.pagePadding),
        children: [
          Row(
            children: [
              AppTheme.sectionAccent(context),
              Expanded(
                child: Text('今日高分', style: AppTheme.sectionTitle(context)),
              ),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: AppTheme.iconSm),
                label: const Text('刷新'),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.gapS),
          _TopStrip(
            posts: feature.topToday,
            height: _topStripHeight,
            cardWidth: _topCardWidth,
            onOpen: _open,
          ),
          const SizedBox(height: AppTheme.gapXl),
          Row(
            children: [
              AppTheme.sectionAccent(context),
              Text('值得一看的标签', style: AppTheme.sectionTitle(context)),
            ],
          ),
          const SizedBox(height: AppTheme.gapM),
          if (feature.featuredTags.isEmpty)
            Text('今天没有出现两次以上的标签', style: AppTheme.hint(context))
          else
            Wrap(
              spacing: AppTheme.gapM,
              runSpacing: AppTheme.gapM,
              children: [
                for (final tag in feature.featuredTags)
                  _TagCard(tag: tag, onOpen: _open),
              ],
            ),
        ],
      ),
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
                      Positioned(
                        left: AppTheme.gapS,
                        top: AppTheme.gapS,
                        child: _rankBadge(index + 1),
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

  Widget _rankBadge(int rank) {
    final color = switch (rank) {
      1 => const Color(0xFFD4A017),
      2 => const Color(0xFF9AA0A6),
      _ => const Color(0xFFB08D57),
    };
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
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}

/// 一个精选标签的卡片：封面 + 标签名 + 出现次数。
///
/// 原版是 `GridView` 里一项一项排的，没做点击跳转；
/// 这里点一下直接把该标签下的帖子铺开成新页面。
class _TagCard extends StatelessWidget {
  const _TagCard({required this.tag, required this.onOpen});

  final FeaturedTag tag;
  final void Function(Post post) onOpen;

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
          onTap: () => onOpen(tag.cover),
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
                      style: AppTheme.hint(context)?.copyWith(
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
