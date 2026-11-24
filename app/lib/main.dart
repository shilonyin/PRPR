import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'services/app_settings.dart';
import 'services/system_proxy.dart';
import 'services/tray_service.dart';
import 'services/window_theme.dart';
import 'ui/app_state.dart';
import 'ui/pages/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  // 必须在任何 HttpClient 创建之前：让 CachedNetworkImage、http 包、
  // flutter_cache_manager 全都走系统代理，否则双击启动时网络请求会静默直连。
  SystemProxy.install();

  WidgetsFlutterBinding.ensureInitialized();

  // booru 大图场景：一张 4000×6000 原图解码约 96MB，默认 imageCache
  // （100MB）会被单张大图吃满，把瀑布流缩略图批量逐出，来回滚动就是
  // 反复解码。放宽到 150MB；张数上限压到 150，因为这里缓存的都是大图，
  // 按张数兜底比默认的 1000 张更贴合实际内存。
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 150 * 1024 * 1024
    ..maximumSize = 150;

  // 桌面窗口：给一个合理的初始尺寸并居中，
  // 否则 Flutter 默认的 1280x720 会贴在屏幕左上角。
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1360, 900),
      minimumSize: Size(900, 600),
      center: true,
      title: 'PRPR',
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    // 拦截关闭按钮：真正「退出」还是「隐藏到托盘」由 onWindowClose
    // 按设置决定；不拦的话系统会直接销毁窗口，后台常驻无从谈起。
    await windowManager.setPreventClose(true);
  }

  final state = await AppState.create();

  if (Platform.isWindows) {
    windowManager.addListener(_AppWindowListener(state));
  }

  runApp(PrprApp(state: state));

  if (Platform.isWindows) {
    // 托盘初始化涉及图标落盘与原生调用，放在首帧之后，避免阻塞启动；
    // 失败时降级为无托盘，程序照常运行。
    WidgetsBinding.instance.addPostFrameCallback((_) => _initTray(state));
  }
}

/// 托盘是否可用。图标落盘或原生创建失败时降级为「无托盘」：
/// 此时关窗必须真正退出 —— 否则进程隐藏起来却没有托盘图标，
/// 用户再也唤不回窗口，只能去任务管理器杀进程。
bool _trayAvailable = false;

Future<void> _initTray(AppState state) async {
  final tray = TrayService(
    onChangeWallpaper: () async {
      // 与自动换壁纸定时器同一保护：正在换壁纸时不叠加一次。
      if (state.engine.isBusy) return;
      await state.changeWallpaper();
    },
    onExit: () async {
      // 托盘「退出」是明确的退出意图：解除关闭拦截后直接销毁窗口。
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    },
  );
  _trayAvailable = await tray.init();
  // 成功后托盘的原生监听闭包持有 TrayService 实例引用，不会被 GC；
  // 失败时 init 内部已释放已创建的原生句柄，这里无需清理。
}

/// 关闭按钮的实际行为：设置开启「关闭时最小化到托盘」且托盘可用时隐藏窗口，
/// 否则真正销毁。
class _AppWindowListener extends WindowListener {
  _AppWindowListener(this._state);

  final AppState _state;

  @override
  void onWindowClose() async {
    if (_trayAvailable && _state.settings.minimizeToTray) {
      // 隐藏而不是销毁：进程存活，自动换壁纸定时器继续跑。
      await windowManager.hide();
      return;
    }
    await windowManager.destroy();
  }
}

/// 应用根组件。
///
/// 主题跟随 `AppSettings.themeModeIndex`：0 = 跟随系统，1 = 浅色，2 = 深色，
/// 对应原 UWP 设置页的主题下拉。
class PrprApp extends StatefulWidget {
  const PrprApp({super.key, required this.state});

  final AppState state;

  @override
  State<PrprApp> createState() => _PrprAppState();
}

class _PrprAppState extends State<PrprApp> {
  /// 上一次应用到原生标题栏的配色签名。builder 每帧都会跑，
  /// 配色没变就跳过，避免每帧都走一次 Win32 调用。
  int? _lastTitlebarSignature;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: widget.state),
        ChangeNotifierProvider<AppSettings>.value(
          value: widget.state.settings,
        ),
      ],
      // 只订阅 themeModeIndex：设置页每改一个键都会 notify，
      // 但只有主题档位变化才需要重建 MaterialApp。
      child: Builder(
        builder: (context) {
          final modeIndex =
              context.select<AppSettings, int>((s) => s.themeModeIndex);
          final mode = switch (modeIndex) {
            1 => ThemeMode.light,
            2 => ThemeMode.dark,
            _ => ThemeMode.system,
          };
          return MaterialApp(
            title: 'PRPR',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: mode,
            // 主题切换默认是硬切，整屏颜色一帧内翻掉最刺眼。给一个短过渡，
            // 但只动颜色、不动位移和缩放——换肤不需要「表演」。
            themeAnimationDuration: AppTheme.durMed,
            themeAnimationCurve: AppTheme.curveEmph,
            builder: (context, child) {
              // 原生标题栏是系统画的，Flutter 主题管不到它：深色内容顶一条
              // 白标题栏，沉浸感一秒钟就没了。挂在 builder 里能拿到当前
              // 真正生效的主题（跟随系统档下 MaterialApp 已经解析完明暗），
              // 不用自己再算一遍。
              final c = AppColor.of(context);
              final dark = Theme.of(context).brightness == Brightness.dark;
              final signature = Object.hash(dark, c.bg, c.ink, c.line);
              if (signature != _lastTitlebarSignature) {
                _lastTitlebarSignature = signature;
                WindowTheme.apply(c, dark: dark);
              }
              return child ?? const SizedBox.shrink();
            },
            home: const HomePage(),
          );
        },
      ),
    );
  }
}
