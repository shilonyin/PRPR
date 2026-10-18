import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/post.dart';
import '../app_state.dart';
import '../widgets/app_text_field.dart';
import '../widgets/post_grid.dart';
import 'post_detail_page.dart';

/// Ctrl+K 把焦点送到搜索框。
class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

/// 搜索页。对应原 UWP `HomePage` 的第一个 Pivot。
///
/// 原版用 `SearchBox` 的 QuerySubmitted 触发 `HomeViewModel.SearchAsync`；
/// 桌面端换成常驻输入框，回车或点按钮触发，并且支持 `Ctrl+K` 聚焦。
class SearchView extends StatefulWidget {
  const SearchView({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuery);
  final FocusNode _focusNode = FocusNode();
  final FocusNode _shortcutScope = FocusNode();

  /// 历史搜索词，仅存活于本次运行。原版有搜索建议，这里用最近搜索顶替。
  final List<String> _recent = <String>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialQuery.isEmpty) {
        _submit(''); // 首屏直接拉最新
      } else {
        _submit(widget.initialQuery);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _shortcutScope.dispose();
    super.dispose();
  }

  Future<void> _submit(String query) async {
    final state = context.read<AppState>();
    final trimmed = query.trim();
    setState(() {
      _recent.remove(trimmed);
      if (trimmed.isNotEmpty) _recent.insert(0, trimmed);
      if (_recent.length > 8) _recent.removeLast();
    });
    await state.search(trimmed, force: true);
    if (!mounted) return;
    final error = state.error;
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(error)));
    }
  }

  /// 清空输入并留住焦点，方便直接重输下一个词。
  void _clear() {
    _controller.clear();
    _focusNode.requestFocus();
    setState(() {});
  }

  void _clearRecent() {
    setState(() => _recent.clear());
  }

  void _reuseRecent(String query) {
    _controller.text = query;
    _submit(query);
  }

  void _removeRecent(String query) {
    setState(() => _recent.remove(query));
  }

  void _open(Post post) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PostDetailPage(post: post, heroPrefix: 'search-'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final query = state.query;
    final posts = state.postsFor(query);

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            const _FocusSearchIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
            onInvoke: (_) {
              _focusNode.requestFocus();
              return null;
            },
          ),
        },
        child: PostGrid(
          posts: posts,
          heroPrefix: 'search-',
          hasMore: state.hasMoreFor(query),
          isLoadingMore: state.isLoading,
          emptyText: state.isLoading ? '正在加载…' : '没有找到符合条件的图片',
          onOpen: _open,
          onLoadMore: () => state.loadMore(query),
          header: _header(context, state),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, AppState state) {
    final loading = state.isLoading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: _controller,
                focusNode: _focusNode,
                onSubmitted: _submit,
                textInputAction: TextInputAction.search,
                hint: '输入标签搜索，最多 6 个（如 landscape sky）',
                // 加载中把搜索图标换成进度圈，回车/点击后的反馈就在输入框里。
                prefixIcon: loading
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.search, size: 20),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空',
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: _clear,
                      ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: loading ? null : () => _submit(_controller.text),
              icon: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(loading ? '搜索中' : '搜索'),
            ),
          ],
        ),
        // 搜索进行中的细进度条；不加载时高度归零，避免布局跳动。
        SizedBox(
          height: 3,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: loading
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: const LinearProgressIndicator(minHeight: 3),
                  )
                : const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                '快捷键 Ctrl+K 聚焦搜索框。加 rating:s 只搜安全内容。',
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (postsCount(state) > 0)
              Text(
                '共 $totalCount(state) 张',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        if (_recent.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                Icons.history,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '最近搜索',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _clearRecent,
                child: const Text('清空'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in _recent)
                InputChip(
                  avatar: const Icon(Icons.history, size: 16),
                  label: Text(q),
                  onPressed: () => _reuseRecent(q),
                  onDeleted: () => _removeRecent(q),
                  deleteButtonTooltipMessage: '移除「$q」',
                  deleteIcon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        ],
      ],
    );
  }

  int postsCount(AppState state) => state.postsFor(state.query).length;

  int totalCount(AppState state) => state.totalFor(state.query);
}
