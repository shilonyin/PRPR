import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/post.dart';
import '../app_state.dart';
import '../theme.dart';
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
///
/// 搜索控件固定在内容区顶部，只有瀑布流滚动：桌面端换关键词是主操作，
/// 滚到第五屏还得一路滚回顶部才能改，是可用性问题而不是观感问题。
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
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.pagePadding,
                AppTheme.pagePadding,
                AppTheme.pagePadding,
                AppTheme.gapM,
              ),
              child: _searchControls(context, state),
            ),
            Expanded(
              child: PostGrid(
                posts: posts,
                heroPrefix: 'search-',
                hasMore: state.hasMoreFor(query),
                isLoadingMore: state.isLoading,
                emptyText: state.isLoading ? '正在加载…' : '没有找到符合条件的图片',
                emptyBuilder: (context) => _emptyState(context, state),
                onOpen: _open,
                onLoadMore: () => state.loadMore(query),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 空状态。
  ///
  /// 失败信息不能只靠 SnackBar —— 它四秒就消失，用户回来只看到「没有找到符合条件的图片」，
  /// 会以为是搜索词的问题。国内网络下最常见的原因恰恰是代理没生效，必须留在界面上。
  Widget _emptyState(BuildContext context, AppState state) {
    final theme = Theme.of(context);
    final error = state.error;

    if (state.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: AppTheme.gapL),
            Text('正在加载…', style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }

    if (error != null) {
      // 标题 16/w600、具体错误与通用建议同为 12 但分两档色：原来三行只差
      // 2px 同色同号，用户分不清哪句是「到底出了什么错」。
      return Center(
        child: ConstrainedBox(
          // 420 会让「无法连接站点：远程计算机拒绝网络连接。请检查网络或代理设置」
          // 折在最后一两个字上（实测「置」单独占一行），480 刚好放得下整句。
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.gapXxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: AppTheme.iconXl,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: AppTheme.gapL),
                Text(
                  '加载失败',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: AppTheme.gapS),
                Text(
                  error,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppTheme.gapS),
                Text(
                  '如果是国内网络，请确认系统代理已开启',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.85),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppTheme.gapXl),
                FilledButton.tonalIcon(
                  onPressed: () => state.search(state.query, force: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.gapXxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_outlined,
              size: AppTheme.iconXl,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppTheme.gapL),
            Text(
              '没有找到符合条件的图片',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 固定在顶部的搜索控件：输入行、说明行、最近搜索。
  Widget _searchControls(BuildContext context, AppState state) {
    final loading = state.isLoading;
    final theme = Theme.of(context);

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
                // 加载中把搜索图标换成进度圈：状态就地反馈，不再另外加
                // 一条进度条和一个转圈的按钮图标（一屏四个圈，视线无处落）。
                prefixIcon: loading
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: SizedBox(
                          width: AppTheme.iconXs,
                          height: AppTheme.iconXs,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.search, size: AppTheme.iconSm),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空',
                        icon: const Icon(Icons.close, size: AppTheme.iconSm),
                        onPressed: _clear,
                      ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: AppTheme.gapM),
            FilledButton.icon(
              onPressed: loading ? null : () => _submit(_controller.text),
              icon: const Icon(Icons.search),
              label: Text(loading ? '搜索中' : '搜索'),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.gapS),
        Row(
          children: [
            Expanded(
              child: Text(
                '快捷键 Ctrl+K 聚焦搜索框。加 rating:s 只搜安全内容。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (postsCount(state) > 0)
              Text(
                '共 ${_formatCount(totalCount(state))} 张',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: AppTheme.tabularFigures,
                ),
              ),
          ],
        ),
        if (_recent.isNotEmpty) ...[
          const SizedBox(height: AppTheme.gapM),
          Row(
            children: [
              Icon(
                Icons.history,
                size: AppTheme.iconXs,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppTheme.gapS),
              Text(
                '最近搜索',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _clearRecent,
                child: const Text('清空'),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.gapXs),
          // 去掉 avatar：标题已经有 history 图标了，chip 里再来一个是重复，
          // 而且把 2 字搜索词撑出三个视觉元素。
          Wrap(
            spacing: AppTheme.gapS,
            runSpacing: AppTheme.gapS,
            children: [
              for (final q in _recent)
                InputChip(
                  label: Text(q),
                  onPressed: () => _reuseRecent(q),
                  onDeleted: () => _removeRecent(q),
                  deleteButtonTooltipMessage: '移除「$q」',
                  deleteIcon: const Icon(Icons.close, size: AppTheme.iconXs),
                ),
            ],
          ),
        ],
      ],
    );
  }

  int postsCount(AppState state) => state.postsFor(state.query).length;

  int totalCount(AppState state) => state.totalFor(state.query);

  /// 把总数格式化成好读的形式：过万用「万」，否则加千分位。
  ///
  /// 不引入 intl：这里只需要两种形态，自己算比多一个依赖划算。
  static String _formatCount(int total) {
    if (total >= 10000) {
      final wan = total / 10000;
      final text = wan >= 100 ? wan.toStringAsFixed(0) : wan.toStringAsFixed(1);
      return '$text 万';
    }
    final digits = total.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
