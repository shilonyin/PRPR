import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/post.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/post_grid.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    await state.loadFavorites();
  }

  void _open(Post post) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PostDetailPage(post: post, heroPrefix: 'fav-'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = state.settings;
    final theme = Theme.of(context);

    if (!settings.isLoggedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.gapXxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: AppTheme.iconXl,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppTheme.gapM),
              Text(
                '登录后才能看到自己的收藏',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppTheme.gapS),
              Text(
                '在「设置 → 账号」里填入站点用户名和密码。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (state.isLoadingFavorites) {
      return const Center(child: CircularProgressIndicator());
    }

    return PostGrid(
      posts: state.favoritePosts,
      heroPrefix: 'fav-',
      emptyText: '还没有收藏任何图片',
      onOpen: _open,
      header: Row(
        children: [
          Expanded(
            child: Text(
              '${state.favoritePosts.length} 张收藏',
              style: AppTheme.sectionTitle(context),
            ),
          ),
          const SizedBox(width: AppTheme.gapM),
          DropdownButton<int>(
            value: state.favoriteSortIndex,
            items: [
              for (var i = 0; i < AppState.favoriteSortLabels.length; i++)
                DropdownMenuItem<int>(
                  value: i,
                  child: Text(AppState.favoriteSortLabels[i]),
                ),
            ],
            onChanged: (value) async {
              if (value == null) return;
              state.favoriteSortIndex = value;
              await _load();
            },
          ),
          const SizedBox(width: AppTheme.gapS),
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: AppTheme.iconSm),
          ),
        ],
      ),
    );
  }
}
