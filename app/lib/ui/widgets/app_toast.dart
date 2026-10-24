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
    _show(context, message, _ToastKind.error);
  }

  /// 中性提示。只用于「点了某个还没实现的选项」这种需要一句话解释的场合。
  static void info(BuildContext context, String message) {
    _show(context, message, _ToastKind.info);
  }

  static void _show(BuildContext context, String message, _ToastKind kind) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final c = AppColor.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            // 用一条 2px 的竖线代替圆形图标：这条提示是「一句话」，
            // 配一个 16px 的图会让 360 宽的条子里出现两个视觉重心。
            Container(
              width: 2,
              height: 14,
              decoration: BoxDecoration(
                color: kind == _ToastKind.error ? c.danger : c.inkFaint,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(width: AppTheme.gapM),
            Expanded(
              child: Text(
                message,
                style: AppType.body.copyWith(color: c.ink),
              ),
            ),
          ],
        ),
        backgroundColor: c.surface,
        behavior: SnackBarBehavior.floating,
        width: 360,
        duration: kind == _ToastKind.error
            ? const Duration(seconds: 4)
            : const Duration(seconds: 3),
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

enum _ToastKind { error, info }
