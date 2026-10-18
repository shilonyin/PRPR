import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'services/app_settings.dart';
import 'ui/app_state.dart';
import 'ui/pages/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
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
            home: const HomePage(),
          );
        },
      ),
    );
  }
}