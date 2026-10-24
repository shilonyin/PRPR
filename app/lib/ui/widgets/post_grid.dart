import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../models/post.dart';
import '../theme.dart';
import 'post_tile.dart';
import 'state_message.dart';

/// 瀑布流网格。原版 UWP 用 `VariableSizedWrapGrid` 做首页，
/// Flutter 侧用 `SliverMasonryGrid`：列宽固定、每列按图片原始比例向下堆，
/// 视觉上最接近原版。
///
/// 之所以用 sliver 而不是 `MasonryGridView`，是因为 [header] 可能需要跟列表
/// 一起滚动，而空列表时又要能撑满整屏。`CustomScrollView` 一次解决两者。
/// 桌面端的主操作（搜索框）不该滚走，所以搜索页现在把 header 传 null，
/// 自己用 Column 把它固定在顶部。
class PostGrid extends StatefulWidget {
  const PostGrid({
    super.key,
    required this.posts,
    required this.onOpen,
    this.onLoadMore,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.initialLoading = false,
    this.heroPrefix = '',
    this.header,
    this.emptyText = '没有内容',
    this.emptyBuilder,
    this.density = 4,
  });

  final List<Post> posts;
  final void Function(Post post) onOpen;
  final VoidCallback? onLoadMore;
  final bool hasMore;
  final bool isLoadingMore;

  /// 首次加载（当前一条结果也没有）。为真时显示骨架网格。
  ///
  /// 与 [isLoadingMore] 分开：翻页时列表已经有内容，不该被骨架盖掉。
  final bool initialLoading;

  final String heroPrefix;

  /// 列表顶部的附加内容。传 null 时列表占满整个可用高度。
  final Widget? header;

  final String emptyText;

  /// 自定义空状态。给了它就不再使用 [emptyText]。
  /// 需要「加载失败 + 重试按钮」这类带交互的空状态时用。
  final WidgetBuilder? emptyBuilder;

  /// 基准密度：1440 宽窗口下希望看到几列。搜索页的密度按钮切换的就是它。
  ///
  /// 这里刻意不是「固定列数」：4K 屏把窗口拉到 2560 逻辑像素时，固定 4 列
  /// 会把每张图撑到 600px，一屏只看得到五六张，密度形同虚设。密度只决定
  /// 单张图的**目标宽度**，真正的列数由窗口宽度除以它算出来，
  /// 所以宽屏上会自然变成 6–7 列，而每张图大小保持一致。
  final int density;

  /// 列宽的基准**内容区**宽度：1440 是设计稿画板宽度，减掉 56 的导轨才是网格能用的宽度。
  ///
  /// 这里必须减导轨：[columnsFor] 收到的是 LayoutBuilder 给的父约束宽度，那已经是
  /// 扣掉导轨之后的内容区宽度。两边口径不一致时，1440 窗口会排出 3 列 428px 的图
  /// （导轨占掉的 56px 被算成了可用空间），和设计稿的 4 列对不上。
  static const double _baselineWidth = 1440 - AppTheme.railWidth;

  /// 给定密度下每列应有的宽度。
  ///
  /// density=4 时：(1384 - 64 - 3×12) / 4 = 321。和 AppTheme.columnWidth(325)
  /// 差 4，是设计稿把列宽取整到 5 的倍数留下的；这里按实际公式算，
  /// 免得两处数字各自漂移。
  static double columnWidthFor(int density) {
    final d = density.clamp(2, 8);
    final available =
        _baselineWidth - AppTheme.pagePadding * 2 - AppTheme.gridGap * (d - 1);
    return available / d;
  }

  /// 按可用宽度算列数。
  ///
  /// 用 round 而不是 floor：`width` 来自 LayoutBuilder，是浮点数除下来的结果，
  /// 设计稿 1440 宽、导轨 56、外边距 64、缝 36 时算出来是 3.998 列，
  /// floor 会把它砍成 3 列、每列撑到 429px，和设计稿的 4 列差一整列。
  /// 密度只是「目标宽度」，取最近档才是它的本意。
  ///
  /// 放在 [PostGrid] 而不是 State 上，是因为首屏骨架 [SkeletonGrid] 也要用它：
  /// 两处各算一套，骨架画 5 列、数据到了变 4 列，整屏图会横跳一次。
  static int columnsFor(double width, int density) {
    // 左右各一个 pagePadding 的外边距，别写字面量——改 padding 时会算错列数。
    // 再减去 (n-1) 条缝：缝也算进可用宽度，否则 4 列会被缝推出边界。
    final available = width - AppTheme.pagePadding * 2;
    final target = columnWidthFor(density);
    final count =
        ((available + AppTheme.gridGap) / (target + AppTheme.gridGap)).round();
    return count.clamp(2, 10);
  }

  @override
  State<PostGrid> createState() => _PostGridState();
}

class _PostGridState extends State<PostGrid> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    final cb = widget.onLoadMore;
    if (cb == null || !widget.hasMore || widget.isLoadingMore) return;
    if (!_controller.hasClients) return;
    final position = _controller.position;
    // 提前一屏开始加载，滚动时不会看到空档
    if (position.pixels >= position.maxScrollExtent - 800) {
      cb();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppTheme.durMed,
      switchInCurve: AppTheme.curveIn,
      switchOutCurve: AppTheme.curveOut,
      child: widget.posts.isEmpty && widget.initialLoading
          ? SkeletonGrid(
              key: const ValueKey<String>('skeleton'),
              density: widget.density,
            )
          : KeyedSubtree(
              key: const ValueKey<String>('content'),
              child: _content(context),
            ),
    );
  }

  Widget _content(BuildContext context) {
    // 顶部不留白：搜索页的顶栏自带 79px 的内边距与底线，
    // 画廊再垫一层 32 会在顶栏下面出现一条明显的空白带。
    const padding = EdgeInsets.fromLTRB(
      AppTheme.pagePadding,
      AppTheme.gapM,
      AppTheme.pagePadding,
      AppTheme.gapXxl,
    );
    final header = widget.header;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = PostGrid.columnsFor(constraints.maxWidth, widget.density);
        final slivers = <Widget>[
          if (header != null)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                padding.left,
                padding.top,
                padding.right,
                0,
              ),
              sliver: SliverToBoxAdapter(child: header),
            ),
          if (widget.posts.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _empty(context),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                padding.left,
                header == null ? padding.top : AppTheme.gapM,
                padding.right,
                padding.bottom,
              ),
              sliver: SliverMasonryGrid.count(
                crossAxisCount: columns,
                // 缝和页面外边距同值：缝比 12 的圆角大，卡片边界才清晰；
                // 12 的缝正好等于圆角半径，视觉上会被「吃掉」显得粘连。
                mainAxisSpacing: AppTheme.gridGap,
                crossAxisSpacing: AppTheme.gridGap,
                // 尾部留一格空位给「还有下一页」——不在格子流里放进度环：
                // 瀑布流每列高度不一，尾部的环会出现在最短那列的中间，
                // 看着像某张图加载失败。真正的进度提示放在视口底部悬浮。
                childCount: widget.posts.length + (widget.hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= widget.posts.length) {
                    return const SizedBox(height: AppTheme.gapXxl * 2);
                  }
                  final post = widget.posts[index];
                  return PostTile(
                    post: post,
                    heroPrefix: widget.heroPrefix,
                    onTap: () => widget.onOpen(post),
                  );
                },
              ),
            ),
        ];

        return Stack(
          children: [
            Scrollbar(
              controller: _controller,
              thumbVisibility: true,
              child: ScrollConfiguration(
                // 桌面端默认不允许鼠标拖动列表：用户按住滚轮/左键往下拽是本能，
                // 而 Flutter 只认滚动条的点击拖拽。把 mouse 加进 dragDevices 即可。
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: const <PointerDeviceKind>{
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  },
                ),
                child: CustomScrollView(
                  controller: _controller,
                  // 预取 600px：桌面滚动一格就是一屏的几分之一，默认缓存太小，
                  // 快速滚动时会闪白。
                  scrollCacheExtent: const ScrollCacheExtent.pixels(600),
                  slivers: slivers,
                ),
              ),
            ),
            // 翻页进度固定在视口底部，不参与布局，列表不会因此跳动。
            //
            // TickerMode 不是可选项：LinearProgressIndicator 是无限动画，
            // 把它塞进 AnimatedOpacity(0) 之后它照样每帧都在跑 ticker，
            // 于是「什么都没发生」的界面上 CPU 也降不下来。禁用 ticker 后
            // 它冻结在当前帧、透明度为 0，不花任何开销；真正出现时再重新跑。
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: widget.isLoadingMore && widget.posts.isNotEmpty ? 1 : 0,
                  duration: AppTheme.durFast,
                  child: TickerMode(
                    enabled: widget.isLoadingMore && widget.posts.isNotEmpty,
                    child: const LinearProgressIndicator(minHeight: 2),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _empty(BuildContext context) {
    final custom = widget.emptyBuilder;
    if (custom != null) return custom(context);
    return StateMessage(
      icon: Icons.image_outlined,
      title: widget.emptyText,
    );
  }
}
