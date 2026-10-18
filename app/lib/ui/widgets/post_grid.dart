import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../models/post.dart';
import '../theme.dart';
import 'post_tile.dart';

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
    this.heroPrefix = '',
    this.header,
    this.emptyText = '没有内容',
    this.emptyBuilder,
  });

  final List<Post> posts;
  final void Function(Post post) onOpen;
  final VoidCallback? onLoadMore;
  final bool hasMore;
  final bool isLoadingMore;
  final String heroPrefix;

  /// 列表顶部的附加内容。传 null 时列表占满整个可用高度。
  final Widget? header;

  final String emptyText;

  /// 自定义空状态。给了它就不再使用 [emptyText]。
  /// 需要「加载失败 + 重试按钮」这类带交互的空状态时用。
  final WidgetBuilder? emptyBuilder;

  @override
  State<PostGrid> createState() => _PostGridState();
}

class _PostGridState extends State<PostGrid> {
  final ScrollController _controller = ScrollController();

  /// 每列目标宽度。窗口从 900 到 4K 都能据此算出合适列数。
  static const double _targetColumnWidth = 260;

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

  static int columnsFor(double width) {
    // 左右各一个 pagePadding 的外边距，别写字面量 32——改 padding 时会算错列数。
    final available = width - AppTheme.pagePadding * 2;
    final count = (available / _targetColumnWidth).floor();
    return count.clamp(2, 8);
  }

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.fromLTRB(
      AppTheme.pagePadding,
      AppTheme.pagePadding,
      AppTheme.pagePadding,
      AppTheme.gapXxl,
    );
    final header = widget.header;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(constraints.maxWidth);
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
                mainAxisSpacing: AppTheme.gapL,
                crossAxisSpacing: AppTheme.gapL,
                childCount: widget.posts.length + (widget.hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= widget.posts.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppTheme.gapXl),
                      child: Center(
                        child: SizedBox(
                          width: AppTheme.iconMd,
                          height: AppTheme.iconMd,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
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

        return CustomScrollView(
          controller: _controller,
          slivers: slivers,
        );
      },
    );
  }

  Widget _empty(BuildContext context) {
    final custom = widget.emptyBuilder;
    if (custom != null) return custom(context);
    return _defaultEmpty(context);
  }

  Widget _defaultEmpty(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppTheme.gapXxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_outlined,
              size: AppTheme.iconXl,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppTheme.gapL),
            Text(
              widget.emptyText,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}
