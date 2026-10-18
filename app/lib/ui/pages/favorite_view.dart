import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/post.dart';
import '../app_state.dart';
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

    if (!settings.isLoggedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 12),
              const Text('登录后才能看到自己的收藏'),
              const SizedBox(height: 8),
              Text(
                '在「设置 → 账号」里填入站点用户名和密码。',
                style: Theme.of(context).textTheme.bodySmall,
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
              '${
                state.favoritePosts.length
              } 张收藏',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(width: 12),
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
          const SizedBox(width: 8),
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}
