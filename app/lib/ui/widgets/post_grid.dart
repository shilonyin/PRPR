import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../models/post.dart';
import 'post_tile.dart';

/// 瀑布流网格。原版 UWP 用 `VariableSizedWrapGrid` 做首页，
/// Flutter 侧用 `SliverMasonryGrid`：列宽固定、每列按图片原始比例向下堆，
/// 视觉上最接近原版。
///
/// 之所以用 sliver 而不是 `MasonryGridView`，是因为 [header]（搜索框之类）
/// 需要跟列表一起滚动，而空列表时又要能撑满整屏。`CustomScrollView` 一次解决两者。
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
  });

  final List<Post> posts;
  final void Function(Post post) onOpen;
  final VoidCallback? onLoadMore;
  final bool hasMore;
  final bool isLoadingMore;
  final String heroPrefix;

  /// 列表顶部的附加内容（例如搜索框）。
  final Widget? header;

  final String emptyText;

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
    final available = width - 32; // 左右各 16 的内边距
    final count = (available / _targetColumnWidth).floor();
    return count.clamp(2, 8);
  }

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.fromLTRB(16, 16, 16, 32);
    final header = widget.header;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(constraints.maxWidth);
        final slivers = <Widget>[
          if (header != null)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, 0),
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
                header == null ? padding.top : 12,
                padding.right,
                padding.bottom,
              ),
              sliver: SliverMasonryGrid.count(
                crossAxisCount: columns,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childCount: widget.posts.length + (widget.hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= widget.posts.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
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

  Widget _empty(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              widget.emptyText,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}
