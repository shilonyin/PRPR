import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// 图片在「瀑布流瓦片 ↔ 详情页大图」之间飞行时的外观。
///
/// 默认的 shuttle 直接复用源 widget 的 `BoxFit`（瓦片是 `cover`），落到详情页
/// 却变成 `contain`，途中会「啪」地跳一下；圆角也会在一次飞行内从 12 突变到 0。
/// 两端都用同一个 builder，飞行过程才是一条连续的曲线。
///
/// 飞行中一律 `cover`：途中矩形是两端插值出来的，用户看的是「同一张图在变形」，
/// 不该同时看到它内部的留白也在变。
Widget heroFlightShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromContext,
  BuildContext toContext,
  String imageUrl,
) {
  // 飞行起点（瓦片）和终点（详情大图）现在都是 imageRadius，
  // 沿途保持不变才是一条连续的曲线；以前从 cardRadius 往 0.4 倍收缩，
  // 是因为两端本来是 12 和 0，现在两端同值，插值反而会让角在中途跳一下。
  return ClipRRect(
    borderRadius: BorderRadius.circular(AppTheme.imageRadius),
    child: CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero,
    ),
  );
}