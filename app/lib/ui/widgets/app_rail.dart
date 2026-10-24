import 'package:flutter/material.dart';

import '../theme.dart';

/// 一条导航项。
class RailDestination {
  const RailDestination({
    required this.label,
    required this.icon,
    this.badge,
  });

  final String label;
  final IconData icon;

  /// 右上角的小计数（收藏数、历史条数）。0 或 null 不显示。
  final int? badge;
}

/// 左侧图标轨。
///
/// 从「236px 展开 + 可折叠」改成「56px 恒定宽度、只有图标」：
/// 五个入口的文字标签常驻要吃掉 180px，而这五个词的辨识度完全靠图标就够了，
/// 文字只是把它们从「猜」变成「读」，代价是把 1320px 的内容区压到 1140。
/// 需要文字时用 tooltip（鼠标悬停 400ms），需要跳转时用 Ctrl+1..5。
///
/// 当前项不是「填充一块更亮的底」而是「一块 surface 底 + 左侧 2px 金线」：
/// 深色界面上纯靠底色差异表现选中，在低亮度屏上会糊成一片；
/// 金线是这屏唯一的高饱和标记，视线一秒就能定位。
class AppRail extends StatelessWidget {
  const AppRail({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.trailing,
  });

  final List<RailDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 底部附属项（主题切换之类），和导航分开。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    return Container(
      width: AppTheme.railWidth,
      color: c.rail,
      child: Column(
        children: [
          const SizedBox(height: AppTheme.gapM),
          const _RailLogo(),
          const SizedBox(height: AppTheme.gapL),
          for (var i = 0; i < destinations.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.gapXs),
              child: _RailItem(
                destination: destinations[i],
                selected: i == selectedIndex,
                onTap: () => onSelected(i),
              ),
            ),
          const Spacer(),
          ?trailing,
          const SizedBox(height: AppTheme.gapM),
        ],
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final RailDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    final selected = widget.selected;
    final iconColor = selected ? c.gold : (_hover ? c.ink : c.inkDim);

    return Tooltip(
      message: widget.destination.label,
      waitDuration: const Duration(milliseconds: 420),
      preferBelow: false,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: AppTheme.railWidth,
            height: AppTheme.railItemSize + 8,
            child: Center(
              child: AnimatedContainer(
                duration: AppTheme.durFast,
                curve: AppTheme.curveEmph,
                width: AppTheme.railItemSize,
                height: AppTheme.railItemSize,
                decoration: BoxDecoration(
                  color: selected
                      ? c.surface
                      : (_hover ? c.surface.withValues(alpha: 0.55) : null),
                  borderRadius:
                      BorderRadius.circular(AppTheme.railItemRadius),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: AnimatedScale(
                        scale: _hover && !selected ? 1.08 : 1,
                        duration: AppTheme.durMicro,
                        child: Icon(
                          widget.destination.icon,
                          size: AppTheme.iconSm,
                          color: iconColor,
                        ),
                      ),
                    ),
                    // 选中指示线：贴左边，2x14。
                    if (selected)
                      Positioned(
                        left: -8,
                        top: (AppTheme.railItemSize - 14) / 2,
                        child: Container(
                          width: 2,
                          height: 14,
                          decoration: BoxDecoration(
                            color: c.gold,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    if ((widget.destination.badge ?? 0) > 0)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: c.gold,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            widget.destination.badge! > 99
                                ? '99+'
                                : '${widget.destination.badge}',
                            style: AppType.chip.copyWith(
                              fontSize: 8,
                              height: 1.1,
                              color: c.onGold,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶部的猫头标。
///
/// 用 CustomPaint 而不是塞一张 png：一只耳朵、一条鼻线的形状完全够用，
/// 矢量在任何 DPI 下都是清晰的，也不用给 assets 增加一个必须随包发布的文件。
class _RailLogo extends StatelessWidget {
  const _RailLogo();

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    return Tooltip(
      message: 'MoeCatnip',
      waitDuration: const Duration(milliseconds: 420),
      child: SizedBox(
        width: AppTheme.railWidth,
        height: 24,
        child: CustomPaint(painter: _CatPainter(c.gold)),
      ),
    );
  }
}

class _CatPainter extends CustomPainter {
  _CatPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + 1;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 脸：比正圆略扁，下半收一点，像猫的下巴。
    final face = Path()
      ..moveTo(cx - 7, cy - 2)
      ..cubicTo(cx - 7, cy + 6, cx + 7, cy + 6, cx + 7, cy - 2)
      ..cubicTo(cx + 7, cy - 6.5, cx + 3.5, cy - 7.5, cx, cy - 7.5)
      ..cubicTo(cx - 3.5, cy - 7.5, cx - 7, cy - 6.5, cx - 7, cy - 2)
      ..close();
    canvas.drawPath(face, paint);

    // 两只耳朵：从头顶向外挑出的两个三角。
    final leftEar = Path()
      ..moveTo(cx - 6.6, cy - 5.2)
      ..lineTo(cx - 6, cy - 10)
      ..lineTo(cx - 2.6, cy - 7.4);
    final rightEar = Path()
      ..moveTo(cx + 6.6, cy - 5.2)
      ..lineTo(cx + 6, cy - 10)
      ..lineTo(cx + 2.6, cy - 7.4);
    canvas.drawPath(leftEar, paint..style = PaintingStyle.stroke);
    canvas.drawPath(rightEar, paint);

    // 两只眼 + 一条鼻线。眼用实心小点，鼻线用短横，
    // 三者挤在 4px 的带子里，远看是一个「表情」而不是三个符号。
    final dot = Paint()..color = color;
    canvas.drawCircle(Offset(cx - 2.4, cy - 1.6), 0.9, dot);
    canvas.drawCircle(Offset(cx + 2.4, cy - 1.6), 0.9, dot);
    canvas.drawLine(
      Offset(cx - 1.2, cy + 2.2),
      Offset(cx + 1.2, cy + 2.2),
      paint..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _CatPainter old) => old.color != color;
}
