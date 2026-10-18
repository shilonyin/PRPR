import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
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

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const Text('PRPR'),
            if (stage != null) ...[
              const SizedBox(width: 16),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                stage.label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: stage == null ? _changeNow : null,
              icon: const Icon(Icons.wallpaper_outlined, size: 18),
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
            leading: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: IconButton(
                tooltip: _railExtended ? '收起侧栏' : '展开侧栏',
                onPressed: () =>
                    setState(() => _railExtended = !_railExtended),
                icon: Icon(
                  _railExtended
                      ? Icons.chevron_left
                      : Icons.chevron_right,
                ),
              ),
            ),
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

class _Destination {
  const _Destination(this.label, this.icon);

  final String label;
  final IconData icon;
}
