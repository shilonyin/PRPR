import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/post.dart';
import '../theme.dart';

/// 瀑布流里的单张缩略图。
///
/// 高度由 [Post.preferredRatio] 决定 —— 原版 UWP 的 `VariableSizedWrapGrid`
/// 也是按原始宽高比排的，这样瀑布流才不会出现拉伸变形。
class PostTile extends StatelessWidget {
  const PostTile({super.key, required this.post, this.onTap, this.heroPrefix = ''});

  final Post post;
  final VoidCallback? onTap;

  /// Hero 动画标识前缀，避免不同列表里的同一张图串台。
  final String heroPrefix;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.cardRadius);
    final ratio = post.preferredRatio;
    // 极端长图会把瀑布流拉得很难看，限一下取值范围。
    final safeRatio = ratio.clamp(0.25, 4.0);
    final preview = post.urlFor(PostImageVersion.preview);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radius),
      child: InkWell(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: safeRatio,
          child: preview.isEmpty
              ? _placeholder(context)
              : Hero(
                  tag: '$heroPrefix${post.id}',
                  child: CachedNetworkImage(
                    imageUrl: preview,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 150),
                    placeholder: (context, _) => _placeholder(context),
                    errorWidget: (context, _, _) => _broken(context),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
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
