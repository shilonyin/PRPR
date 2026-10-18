import 'package:flutter/material.dart';

import '../theme.dart';

/// 轻量提示。
///
/// 以前任何结果都弹一条 `SnackBar`：「已收藏」「已复制」「已设为壁纸」…
/// 全都一样重、一样停四秒，还会排队堆叠。现在的原则：
///
/// - **成功类不弹**：按钮/图标的形态变化本身就是反馈（收藏变实心、
///   复制图标临时变对勾）。用户看到状态变了，不需要再读一句「已收藏」。
/// - **失败才弹，而且只弹一条**：用 [hideCurrentSnackBar] 而不是
///   [clearSnackBars]，后者会把正在显示的提示直接掐掉再排新的，闪烁很明显。
abstract final class AppToast {
  /// 失败提示。固定宽度 360、浮动：桌面窗口很宽，全宽横条的阅读成本过高。
  static void error(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        width: 360,
        duration: AppTheme.durTask * 10,
      ),
    );
  }

  /// 结果里失败的那部分才弹窗；成功静默。
  static void resultIfFailed(
    BuildContext context, {
    required bool success,
    required String message,
  }) {
    if (success) return;
    error(context, message);
  }
}
