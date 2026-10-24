import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/wallpaper_engine.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/app_rail.dart';
import '../widgets/app_toast.dart';
import 'favorite_view.dart';
import 'feature_view.dart';
import 'history_page.dart';
import 'search_view.dart';
import 'settings_page.dart';

/// Ctrl+1..5 切页。
class _SelectTabIntent extends Intent {
  const _SelectTabIntent(this.index);

  final int index;
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

/// 主界面骨架。
///
/// 上一版是 236px 可折叠文字侧栏 + AppBar 标题。两个问题叠在一起：
///
/// 1. 侧栏占宽。五个入口的标签常驻 236px，而内容区才是这个应用的全部意义
///    （看图）。收成 56px 只有图标之后，1320px 正好摆下 4 列 325 的瓦片。
/// 2. AppBar 把「页面名 + 操作 + 状态」三件事挤在一条 56px 的带子上，
///    而搜索页真正需要常驻顶栏的是**搜索语法本身**。所以 AppBar 取消，
///    各页自己画顶栏（见 widgets/app_topbar.dart）：搜索页 79px 内嵌输入、
///    设置页 56px 只有页名、详情页 56px 是返回箭头和面包屑。
///
/// 「换一张壁纸」这个全局动作从顶栏挪到导航轨底部：它在任何页都可用，
/// 属于应用级动作而不是页面级动作；放顶栏会被每一页的顶栏重新实现一遍。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  /// 启动时停在哪一页。默认 0 = 搜索页。
  ///
  /// 可以用环境变量 PRPR_TAB=0..4 覆盖（构建期 PRPR_TAB dart-define 也行）。
  /// 加这个是为了截图核对 —— 桌面端没有可靠的自动化点击，靠鼠标屏幕坐标
  /// 换算去点 rail 每次都被 150% DPI 缩放坑，改成可配置比反复调坐标省事。
  /// 环境变量优先于 dart-define，这样换一页截图不用重新编译。
  int _index = _initialIndex();

  static int _initialIndex() {
    final raw = Platform.environment['PRPR_TAB'];
    final fromEnv = int.tryParse(raw ?? '');
    final index = fromEnv ?? const int.fromEnvironment('PRPR_TAB', defaultValue: 0);
    return index.clamp(0, 4);
  }

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

  static const List<RailDestination> _destinations = <RailDestination>[
    RailDestination(label: '搜索  Ctrl+1', icon: Icons.search),
    RailDestination(label: '每日精选  Ctrl+2', icon: Icons.today_outlined),
    RailDestination(label: '收藏  Ctrl+3', icon: Icons.favorite_border),
    RailDestination(label: '历史  Ctrl+4', icon: Icons.history),
    RailDestination(label: '设置  Ctrl+5', icon: Icons.tune),
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
    // 成功不弹提示：轨底那颗按钮自己变绿说「已换」，3 秒后恢复。
    _resultTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _lastResult = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final stage = state.currentStage;

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
          // 没有 AppBar，也没有 SafeArea：桌面窗口没有刘海，
          // 系统标题栏由 runner 自己管。内容从 0,0 开始画。
          body: Row(
            children: [
              AppRail(
                destinations: _destinations,
                selectedIndex: _index,
                onSelected: _select,
                trailing: _WallpaperButton(
                  applying: _applying,
                  stage: stage,
                  lastResult: _lastResult,
                  onTap: _changeNow,
                ),
              ),
              // rail 与内容之间只有 1px 分界，不用 VerticalDivider 组件：
              // 它带 16 的默认边距，会把内容区起点推离 56。
              Container(width: 1, color: AppColor.of(context).line),
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
}

/// 轨底的应用级动作：换壁纸。
///
/// 三种状态共用一个 40x40 的位置：空闲是金色描边图标，进行中是分段进度环，
/// 刚成功是绿色勾。位置固定、只换内容，用户第二次点的时候手不用重新找。
class _WallpaperButton extends StatelessWidget {
  const _WallpaperButton({
    required this.applying,
    required this.stage,
    required this.lastResult,
    required this.onTap,
  });

  final bool applying;
  final ChangeStage? stage;
  final ChangeResult? lastResult;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    final busy = stage != null || applying;
    final done = !busy && lastResult?.success == true;

    return Tooltip(
      message: busy
          ? (stage?.label ?? '换壁纸中')
          : (done ? '已换上新壁纸' : '换一张壁纸  Ctrl+Enter'),
      waitDuration: const Duration(milliseconds: 420),
      preferBelow: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.gapS),
        child: MouseRegion(
          cursor: busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: busy ? null : onTap,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: AppTheme.railWidth,
              height: AppTheme.railItemSize + 8,
              child: Center(
                child: AnimatedContainer(
                  duration: AppTheme.durFast,
                  width: AppTheme.railItemSize,
                  height: AppTheme.railItemSize,
                  decoration: BoxDecoration(
                    color: done
                        ? c.safe.withValues(alpha: 0.16)
                        : c.gold.withValues(alpha: busy ? 0.10 : 0.14),
                    borderRadius:
                        BorderRadius.circular(AppTheme.railItemRadius),
                  ),
                  child: Center(
                    child: busy
                        ? _StageRing(stage: stage, applying: applying)
                        : Icon(
                            done
                                ? Icons.check_rounded
                                : Icons.wallpaper_outlined,
                            size: AppTheme.iconSm,
                            color: done ? c.safe : c.gold,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 换壁纸的分段进度环。
///
/// 用环而不是百分比：各阶段耗时完全不可知（拉列表 0.3~0.8s、下载 1~3s、
/// 检测 0.2~2s），按时间推进的百分比会在 90% 停十几秒，比不显示更焦虑。
/// 环上按阶段分 5 段，只表示「走到第几步」。
class _StageRing extends StatelessWidget {
  const _StageRing({required this.stage, required this.applying});

  final ChangeStage? stage;
  final bool applying;

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    final total = ChangeStage.values.length;
    final done = stage == null ? 0 : stage!.index;

    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(
        painter: _RingPainter(
          total: total,
          done: done,
          color: c.gold,
          track: c.line,
        ),
        child: Center(
          child: applying && stage == null
              ? SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: c.gold,
                  ),
                )
              : Icon(Icons.wallpaper_outlined, size: 11, color: c.gold),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.total,
    required this.done,
    required this.color,
    required this.track,
  });

  final int total;
  final int done;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
    const gap = 0.16;
    final sweep = (6.28318 - gap * total) / total;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < total; i++) {
      final start = -1.5708 + i * (sweep + gap);
      base.color = i <= done ? color : track;
      canvas.drawArc(rect, start, sweep, false, base);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.done != done || old.total != total || old.color != color;
}
