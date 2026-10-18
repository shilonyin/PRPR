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
          _error = '$e';
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final feature = _feature ?? DailyFeature.empty;
    if (feature.topToday.isEmpty && feature.featuredTags.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.today_outlined, size: 48),
            const SizedBox(height: 12),
            const Text('今天还没有新内容'),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('刷新')),
          ],
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
              Expanded(
                child: Text('今日高分', style: AppTheme.sectionTitle(context)),
              ),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 280,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: feature.topToday.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final post = feature.topToday[index];
                return SizedBox(
                  width: 200,
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
                        left: 8,
                        top: 8,
                        child: _rankBadge(context, index + 1),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 28),
          Text('值得一看的标签', style: AppTheme.sectionTitle(context)),
          const SizedBox(height: 12),
          if (feature.featuredTags.isEmpty)
            Text('今天没有出现两次以上的标签', style: AppTheme.hint(context))
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final tag in feature.featuredTags)
                  _TagCard(tag: tag, onOpen: _open),
              ],
            ),
        ],
      ),
    );
  }

  Widget _rankBadge(BuildContext context, int rank) {
    final color = switch (rank) {
      1 => const Color(0xFFD4A017),
      2 => const Color(0xFF9AA0A6),
      _ => const Color(0xFFB08D57),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'TOP $rank',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
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
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  errorWidget: (context, _, _) => ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tag.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tag.posts.length} 张',
                      style: AppTheme.hint(context),
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
