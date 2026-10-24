import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/post.dart';
import '../theme.dart';
import 'hero_flight.dart';

/// 瀑布流里的单张缩略图。
///
/// 高度由 [Post.preferredRatio] 决定 —— 原版 UWP 的 `VariableSizedWrapGrid`
/// 也是按原始宽高比排的，这样瀑布流才不会出现拉伸变形。
///
/// 交互有三态，缺一不可：
/// - **悬停**：描边收紧 + 底部浮出尺寸与分级。桌面端没有触摸按压，
///   鼠标移上去毫无变化，用户会怀疑卡片能不能点。
/// - **按下**：缩到 0.985。按 90ms 比松开 140ms 快，手感才「跟手」。
/// - **键盘焦点**：2px 实色描边 + 外发光，必须与悬停有明显区别，
///   否则键盘用户不知道自己停在哪。
///
/// 刻意不做悬停放大：列宽与缝都是硬约束，放大只能是 Transform，
/// 不参与布局，放大后会盖住邻居。
///
/// **分级标记从右上角的 S/Q/E 徽章改成左上角的 6px 圆点**：
/// 一屏三十张图就有三十个色块徽章，它们在同一高度排成一条虚线，
/// 每张图都被啃掉一个角；而「这张是 safe / questionable / explicit」
/// 是一个只需要 3 个离散值的属性，一个点足够，悬停时再补全称。
class PostTile extends StatefulWidget {
  const PostTile({
    super.key,
    required this.post,
    this.onTap,
    this.heroPrefix = '',
  });

  final Post post;
  final VoidCallback? onTap;

  /// Hero 动画标识前缀，避免不同列表里的同一张图串台。
  final String heroPrefix;

  @override
  State<PostTile> createState() => _PostTileState();
}

class _PostTileState extends State<PostTile> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  void _activate() => widget.onTap?.call();

  /// 键盘移动焦点时把当前瓦片滚进视口。
  ///
  /// 不做这件事的话，方向键能穿过屏幕外几十张不可见的卡片，焦点在哪儿完全
  /// 看不到，键盘导航等于没用。
  void _ensureVisible() {
    if (!mounted) return;
    Scrollable.ensureVisible(
      context,
      duration: AppTheme.durBase,
      curve: AppTheme.curveIn,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    // 瓦片是「内容」不是「容器」：圆角走 imageRadius(4)。
    final radius = BorderRadius.circular(AppTheme.imageRadius);
    final ratio = widget.post.preferredRatio;
    // 极端长图会把瀑布流拉得很难看，限一下取值范围。
    final safeRatio = ratio.clamp(0.5, 2.0);
    final preview = widget.post.urlFor(PostImageVersion.preview);
    final showOverlay = _hovered || _focused;

    return RepaintBoundary(
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) {
          if (_hovered == value) return;
          setState(() => _hovered = value);
        },
        onShowFocusHighlight: (value) {
          if (_focused == value) return;
          setState(() => _focused = value);
          if (value) _ensureVisible();
        },
        // Enter 与 Space 都激活，和按钮的默认行为一致。
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: _activate,
          child: AnimatedScale(
            scale: _pressed ? 0.985 : 1,
            duration: _pressed ? AppTheme.durMicro : AppTheme.durFast,
            curve: AppTheme.curveIn,
            child: AnimatedContainer(
              duration: AppTheme.durFast,
              curve: AppTheme.curveIn,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: _focused
                      ? c.gold
                      : _hovered
                          ? c.gold.withValues(alpha: 0.5)
                          : Colors.transparent,
                  width: _focused ? 2 : 1.5,
                ),
                boxShadow: [
                  if (_focused)
                    BoxShadow(
                      color: c.gold.withValues(alpha: 0.3),
                      blurRadius: 0,
                      spreadRadius: 3,
                    )
                  else if (_hovered)
                    const BoxShadow(
                      color: Color(0x47000000),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                ],
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: AspectRatio(
                  aspectRatio: safeRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (preview.isEmpty)
                        _placeholder(context)
                      else
                        Hero(
                          tag: '${widget.heroPrefix}${widget.post.id}',
                          flightShuttleBuilder: (
                            flightContext,
                            animation,
                            direction,
                            fromContext,
                            toContext,
                          ) =>
                              heroFlightShuttle(
                            flightContext,
                            animation,
                            direction,
                            fromContext,
                            toContext,
                            preview,
                          ),
                          placeholderBuilder: (context, _, _) =>
                              SizedBox.expand(child: _placeholder(context)),
                          child: CachedNetworkImage(
                            imageUrl: preview,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            fadeInDuration: AppTheme.durMed,
                            fadeInCurve: AppTheme.curveIn,
                            placeholder: (context, _) => _placeholder(context),
                            errorWidget: (context, _, _) => _broken(context),
                          ),
                        ),
                      // 分级点：常驻，6px，左上角，距边 8。
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _RatingDot(rating: widget.post.rating),
                      ),
                      // 悬停 / 聚焦才出现的底部信息。常驻会盖住图，
                      // 而缩略图本身才是用户找图的主要依据。
                      IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: showOverlay ? 1 : 0,
                          duration: AppTheme.durFast,
                          curve: AppTheme.curveIn,
                          child: _overlay(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 底部渐变 + 尺寸。
  Widget _overlay(BuildContext context) {
    final post = widget.post;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0),
                  Colors.black.withValues(alpha: 0.66),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: AppTheme.gapS,
          right: AppTheme.gapS,
          bottom: 6,
          child: Row(
            children: [
              Text(
                '${post.width} × ${post.height}',
                style: AppType.monoData.copyWith(color: Colors.white),
              ),
              const Spacer(),
              Text(
                _ratingName(post.rating),
                style: AppType.monoData.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 图片没到位时的占位。
  ///
  /// 以前这里放了一个无限转圈的进度环 —— 一屏三十张卡就是三十个 ticker
  /// 同时请求下一帧，滚动直接掉帧。纯色块在这个尺寸下信息量一样，成本是零。
  Widget _placeholder(BuildContext context) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      );

  Widget _broken(BuildContext context) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );

}

/// 分级代号 → 全称。
///
/// 放在顶层而不是 PostTile 的静态方法里：[_RatingDot] 是另一个类，
/// 它也要用这份映射（tooltip 里写全称），静态私有方法跨类访问不了。
String _ratingName(String rating) => switch (rating.toLowerCase()) {
      's' => 'safe',
      'q' => 'questionable',
      'e' => 'explicit',
      _ => 'unknown',
    };

/// 分级圆点。6px，带 1px 深色描边，保证压在亮图上也能看见。
class _RatingDot extends StatelessWidget {
  const _RatingDot({required this.rating});

  final String rating;

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    final color = switch (rating.toLowerCase()) {
      's' => c.safe,
      'q' => c.gold,
      'e' => c.danger,
      _ => c.inkFaint,
    };
    return Tooltip(
      message: _ratingName(rating),
      waitDuration: const Duration(milliseconds: 500),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          // 描边必须固定偏深：圆点会压在纯白图上，浅色主题下取 bg 就消失了。
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.55),
            width: 1,
          ),
        ),
      ),
    );
  }
}
