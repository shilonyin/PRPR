import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/wallpaper_engine.dart';
import '../app_state.dart';
import '../theme.dart';
import 'favorite_view.dart';
import 'feature_view.dart';
import 'history_page.dart';
import 'search_view.dart';
import 'settings_page.dart';

/// 主界面骨架。
///
/// 原 UWP `HomePage` 用 `Pivot` 横向切「首页 / 收藏 / 概念」，
/// 另外用汉堡菜单跳到设置与关于。桌面端换成常驻的 `NavigationRail`：
/// 没有二级菜单，一眼能看到所有入口，也不用先展开再点。
///
/// 各 tab 用 `IndexedStack` 保活 —— 搜索到一半切走再切回来，
/// 列表和滚动位置都还在。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  bool _railExtended = true;

  static const List<_Destination> _destinations = <_Destination>[
    _Destination('搜索', Icons.search),
    _Destination('每日精选', Icons.today_outlined),
    _Destination('收藏', Icons.favorite_border),
    _Destination('历史', Icons.history),
    _Destination('设置', Icons.settings_outlined),
  ];

  Future<void> _changeNow() async {
    final state = context.read<AppState>();
    final result = await state.changeWallpaper();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final stage = state.currentStage;
    final theme = Theme.of(context);

    return Scaffold(
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
                onPressed: () => setState(() => _railExtended = !_railExtended),
                icon: Icon(
                  _railExtended
                      ? Icons.keyboard_double_arrow_left
                      : Icons.keyboard_double_arrow_right,
                  size: AppTheme.iconSm,
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
        title: Row(
          children: [
            Text(_destinations[_index].label),
            if (stage != null) ...[
              const SizedBox(width: AppTheme.gapL),
              _StageIndicator(stage: stage),
            ],
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppTheme.gapM),
            child: FilledButton.icon(
              onPressed: stage == null ? _changeNow : null,
              icon: const Icon(Icons.wallpaper_outlined, size: AppTheme.iconSm),
              label: const Text('换一张壁纸'),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            extended: _railExtended,
            labelType: _railExtended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
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
        ],
      ),
    );
  }
}

/// 换壁纸的进度指示。
///
/// 换壁纸要拉列表、下载原图、跑人脸检测，正常一两秒就完；但「拉列表」那一步
/// 在网络差时可能要十几秒。以前 AppBar 一有 stage 就立刻转圈，导致点按钮后
/// 立刻闪一下再消失，用户还没读完「正在下载」四个字。延迟 1 秒出现：
/// 快的操作干脆不显示转圈，慢的操作才提示。
class _StageIndicator extends StatefulWidget {
  const _StageIndicator({required this.stage});

  final ChangeStage stage;

  @override
  State<_StageIndicator> createState() => _StageIndicatorState();
}

class _StageIndicatorState extends State<_StageIndicator> {
  static const Duration _delay = Duration(seconds: 1);

  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(covariant _StageIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 阶段变了不必重置计时器：用户关心的是「这个操作慢不慢」，
    // 不是「这一阶段慢不慢」。
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer(_delay, () {
      if (!mounted) return;
      setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: AppTheme.iconXs,
            height: AppTheme.iconXs,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppTheme.gapS),
          Text(
            widget.stage.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon);

  final String label;
  final IconData icon;
}
