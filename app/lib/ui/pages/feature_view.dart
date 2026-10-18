import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/post.dart';
import '../../services/daily_feature.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/post_tile.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
      MaterialPageRoute<void>(
        builder: (_) => PostDetailPage(post: post, heroPrefix: 'feature-'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _messageState(
        icon: Icons.cloud_off_outlined,
        title: '加载失败',
        detail: _error!,
        actionLabel: '重试',
        actionIcon: Icons.refresh,
      );
    }

    final feature = _feature ?? DailyFeature.empty;
    if (feature.topToday.isEmpty && feature.featuredTags.isEmpty) {
      return _messageState(
        icon: Icons.today_outlined,
        title: '今天还没有新内容',
        actionLabel: '刷新',
        actionIcon: Icons.refresh,
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
          SizedBox(
            height: _topStripHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: feature.topToday.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: AppTheme.gapM),
              itemBuilder: (context, index) {
                final post = feature.topToday[index];
                return SizedBox(
                  width: _topCardWidth,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: PostTile(
                          post: post,
                          heroPrefix: 'feature-',
                          onTap: () => _open(post),
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

  /// 空态与错误态共用一套排版：以前两处各写一份，图标尺寸、间距、按钮
  /// 都不一样，同一个页面的「没内容」和「加载失败」看起来像两个应用的。
  Widget _messageState({
    required IconData icon,
    required String title,
    String? detail,
    required String actionLabel,
    required IconData actionIcon,
  }) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        // 与搜索页错误态同宽，两页的失败提示才不会一个宽一个窄。
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.gapXxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: AppTheme.iconXl, color: theme.colorScheme.error),
              const SizedBox(height: AppTheme.gapL),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (detail != null) ...[
                const SizedBox(height: AppTheme.gapS),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: AppTheme.gapXl),
              FilledButton.tonalIcon(
                onPressed: _load,
                icon: Icon(actionIcon, size: AppTheme.iconSm),
                label: Text(actionLabel),
              ),
            ],
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
