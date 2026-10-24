import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'services/app_settings.dart';
import 'services/system_proxy.dart';
import 'services/window_theme.dart';
import 'ui/app_state.dart';
import 'ui/pages/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  // 必须在任何 HttpClient 创建之前：让 CachedNetworkImage、http 包、
  // flutter_cache_manager 全都走系统代理，否则双击启动时网络请求会静默直连。
  SystemProxy.install();

  WidgetsFlutterBinding.ensureInitialized();

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
  }

  final state = await AppState.create();

  runApp(PrprApp(state: state));
}

/// 应用根组件。
///
/// 主题跟随 `AppSettings.themeModeIndex`：0 = 跟随系统，1 = 浅色，2 = 深色，
/// 对应原 UWP 设置页的主题下拉。
class PrprApp extends StatelessWidget {
  const PrprApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: state),
        ChangeNotifierProvider<AppSettings>.value(value: state.settings),
      ],
      child: Consumer<AppSettings>(
        builder: (context, settings, _) {
          final mode = switch (settings.themeModeIndex) {
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
              WindowTheme.apply(
                AppColor.of(context),
                dark: Theme.of(context).brightness == Brightness.dark,
              );
              return child ?? const SizedBox.shrink();
            },
            home: const HomePage(),
          );
        },
      ),
    );
  }
}
