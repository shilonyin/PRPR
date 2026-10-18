import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/post.dart';
import '../theme.dart';

/// 瀑布流里的单张缩略图。
///
/// 高度由 [Post.preferredRatio] 决定 —— 原版 UWP 的 `VariableSizedWrapGrid`
/// 也是按原始宽高比排的，这样瀑布流才不会出现拉伸变形。
///
/// 悬停时给一点反馈：桌面端没有触摸的按压态，鼠标移上去如果毫无变化，
/// 用户会怀疑卡片是不是可点的。这里只做两件轻的事——描边收紧 + 底部
/// 浮出尺寸与分级，不做缩放，缩放会让整列瀑布流跟着抖。
class PostTile extends StatefulWidget {
  const PostTile({
    super.key,
    required this.post,
    this.onTap,
    this.heroPrefix = '',
  });

  final Post post;
  final VoidCallback? onTap;

  /// Hero 动画标识前缀，避免不同列表里的同一张图串台。
  final String heroPrefix;

  @override
  State<PostTile> createState() => _PostTileState();
}

class _PostTileState extends State<PostTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(AppTheme.cardRadius);
    final ratio = widget.post.preferredRatio;
    // 极端长图会把瀑布流拉得很难看，限一下取值范围。
    // 以前是 0.25~4.0，1:4 的竖图会变成一张一千多像素高的单卡，
    // 一屏只放得下一张，翻页体验直接崩掉；收到 0.5~2.0。
    final safeRatio = ratio.clamp(0.5, 2.0);
    final preview = widget.post.urlFor(PostImageVersion.preview);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: _hovered
                ? theme.colorScheme.primary.withValues(alpha: 0.55)
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: radius),
          child: InkWell(
            onTap: widget.onTap,
            child: AspectRatio(
              aspectRatio: safeRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (preview.isEmpty)
                    _placeholder(context)
                  else
                    Hero(
                      tag: '${widget.heroPrefix}${widget.post.id}',
                      child: CachedNetworkImage(
                        imageUrl: preview,
                        fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 150),
                        placeholder: (context, _) => _placeholder(context),
                        errorWidget: (context, _, _) => _broken(context),
                      ),
                    ),
                  // 悬停才出现的两行信息。常驻会盖住图，而缩略图本身
                  // 是用户找图的主要依据。
                  IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _hovered ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: _overlay(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 底部渐变 + 尺寸、右上角分级徽章。
  Widget _overlay(BuildContext context) {
    final theme = Theme.of(context);
    final post = widget.post;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 56,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0),
                  Colors.black.withValues(alpha: 0.62),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: AppTheme.gapS,
          right: AppTheme.gapS,
          bottom: AppTheme.gapS,
          child: Text(
            '${post.width} × ${post.height}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              fontFeatures: AppTheme.tabularFigures,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Positioned(
          top: AppTheme.gapS,
          right: AppTheme.gapS,
          child: _ratingBadge(context, theme),
        ),
      ],
    );
  }

  Widget _ratingBadge(BuildContext context, ThemeData theme) {
    final rating = widget.post.rating.toLowerCase();
    final (label, color) = switch (rating) {
      's' => ('S', const Color(0xFF2E7D32)),
      'q' => ('Q', const Color(0xFFEF6C00)),
      'e' => ('E', const Color(0xFFC62828)),
      _ => ('?', const Color(0xFF546E7A)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppTheme.chipRadius),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.2,
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: SizedBox(
            width: AppTheme.iconSm,
            height: AppTheme.iconSm,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );

  Widget _broken(BuildContext context) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
}
