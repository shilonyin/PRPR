import 'package:flutter/material.dart';

import '../theme.dart';

/// 页面顶栏。
///
/// 新外壳没有全局 AppBar：搜索页的顶栏里嵌着搜索语法，设置页的顶栏只有
/// 页名和版本号，详情页的顶栏是返回箭头和面包屑——三者的高度和内容都不同，
/// 用一个 AppBar 去兼容会变成一个到处是 if 的东西。
///
/// 所以 AppBar 退成这个薄组件：给一条底线、一个固定高度、一段左右留白，
/// 里面放什么由页面决定。
class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.child,
    this.height = AppTheme.topbarHeight,
    this.padding = const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding),
    this.showBottomLine = true,
    this.color,
  });

  final Widget child;
  final double height;
  final EdgeInsets padding;
  final bool showBottomLine;

  /// 底栏色。默认跟 scaffold 相同；详情页左半是更深的画布，
  /// 顶栏要覆盖整宽，才需要显式指定。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.bg,
        border: showBottomLine
            ? Border(bottom: BorderSide(color: c.line))
            : null,
      ),
      child: child,
    );
  }
}

/// 顶栏左侧的返回按钮。统一成 32x32 的命中块 + 18 的箭头。
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onPressed, this.tooltip = '返回'});

  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: tooltip,
        onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
        icon: Icon(Icons.arrow_back, size: 18, color: c.inkDim),
      ),
    );
  }
}

/// 面包屑：搜索 / landscape / sky。
///
/// 分隔符用等宽字体画，不用图标——「/」在等宽里天然对齐，
/// 图标会在每个节点前后各带一圈空白，五个节点就散开了。
class AppBreadcrumb extends StatelessWidget {
  const AppBreadcrumb({super.key, required this.parts, this.onTap});

  final List<String> parts;

  /// 点某一段回跳。索引对应 parts。
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    final style = AppType.monoData.copyWith(color: c.inkFaint);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('/', style: style.copyWith(color: c.lineStrong)),
            ),
          if (onTap == null)
            Text(parts[i], style: style)
          else
            _BreadcrumbTap(
              label: parts[i],
              style: style,
              onTap: () => onTap!(i),
            ),
        ],
      ],
    );
  }
}

class _BreadcrumbTap extends StatefulWidget {
  const _BreadcrumbTap({
    required this.label,
    required this.style,
    required this.onTap,
  });

  final String label;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  State<_BreadcrumbTap> createState() => _BreadcrumbTapState();
}

class _BreadcrumbTapState extends State<_BreadcrumbTap> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedDefaultTextStyle(
          duration: AppTheme.durFast,
          style: widget.style.copyWith(
            color: _hover ? c.ink : c.inkFaint,
            decoration: _hover ? TextDecoration.underline : null,
            decorationColor: c.lineStrong,
          ),
          child: Text(widget.label),
        ),
      ),
    );
  }
}

/// 顶栏里的等宽小标签（No. 1270859 / v2.4.0 / 137 张）。
class AppTopBarLabel extends StatelessWidget {
  const AppTopBarLabel(
    this.text, {
    super.key,
    this.color,
    this.emphasize = false,
  });

  final String text;
  final Color? color;

  /// 金色强调（计数、编号这种「页面的定位信息」）。
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    return Text(
      text,
      style: AppType.monoData.copyWith(
        fontSize: 11.5,
        color: color ?? (emphasize ? c.goldText : c.inkFaint),
        fontWeight: emphasize ? FontWeight.w500 : FontWeight.w400,
      ),
    );
  }
}
