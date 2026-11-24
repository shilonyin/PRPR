import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart'
    show
        ContextMenuTrigger,
        Image,
        Menu,
        MenuItem,
        MenuItemClickedEvent,
        MenuItemType,
        TrayIcon,
        TrayIconClickedEvent,
        TrayIconDoubleClickedEvent;
import 'package:window_manager/window_manager.dart';

/// 系统托盘图标与右键菜单。
///
/// tray_manager 0.8.x 起把旧的 TrayManager/Menu 桥接层整体标记为 deprecated，
/// 主入口导出的是 nativeapi 的 TrayIcon/Menu，这里直接用新 API。
///
/// 本服务不 import 任何 ui：「换壁纸」与「退出」由 main.dart 注入回调 ——
/// 托盘是系统级入口，窗口隐藏、widget 树不活跃时也必须能用。
class TrayService {
  TrayService({
    required this.onChangeWallpaper,
    required this.onExit,
  });

  /// 托盘图标复用 Windows runner 的 app_icon.ico，打进 Flutter asset。
  static const String _iconAsset = 'windows/runner/resources/app_icon.ico';

  /// 换壁纸回调：由 main.dart 注入，走 AppState.changeWallpaper。
  final Future<void> Function() onChangeWallpaper;

  /// 退出回调：由 main.dart 注入，解除关闭拦截并销毁窗口。
  final Future<void> Function() onExit;

  // nativeapi 的句柄都是 ffi.Finalizable：Dart 对象一旦不可达，原生句柄
  // 就会被 finalizer 释放。图标、菜单、菜单项必须全部由字段持有，
  // 不能只当 init 里的局部变量，否则托盘会在某次 GC 后凭空消失。
  TrayIcon? _trayIcon;
  Image? _iconImage;
  Menu? _menu;
  final List<MenuItem> _menuItems = [];

  /// 托盘是否已就绪。main.dart 用它决定关窗时能不能隐藏到托盘。
  bool get isReady => _trayIcon != null;

  /// 初始化托盘。任何一步失败都返回 false（降级为无托盘），不抛异常：
  /// 托盘是锦上添花，图标落盘失败不该阻止程序正常启动。
  Future<bool> init() async {
    if (!Platform.isWindows) return false;
    try {
      final iconPath = await _materializeIcon();
      if (iconPath == null) return false;

      // Windows 托盘吃 ico 文件：先把 asset 落盘，再按路径加载。
      final image = Image.fromFile(iconPath);
      if (image == null) return false;
      final trayIcon = TrayIcon.create();
      final menu = Menu.create();
      if (trayIcon == null || menu == null) {
        image.dispose();
        trayIcon?.dispose();
        menu?.dispose();
        return false;
      }

      // 每个菜单项挂自己的监听闭包来区分点击，不必维护 key/id 查找表。
      final items = <MenuItem>[];
      MenuItem? addItem(String label, Future<void> Function() action) {
        final item = MenuItem.createWithLabelAndType(label, MenuItemType.normal);
        if (item == null) return null;
        item.addListener((event) {
          if (event is MenuItemClickedEvent) return action();
        });
        items.add(item);
        return item;
      }

      final showItem = addItem('显示主窗口', _showMainWindow);
      final changeItem = addItem('立即换一张壁纸', onChangeWallpaper);
      final exitItem = addItem('退出', onExit);
      if (showItem == null || changeItem == null || exitItem == null) {
        for (final item in items) {
          item.dispose();
        }
        menu.dispose();
        trayIcon.dispose();
        image.dispose();
        return false;
      }
      menu.addItem(showItem);
      menu.addItem(changeItem);
      menu.addSeparator();
      menu.addItem(exitItem);

      trayIcon
        ..icon = image
        ..setTooltip('PRPR')
        ..setContextMenu(menu)
        // 显式指定右键弹菜单：不依赖各平台原生默认触发方式。
        ..setContextMenuTrigger(ContextMenuTrigger.rightClicked)
        ..addListener((event) {
          // 左键单击与双击都唤回主窗口；右键交给上下文菜单。
          if (event is TrayIconClickedEvent ||
              event is TrayIconDoubleClickedEvent) {
            _showMainWindow();
          }
        })
        ..setVisible(true);

      _iconImage = image;
      _menu = menu;
      _menuItems.addAll(items);
      _trayIcon = trayIcon;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 把 ico 从 asset 落盘到应用支持目录，返回绝对路径；失败返回 null。
  /// 与 face_detector 的级联落盘同一模式：原生接口只认文件路径，
  /// 而 flutter_assets 里的资源没有稳定的磁盘位置。
  Future<String?> _materializeIcon() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final target =
          File('${dir.path}${Platform.pathSeparator}prpr_tray_icon.ico');
      if (!await target.exists()) {
        final data = await rootBundle.load(_iconAsset);
        await target.parent.create(recursive: true);
        await target.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
      return target.path;
    } catch (_) {
      return null;
    }
  }

  /// 唤回主窗口：最小化先还原，再 show + focus。
  Future<void> _showMainWindow() async {
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  /// 释放原生句柄。进程退出前调用；托盘监听闭包持有本实例引用，
  /// 不调用也不会提前 GC，这里只是让清理链完整。
  void dispose() {
    for (final item in _menuItems) {
      item.dispose();
    }
    _menuItems.clear();
    _menu?.dispose();
    _menu = null;
    _iconImage?.dispose();
    _iconImage = null;
    _trayIcon?.dispose();
    _trayIcon = null;
  }
}
