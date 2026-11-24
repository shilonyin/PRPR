import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/post.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/app_route.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_topbar.dart';
import '../widgets/post_grid.dart';
import '../widgets/state_message.dart';
import 'post_detail_page.dart';

/// Ctrl+K 把焦点送到搜索框。
class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

/// 搜索页。对应原 UWP `HomePage` 的第一个 Pivot。
///
/// 上一版的搜索是「一个带边框的输入框 + 一个搜索按钮 + 下面一行说明 + 再下面
/// 一行最近搜索 chip」，四层东西竖着叠了 120px 高，占掉了小半屏。
///
/// 新版把它压成一件事：**顶栏本身就是输入框**。搜索图标、查询串、语法提示、
/// 结果计数、排序、密度全在同一条 79px 的带子里，没有边框、没有按钮——
/// 桌面端的搜索框不需要提交按钮，回车就是提交，用户看着自己打出来的
/// 标签串（等宽字体，标签之间就是空格）比看着一个「搜索」按钮更有数。
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

  /// 首页发来的「把光标送进搜索框」信号。Ctrl+K 在任何页都该有用，
  /// 而本页自己的快捷键只在本页有焦点时才生效，所以还要接住这条。
  ValueNotifier<int>? _focusTick;

  /// 首页发来的「刷新当前页」信号。
  ValueNotifier<int>? _refreshTick;

  /// 外部页面（精选标签墙 / 详情页面包屑）发来的「用这个词搜索」信号。
  ValueNotifier<String?>? _externalSearch;

  /// 历史搜索词，仅存活于本次运行。
  final List<String> _recent = <String>[];

  /// 排序菜单展开状态（点空白关掉）。
  bool _sortOpen = false;

  /// 排序选项：order: 标签 → 显示名。空串 = 默认（不带 order:）。
  /// order: 计入站点的 6 标签上限，追加前要先数一遍（见 _applySort）。
  static const Map<String, String> _sortOptions = <String, String>{
    '': '默认',
    'order:score': '评分 ↓',
    'order:score_asc': '评分 ↑',
    'order:id': 'ID ↓',
    'order:id_asc': 'ID ↑',
  };

  /// 输入框焦点状态。用 ValueNotifier 局部化而不是整页 setState：
  /// 焦点变化只影响搜索图标颜色和最近搜索条，不该拖着 PostGrid 重建。
  final ValueNotifier<bool> _inputFocused = ValueNotifier<bool>(false);

  /// 三档密度：紧凑 5、标准 4、舒展 3。
  ///
  /// 存的是「1440 宽基准下想看几列」，不是最终列数 —— 实际列数由窗口宽度
  /// 除以按密度算出的单图宽度得到。不存最终列数是因为同一台机器上把窗口
  /// 从 1440 拉到 2560 时，4 列会被撑成 600px 一张，密度就失去意义了。
  int _density = 4;

  @override
  void initState() {
    super.initState();
    // _RecentBar 的可见性读 hasFocus，但焦点变化不会自己触发 build，
    // 必须显式监听，否则失焦后最近搜索条一直挂着。
    _focusNode.addListener(_syncInputFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialQuery.isEmpty) {
        _submit(''); // 首屏直接拉最新
      } else {
        _submit(widget.initialQuery);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.read<AppState>();
    if (!identical(_focusTick, state.focusSearchTick)) {
      _focusTick?.removeListener(_takeFocus);
      _focusTick = state.focusSearchTick..addListener(_takeFocus);
    }
    if (!identical(_refreshTick, state.refreshTick)) {
      _refreshTick?.removeListener(_refresh);
      _refreshTick = state.refreshTick..addListener(_refresh);
    }
    if (!identical(_externalSearch, state.externalSearchRequest)) {
      _externalSearch?.removeListener(_onExternalSearch);
      _externalSearch = state.externalSearchRequest
        ..addListener(_onExternalSearch);
    }
  }

  @override
  void dispose() {
    _focusTick?.removeListener(_takeFocus);
    _refreshTick?.removeListener(_refresh);
    _externalSearch?.removeListener(_onExternalSearch);
    _focusNode.removeListener(_syncInputFocus);
    _inputFocused.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _syncInputFocus() {
    _inputFocused.value = _focusNode.hasFocus;
  }

  void _takeFocus() {
    if (!mounted) return;
    _focusNode.requestFocus();
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  void _refresh() {
    if (!mounted) return;
    final state = context.read<AppState>();
    if (state.currentTab != 0) return;
    state.search(state.query, force: true);
  }

  /// 接住外部页面的搜索请求：同步输入框并提交。
  ///
  /// 与 _refresh 不同，这里不检查 currentTab —— 外部请求是明确的「搜这个词」，
  /// 切页由 backToSearchTick 另行负责。消费后把信号清空，保证同一标签
  /// 再次点击时 ValueNotifier 仍会通知（值相同不再触发）。
  void _onExternalSearch() {
    if (!mounted) return;
    final state = context.read<AppState>();
    final query = state.externalSearchRequest.value;
    if (query == null) return;
    state.externalSearchRequest.value = null;
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    _submit(query);
  }

  Future<void> _submit(String query) async {
    final state = context.read<AppState>();
    final trimmed = query.trim();
    setState(() {
      _recent.remove(trimmed);
      if (trimmed.isNotEmpty) _recent.insert(0, trimmed);
      if (_recent.length > 6) _recent.removeLast();
    });
    await state.search(trimmed, force: true);
    if (!mounted) return;
    final error = state.error;
    if (error != null) AppToast.error(context, error);
  }

  /// 当前生效的 order: 标签（空串 = 默认排序）。
  static String _currentOrder(String query) => query
      .split(' ')
      .firstWhere((t) => t.startsWith('order:'), orElse: () => '');

  /// 选排序 = 替换/追加 query 里的 order: 标签再重查。
  ///
  /// order: 计入站点 6 标签上限：替换已有 order: 不改变标签数，
  /// 但给已满 6 个标签的 query 追加一个会被站点拒绝，先挡下并提示。
  void _applySort(String order) {
    setState(() => _sortOpen = false);
    final state = context.read<AppState>();
    final tokens = state.query
        .split(' ')
        .where((t) => t.isNotEmpty && !t.startsWith('order:'))
        .toList();
    if (order.isNotEmpty) tokens.add(order);
    if (tokens.length > 6) {
      AppToast.info(context, '最多支持 6 个标签，排序（order:）也占一个');
      return;
    }
    final newQuery = tokens.join(' ');
    // 输入框同步显示新 query：排序是 query 的一部分，不能只改结果不改串。
    _controller.text = newQuery;
    _controller.selection = TextSelection.collapsed(offset: newQuery.length);
    _submit(newQuery); // 内部走 AppState.search(force: true)
  }

  void _reuseRecent(String query) {
    _controller.text = query;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    _focusNode.requestFocus();
    _submit(query);
  }

  void _open(Post post) {
    Navigator.of(context).push(
      appPageRoute<void>(
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
        child: GestureDetector(
          // 点空白收起排序菜单。放在最外层是为了「点哪儿都能关」。
          onTap: _sortOpen ? () => setState(() => _sortOpen = false) : null,
          child: Column(
            children: [
              _buildTopBar(context, state),
              // 最近搜索不占常驻空间：它只在输入框拿到焦点时从顶栏下面
              // 滑出一行。没有焦点时这里什么也没有，画廊直接顶到顶栏下沿。
              ValueListenableBuilder<bool>(
                valueListenable: _inputFocused,
                builder: (context, focused, _) => _RecentBar(
                  visible: focused && _recent.isNotEmpty,
                  items: _recent,
                  onPick: _reuseRecent,
                ),
              ),
              Expanded(
                child: PostGrid(
                  posts: posts,
                  heroPrefix: 'search-',
                  hasMore: state.hasMoreFor(query),
                  isLoadingMore: state.isLoading,
                  initialLoading: state.isLoading && posts.isEmpty,
                  emptyText: '没有找到符合条件的图片',
                  emptyBuilder: (context) => _emptyState(context, state),
                  onOpen: _open,
                  onLoadMore: () => state.loadMore(query),
                  density: _density,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶栏：搜索语法 + 结果计数 + 排序 + 密度 + 换壁纸。
  ///
  /// 高度 79 = 上 20 + 输入行 22 + 间距 6 + 提示行 16 + 下 15。
  /// 输入行不是 TextField 而是把 TextField 的装饰全部剥掉后直接铺在顶栏上：
  /// 一个 79px 高、无边框、通栏的输入区，光标是金色的那一条。
  Widget _buildTopBar(BuildContext context, AppState state) {
    final c = AppColor.of(context);
    final loading = state.isLoading;
    // 计数显示筛选后的实际条数，而不是站点总数（分页仍按站点总数判断）。
    final total = state.postsFor(state.query).length;

    return AppTopBar(
      height: AppTheme.topbarHeightSearch,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: _inputFocused,
            builder: (context, focused, _) => Icon(
              Icons.search,
              size: 17,
              color: focused ? c.gold : c.inkFaint,
            ),
          ),
          const SizedBox(width: AppTheme.gapM + 2),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 22,
                  // 不在 onChanged 里整页 setState：页面没有任何部分逐键
                  // 读输入文本，TextField 自己渲染自己；整页重建只会拖着
                  // PostGrid 白重建几十次。焦点态走 _inputFocused 局部刷新。
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    onSubmitted: _submit,
                    textInputAction: TextInputAction.search,
                    cursorColor: c.gold,
                    cursorWidth: 1.6,
                    cursorHeight: 17,
                    style: AppType.title.copyWith(
                      fontSize: 16,
                      color: c.ink,
                      height: 1.2,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'landscape  sky  rating:s',
                      // 占位符用实色 inkFaint：再叠 0.55 透明度只剩约
                      // 1.9:1 对比度，深色底上基本看不见。
                      hintStyle: AppType.title.copyWith(
                        fontSize: 16,
                        height: 1.2,
                        color: c.inkFaint,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _SyntaxHint(loading: loading, recent: _recent.isEmpty),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.gapL),
          if (total > 0) ...[
            _CountReadout(total: total, loading: loading),
            const SizedBox(width: AppTheme.gapL),
            Container(width: 1, height: 14, color: c.line),
            const SizedBox(width: AppTheme.gapL),
          ],
          _SortMenu(
            open: _sortOpen,
            // 入口 label 反映当前生效的排序，而不是恒为「评分 ↓」。
            label: _sortOptions[_currentOrder(state.query)] ??
                _currentOrder(state.query),
            current: _currentOrder(state.query),
            onTap: () => setState(() => _sortOpen = !_sortOpen),
            onPick: _applySort,
          ),
          const SizedBox(width: AppTheme.gapM),
          _DensityButton(
            density: _density,
            onTap: () => setState(
              // 4 → 5 → 3 → 4：先加一档再退两档，比单向循环少按一次回到标准。
              () => _density = _density == 4 ? 5 : (_density == 5 ? 3 : 4),
            ),
          ),
        ],
      ),
    );
  }

  /// 空状态。
  ///
  /// 失败信息不能只靠提示条 —— 它几秒就消失，用户回来只看到「没有找到」，
  /// 会以为是搜索词的问题。国内网络下最常见的原因恰恰是代理没生效，必须留在界面上。
  Widget _emptyState(BuildContext context, AppState state) {
    final c = AppColor.of(context);
    final error = state.error;

    if (error != null) {
      return StateMessageSwitcher(
        stateKey: 'error',
        child: StateMessage(
          icon: Icons.cloud_off_outlined,
          iconColor: c.danger,
          title: '加载失败',
          detail: error,
          hint: '如果是国内网络，请确认系统代理已开启',
          actionLabel: '重试',
          busy: state.isLoading,
          onAction: () => state.search(state.query, force: true),
        ),
      );
    }

    return StateMessageSwitcher(
      stateKey: 'empty',
      child: StateMessage(
        icon: Icons.image_outlined,
        title: '没有找到符合条件的图片',
        hint: '换个标签组合试试',
        suggestions: const <String>['landscape', 'sky', 'original'],
        onSuggestion: _reuseRecent,
      ),
    );
  }
}

/// 输入框下面那行 11px 的语法提示。
///
/// 换了内容而不是消失：平时教语法（`支持 rating:s / score:>50 / tag`），
/// 加载时变成阶段文案。常驻一行说明比一个只在出错时出现的 tooltip 有用——
/// 这套标签语法是新用户唯一的学习门槛。
class _SyntaxHint extends StatelessWidget {
  const _SyntaxHint({required this.loading, required this.recent});

  final bool loading;
  final bool recent;

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    return AnimatedSwitcher(
      duration: AppTheme.durFast,
      child: Text(
        loading
            ? '正在获取…'
            : 'Ctrl+K 聚焦 · 支持 rating:s / score:>50 / tag / -tag 排除',
        key: ValueKey<bool>(loading),
        style: AppType.caption.copyWith(color: c.inkFaint),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 结果计数。等宽、金色、千分位。
class _CountReadout extends StatelessWidget {
  const _CountReadout({required this.total, required this.loading});

  final int total;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    return AnimatedOpacity(
      duration: AppTheme.durFast,
      opacity: loading ? 0.45 : 1,
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: _thousands(total),
              style: AppType.monoData.copyWith(
                fontSize: 12.5,
                color: c.goldText,
                fontWeight: FontWeight.w500,
              ),
            ),
            TextSpan(
              text: ' 张',
              style: AppType.monoData.copyWith(
                fontSize: 11,
                color: c.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 千分位。不引入 intl：只需要这一种形态。
  static String _thousands(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

/// 排序入口。选项一一对应 order: 标签，选中即替换/追加该标签重查；
/// 入口 label 永远反映当前排序。此前这里只弹一条 Toast，是个假下拉。
class _SortMenu extends StatelessWidget {
  const _SortMenu({
    required this.open,
    required this.label,
    required this.current,
    required this.onTap,
    required this.onPick,
  });

  final bool open;
  final String label;

  /// 当前生效的 order: 标签（空串 = 默认），用于高亮菜单里的当前项。
  final String current;
  final VoidCallback onTap;

  /// 回传 order: 标签本身；空串表示去掉排序回默认。
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ChipTap(
          label: label,
          open: open,
          onTap: onTap,
        ),
        if (open) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.gapS,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(AppTheme.inputRadius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in _SearchViewState._sortOptions.entries)
                  InkWell(
                    onTap: () => onPick(entry.key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.gapS,
                        vertical: 2,
                      ),
                      child: Text(
                        entry.value,
                        style: AppType.caption.copyWith(
                          color: entry.key == current ? c.goldText : c.inkDim,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ChipTap extends StatefulWidget {
  const _ChipTap({
    required this.label,
    required this.open,
    required this.onTap,
  });

  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  State<_ChipTap> createState() => _ChipTapState();
}

class _ChipTapState extends State<_ChipTap> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        // 视觉保持 26 高，命中区扩到 32：触控板/触摸屏上 26px 太难点中。
        child: SizedBox(
          height: 32,
          child: Center(
            child: AnimatedContainer(
              duration: AppTheme.durFast,
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: widget.open || _hover ? c.surface : Colors.transparent,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(AppTheme.chipRadius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label,
                    style: AppType.monoData.copyWith(color: c.inkDim),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, size: 13, color: c.inkFaint),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 密度切换。图标画的是当前列数的示意，而不是一个固定图标。
class _DensityButton extends StatelessWidget {
  const _DensityButton({required this.density, required this.onTap});

  final int density;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    return Tooltip(
      message: '密度：$density 列（基准 1440 宽）',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          // 命中区 32×32（图形仍是 13×13 居中）：小按钮更要给够点击余量。
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: SizedBox(
                width: 13,
                height: 13,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var r = 0; r < 2; r++)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (var i = 0; i < 2; i++)
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: c.inkFaint,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 最近搜索。只在输入框有焦点时滑出。
class _RecentBar extends StatelessWidget {
  const _RecentBar({
    required this.visible,
    required this.items,
    required this.onPick,
  });

  final bool visible;
  final List<String> items;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    return AnimatedSize(
      duration: AppTheme.durBase,
      curve: AppTheme.curveEmph,
      alignment: Alignment.topCenter,
      child: !visible
          ? const SizedBox(width: double.infinity, height: 0)
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                AppTheme.pagePadding,
                0,
                AppTheme.pagePadding,
                AppTheme.gapM,
              ),
              child: Wrap(
                spacing: AppTheme.gapS,
                runSpacing: AppTheme.gapS,
                children: [
                  for (final q in items)
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => onPick(q),
                        behavior: HitTestBehavior.opaque,
                        // 视觉 24 高不变，命中区扩到 32，理由同 _ChipTap。
                        child: SizedBox(
                          height: 32,
                          child: Center(
                            child: Container(
                              height: 24,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: c.line),
                                borderRadius: BorderRadius.circular(
                                    AppTheme.chipRadius),
                              ),
                              child: Center(
                                child: Text(
                                  q.isEmpty ? '(空)' : q,
                                  style:
                                      AppType.chip.copyWith(color: c.inkDim),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
