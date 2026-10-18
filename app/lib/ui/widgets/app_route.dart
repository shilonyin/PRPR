import 'package:flutter/material.dart';

import '../theme.dart';

/// 详情页转场。
///
/// 不用 `MaterialPageRoute`：它在桌面（及 Android）走 `ZoomPageTransitionsBuilder`
/// —— 整页从 0.85 放大淡入 300ms。这一层和 Hero 的飞行叠加在一起，视觉上是
/// 「图在飞、底下那层也在动」，用户说不清自己在看哪个。
///
/// 这里把整页动画压到很轻，并且推迟到 25% 之后才开始：前 65ms 只有 Hero 在动，
/// 剩下 195ms 页面背景淡入接住它。返回更快（200ms），因为返回时用户已经知道
/// 要去哪儿，不需要再解释一遍。
Route<T> appPageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: AppTheme.durSlow,
    reverseTransitionDuration: _kReverseDuration,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: const Interval(0.25, 1, curve: Curves.easeOut),
      );
      return FadeTransition(opacity: curved, child: child);
    },
  );
}

const Duration _kReverseDuration = Duration(milliseconds: 200);
