import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/wallpaper_engine.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import 'favorite_view.dart';
import 'feature_view.dart';
import 'history_page.dart';
import 'search_view.dart';
import 'settings_page.dart';

/// 侧栏展开宽度与收起宽度。
///
/// 收起态 80 是 Material 的 NavigationRail 默认最小宽度，图标能完整放下；
/// 展开态 236 比默认的 256 窄一点，把省下的宽度留给内容区。
const double _kRailExtendedWidth = 236;
const double _kRailCollapsedWidth = 80;

/// Ctrl+1..5 切页。
class _SelectTabIntent extends Intent {
  const _SelectTabIntent(this.index);

  final int index;
}

/// 主界面骨架。
///
/// 原 UWP `HomePage` 用 `Pivot` 横向切「首页 / 收藏 / 概念」，
/// 另外用汉堡菜单跳到设置与关于。桌面端换成常驻的 `NavigationRail`：
/// 没有二级菜单，一眼能看到所有入口，也不用先展开再点。
///
/// 各 tab 用 `IndexedStack` 保活 —— 搜索到一半切走再切回来，
/// 列表和滚动位置都还在。保活也意味着切换时必须自己补一个过场，
/// 否则画面是一帧硬切，像被刷新了。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  bool _railExtended = true;

  /// 换壁纸的一次性结果。成功后显示 3 秒再收起。
  ChangeResult? _lastResult;
  bool _applying = false;
  Timer? _resultTimer;

  /// tab 过场。
  ///
  /// 用一次性 controller 而不是 `AnimatedSwitcher`：后者会重建 element 树，
  /// `IndexedStack` 里各页的 State（搜索词、滚动位置、输入焦点）会全丢。
  late final AnimationController _tabController = AnimationController(
    vsync: this,
    duration: AppTheme.durBase,
    value: 1,
  );

  late final Animation<double> _tabOpacity = CurvedAnimation(
    parent: _tabController,
    curve: AppTheme.curveIn,
  );

  /// 0.006 在当前高度下约 8px。再大就显得页面在「滑进来」，
  /// 切 tab 是同一层级的平级切换，不该有方向感。
  late final Animation<Offset> _tabOffset = Tween<Offset>(
    begin: const Offset(0, 0.006),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _tabController, curve: AppTheme.curveIn));

  static const List<_Destination> _destinations = <_Destination>[
    _Destination('搜索', Icons.search),
    _Destination('每日精选', Icons.today_outlined),
    _Destination('收藏', Icons.favorite_border),
    _Destination('历史', Icons.history),
    _Destination('设置', Icons.settings_outlined),
  ];

  @override
  void dispose() {
    _resultTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index < 0 || index >= _destinations.length) return;
    final state = context.read<AppState>();
    // 记下当前页：F5 只该刷眼前这一页，五个页面全活在 IndexedStack 里，
    // 只发信号不指明对象的话它们会一起重新联网。
    state.currentTab = index;
    if (index == _index) return;
    setState(() => _index = index);
    _tabController.forward(from: 0);
  }

  Future<void> _changeNow() async {
    if (_applying) return;
    _resultTimer?.cancel();
    setState(() {
      _applying = true;
      _lastResult = null;
    });
    final state = context.read<AppState>();
    final result = await state.changeWallpaper();
    if (!mounted) return;
    setState(() {
      _applying = false;
      _lastResult = result;
    });
    if (!result.success) {
      AppToast.error(context, result.message);
      return;
    }
    // 成功不弹提示：胶囊自己变绿说「已换上新壁纸」，3 秒后收起。
    _resultTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _lastResult = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final stage = state.currentStage;
    final theme = Theme.of(context);

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        for (var i = 0; i < _destinations.length; i++)
          SingleActivator(
            LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i),
            control: true,
          ): _SelectTabIntent(i),
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            const _ChangeWallpaperIntent(),
        const SingleActivator(LogicalKeyboardKey.f5):
            const _RefreshIntent(),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true):
            const _RefreshIntent(),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            const _FocusSearchIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _SelectTabIntent: CallbackAction<_SelectTabIntent>(
            onInvoke: (intent) {
              _select(intent.index);
              return null;
            },
          ),
          _ChangeWallpaperIntent: CallbackAction<_ChangeWallpaperIntent>(
            onInvoke: (_) {
              if (!_applying && context.read<AppState>().currentStage == null) {
                _changeNow();
              }
              return null;
            },
          ),
          _RefreshIntent: CallbackAction<_RefreshIntent>(
            onInvoke: (_) {
              // 刷新只作用于当前页：搜索页重查同一个关键词，精选页重算
              // 今日高分，收藏页重拉列表，历史页没有可刷的东西。
              context.read<AppState>().requestRefresh();
              return null;
            },
          ),
          _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
            onInvoke: (_) {
              // 在任何页按 Ctrl+K 都先切到搜索页再把光标送进输入框。
              _select(0);
              context.read<AppState>().focusSearchTick.value++;
              return null;
            },
          ),
        },
        child: Scaffold(
          appBar: AppBar(
            // 页面名当标题，「PRPR」退成左侧小标：以前标题恒为 PRPR，切页毫无反馈，
            // 页面身份只能靠内容区的段标题补，等于让段标题兼任页面标题。
            //
            // 折叠按钮也放在这里，而不是 NavigationRail 的 leading：rail 的 Column
            // 给 leading 的是松散约束，Align 会收缩到按钮自身宽度再被 Column 居中，
            // 结果按钮飘在导航图标右侧、看着像第 6 个入口。AppBar 的 leading 有固定
            // 宽度，位置完全可控。
            leadingWidth: 132,
            leading: Padding(
              padding: const EdgeInsets.only(left: AppTheme.gapS),
              child: Row(
                children: [
                  IconButton(
                    tooltip: _railExtended ? '收起侧栏' : '展开侧栏',
                    onPressed: () =>
                        setState(() => _railExtended = !_railExtended),
                    // 只转箭头不换图标：换图标是两帧之间的硬切，转 180°
                    // 能把「侧栏翻过去了」这件事讲完。
                    icon: AnimatedRotation(
                      turns: _railExtended ? 0 : 0.5,
                      duration: AppTheme.durMed,
                      curve: AppTheme.curveEmph,
                      child: const Icon(
                        Icons.keyboard_double_arrow_left,
                        size: AppTheme.iconSm,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.gapXs),
                  Flexible(
                    child: Text(
                      'PRPR',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            titleSpacing: 0,
            // 标题比内容区快 40ms 换掉：标题先动、内容跟上，
            // 视线先落在标题上再被引到正文，比两者同时动更有层次。
            title: AnimatedSwitcher(
              duration: AppTheme.durFast,
              switchInCurve: AppTheme.curveIn,
              transitionBuilder: (child, animation) {
                final offset = Tween<Offset>(
                  begin: const Offset(0, -0.25),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: offset, child: child),
                );
              },
              child: Text(
                _destinations[_index].label,
                key: ValueKey<int>(_index),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: AppTheme.gapM),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 任务胶囊、成功提示、换壁纸按钮共用同一行，不占内容区高度。
                    AnimatedSize(
                      duration: AppTheme.durMed,
                      curve: AppTheme.curveEmph,
                      alignment: Alignment.centerRight,
                      child: _trailingStatus(stage),
                    ),
                    const SizedBox(width: AppTheme.gapM),
                    FilledButton.icon(
                      onPressed:
                          (stage != null || _applying) ? null : _changeNow,
                      icon: const Icon(
                        Icons.wallpaper_outlined,
                        size: AppTheme.iconSm,
                      ),
                      label: const Text('换一张壁纸'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: Row(
            children: [
              AnimatedContainer(
                duration: AppTheme.durMed,
                curve: AppTheme.curveEmph,
                width: _railExtended ? _kRailExtendedWidth : _kRailCollapsedWidth,
                // rail 的宽度本身就由 extended 决定，切 extended 会在一帧内
                // 改变宽度/标签/布局，任何补间都盖不住。所以这里恒为展开态，
                // 外层裁切来出收起效果。
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: _kRailExtendedWidth,
                    maxWidth: _kRailExtendedWidth,
                    child: NavigationRail(
                      extended: true,
                      selectedIndex: _index,
                      onDestinationSelected: _select,
                      destinations: [
                        for (final d in _destinations)
                          NavigationRailDestination(
                            icon: Icon(d.icon),
                            label: Text(d.label),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                child: FadeTransition(
                  opacity: _tabOpacity,
                  child: SlideTransition(
                    position: _tabOffset,
                    child: IndexedStack(
                      index: _index,
                      children: const [
                        SearchView(),
                        FeatureView(),
                        FavoriteView(),
                        HistoryPage(),
                        SettingsPage(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// AppBar 右侧的状态区：优先级 任务中 > 刚成功 > 空。
  Widget _trailingStatus(ChangeStage? stage) {
    if (stage != null) {
      return _TaskPill(key: const ValueKey<String>('task'), stage: stage);
    }
    final result = _lastResult;
    if (result != null && result.success) {
      return const _SuccessChip(key: ValueKey<String>('done'));
    }
    return const SizedBox.shrink(key: ValueKey<String>('idle'));
  }
}

/// Ctrl+Enter 换壁纸。
class _ChangeWallpaperIntent extends Intent {
  const _ChangeWallpaperIntent();
}

class _RefreshIntent extends Intent {
  const _RefreshIntent();
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

/// 换壁纸的进度胶囊。
///
/// 以前是标题旁边一个 16px 的圈 + 一行「正在下载」。问题在于「换壁纸」是全应用
/// 唯一的真·长任务（拉列表 0.3~0.8s、下载 1~3s、检测 0.2~2s），反馈却是最弱的。
///
/// 现在换成**分段**进度而不是百分比：各阶段耗时完全不可知，一条按时间推进的
/// 进度条会在 90% 停十几秒，比不显示更让人焦虑；分段只表达「走到第几步了」。
class _TaskPill extends StatelessWidget {
  const _TaskPill({super.key, required this.stage});

  final ChangeStage stage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = stage.index;
    final total = ChangeStage.values.length;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.gapM,
        vertical: AppTheme.gapS,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            AnimatedContainer(
              duration: AppTheme.durFast,
              curve: AppTheme.curveIn,
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: i < current
                    ? scheme.primary
                    : i == current
                        ? scheme.primary.withValues(alpha: 0.45)
                        : scheme.outlineVariant,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ],
          const SizedBox(width: AppTheme.gapM),
          AnimatedSwitcher(
            duration: AppTheme.durFast,
            switchInCurve: AppTheme.curveIn,
            transitionBuilder: (child, animation) {
              final offset = Tween<Offset>(
                begin: const Offset(0, 0.12),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: offset, child: child),
              );
            },
            child: Text(
              stage.label,
              key: ValueKey<ChangeStage>(stage),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 换壁纸成功后的提示。
///
/// 少数几个允许回弹的地方之一：`easeOutBack` 会冲到约 1.1 倍再落回 1.0，
/// 「弹出来」的分量刚好和「成了」这件事匹配，又只持续 320ms。
class _SuccessChip extends StatelessWidget {
  const _SuccessChip({super.key});

  static const Color _green = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.9, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, value, child) =>
          Transform.scale(scale: value, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.gapM,
          vertical: AppTheme.gapS,
        ),
        decoration: BoxDecoration(
          color: _green.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppTheme.chipRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: AppTheme.iconXs, color: _green),
            const SizedBox(width: AppTheme.gapXs),
            Text(
              '已换上新壁纸',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon);

  final String label;
  final IconData icon;
}
