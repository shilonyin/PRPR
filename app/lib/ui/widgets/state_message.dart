import 'package:flutter/material.dart';

import '../theme.dart';

/// 内容区「没有内容可看」时的统一展示。
///
/// 以前错误态、空态、加载态各写各的：字号差 2px、颜色同一个、间距 12/6/6/16
/// 毫无节奏，读者分不清哪句是结论、哪句是建议。抽成一个组件后三态共用同一套
/// 结构（图标 → 标题 → 具体原因 → 通用建议 → 动作），页面只负责填内容。
///
/// 宽度上限 480：420 时「…请确认系统代理已开启」的最后一个字会单独折行。
class StateMessage extends StatelessWidget {
  const StateMessage({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.hint,
    this.iconColor,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.busy = false,
    this.suggestions = const <String>[],
    this.onSuggestion,
    this.maxWidth = 480,
  });

  /// 顶部图标。错误用 cloud_off / 空用 image_outlined 之类。
  final IconData icon;

  /// 一句话结论。用 titleMedium + w600 + onSurface，是全块唯一的强调。
  final String title;

  /// 具体原因（例如站点返回的异常文本）。
  final String? detail;

  /// 通用建议。比 [detail] 更淡一级，避免两句抢注意力。
  final String? hint;

  final Color? iconColor;

  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  /// 动作执行中：按钮原位换成 16px 进度环，整块压暗并吃掉点击。
  ///
  /// 刻意不整块消失再重来 —— 重试时界面突然空一下，用户会以为点错了。
  final bool busy;

  /// 空态时给的可点建议标签。
  final List<String> suggestions;
  final ValueChanged<String>? onSuggestion;

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AnimatedOpacity(
      opacity: busy ? 0.6 : 1,
      duration: AppTheme.durFast,
      curve: AppTheme.curveIn,
      child: IgnorePointer(
        ignoring: busy,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.gapXxl),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 图标从 0.9 弹到 1.0：错误出现时有一点「落下来」的重量，
                  // 但不用回弹曲线 —— 这是故障提示，不该显得活泼。
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.9, end: 1),
                    duration: AppTheme.durTask,
                    curve: AppTheme.curveIn,
                    builder: (context, value, child) =>
                        Transform.scale(scale: value, child: child),
                    child: Icon(
                      icon,
                      size: AppTheme.iconXl,
                      color: iconColor ?? scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppTheme.gapL),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (detail != null && detail!.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.gapS),
                    Text(
                      detail!,
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (hint != null && hint!.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.gapS),
                    Text(
                      hint!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                  if (suggestions.isNotEmpty && onSuggestion != null) ...[
                    const SizedBox(height: AppTheme.gapL),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: AppTheme.gapS,
                      runSpacing: AppTheme.gapS,
                      children: [
                        for (final tag in suggestions)
                          ActionChip(
                            label: Text(tag),
                            onPressed: () => onSuggestion!(tag),
                          ),
                      ],
                    ),
                  ],
                  if (onAction != null || busy) ...[
                    const SizedBox(height: AppTheme.gapXl),
                    SizedBox(
                      height: 40,
                      child: busy
                          ? const Center(
                              child: SizedBox(
                                width: AppTheme.iconXs,
                                height: AppTheme.iconXs,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : FilledButton.tonalIcon(
                              onPressed: onAction,
                              icon: Icon(actionIcon ?? Icons.refresh),
                              label: Text(actionLabel ?? '重试'),
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 给 [StateMessage] 用的三态切换器。
///
/// 三态（加载 / 失败 / 空）之间硬切会让人以为页面刷新了一次；淡入 + 一点上浮
/// 能表达「内容换了」，又不会把视线甩开。
///
/// 用 [stateKey] 而不是比较 widget 类型：三种状态都是同一个 `StateMessage`，
/// 不给不同的 key，`AnimatedSwitcher` 认为没变化，什么都不做。
class StateMessageSwitcher extends StatelessWidget {
  const StateMessageSwitcher({
    super.key,
    required this.stateKey,
    required this.child,
  });

  final Object stateKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppTheme.durMed,
      switchInCurve: AppTheme.curveIn,
      switchOutCurve: AppTheme.curveOut,
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: KeyedSubtree(key: ValueKey<Object>(stateKey), child: child),
    );
  }
}

/// 首屏骨架网格。
///
/// 以前首屏是一个居中转圈：空白 + 一个圆环，看不出这个页面最终长什么样，
/// 也不知道要等多久。骨架给出布局形状，等待显得短，内容到位时也不跳。
///
/// 关键约束：**整块只有一个 ticker**。曾经的写法是每张占位卡各转一个无限
/// 进度圈，一屏 30 张就是 30 个 ticker 同时刷帧，滚动直接掉帧。
class SkeletonGrid extends StatefulWidget {
  const SkeletonGrid({super.key, this.tileCount = 18});

  final int tileCount;

  @override
  State<SkeletonGrid> createState() => _SkeletonGridState();
}

class _SkeletonGridState extends State<SkeletonGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  /// 固定的高度序列。用固定序列而不是随机数：
  /// 重建（例如窗口 resize）时骨架形状不跳，看起来才像「正在加载同一批图」。
  static const List<double> _ratios = <double>[
    0.72,
    1.45,
    1.0,
    0.66,
    1.28,
    0.85,
    1.6,
    0.95,
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth);
        final width = (constraints.maxWidth -
                AppTheme.pagePadding * 2 -
                AppTheme.gapL * (columns - 1)) /
            columns;
        // 往最短的一列里塞下一块，模拟瀑布流的堆叠方式。
        final buckets = List<List<double>>.generate(columns, (_) => <double>[]);
        final heights = List<double>.filled(columns, 0);
        for (var i = 0; i < widget.tileCount; i++) {
          var target = 0;
          for (var c = 1; c < columns; c++) {
            if (heights[c] < heights[target]) target = c;
          }
          final ratio = _ratios[i % _ratios.length];
          buckets[target].add(ratio);
          heights[target] += width * ratio + AppTheme.gapL;
        }
        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppTheme.pagePadding,
            AppTheme.gapM,
            AppTheme.pagePadding,
            AppTheme.pagePadding,
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final color = Color.lerp(
                scheme.surfaceContainerHigh,
                scheme.surfaceContainerHighest,
                AppTheme.curveEmph.transform(_controller.value),
              )!;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0) const SizedBox(width: AppTheme.gapL),
                    SizedBox(
                      width: width,
                      child: Column(
                        children: [
                          for (final ratio in buckets[c])
                            Padding(
                              padding: const EdgeInsets.only(bottom: AppTheme.gapL),
                              child: Container(
                                height: width * ratio,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.cardRadius,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// 与 [PostGrid] 同一套列宽算法，骨架与真内容才不会错列。
  static int _columnsFor(double width) {
    final available = width - AppTheme.pagePadding * 2;
    return (available / 260).floor().clamp(2, 8);
  }
}
