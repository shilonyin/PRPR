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
/// 刻意不做悬停放大：列宽 260、缝 16 都是硬约束，放大只能是 Transform，
/// 不参与布局，放大后会盖住邻居。
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(AppTheme.cardRadius);
    final ratio = widget.post.preferredRatio;
    // 极端长图会把瀑布流拉得很难看，限一下取值范围。
    // 以前是 0.25~4.0，1:4 的竖图会变成一张一千多像素高的单卡，
    // 一屏只放得下一张，翻页体验直接崩掉；收到 0.5~2.0。
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
                      ? scheme.primary
                      : _hovered
                          ? scheme.primary.withValues(alpha: 0.55)
                          : Colors.transparent,
                  width: _focused ? 2 : 1.5,
                ),
                boxShadow: [
                  if (_focused)
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.35),
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
              child: Card(
                clipBehavior: Clip.antiAlias,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: radius),
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
                          // 飞行途中的外观由 hero_flight 统一决定，详情页用的是
                          // 同一个函数——两处各写一遍正是「起终点不一致」的来源。
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
                          // Hero 占位的签名是 (context, heroSize, child)，
                          // 只接 context 会类型不匹配。飞行时源位置留一块纯色，
                          // 避免原地还留着一张图、看起来像「复制了一份」。
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
                      // 悬停 / 聚焦才出现的两行信息。常驻会盖住图，
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

  /// 底部渐变 + 尺寸、右上角分级徽章。
  Widget _overlay(BuildContext context) {
    final post = widget.post;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 56,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0),
                  Colors.black.withValues(alpha: 0.62),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: AppTheme.gapS,
          right: AppTheme.gapS,
          bottom: AppTheme.gapS,
          child: Text(
            '${post.width} × ${post.height}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              fontFeatures: AppTheme.tabularFigures,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Positioned(
          top: AppTheme.gapS,
          right: AppTheme.gapS,
          child: _ratingBadge(),
        ),
      ],
    );
  }

  Widget _ratingBadge() {
    final rating = widget.post.rating.toLowerCase();
    final (label, color) = switch (rating) {
      's' => ('S', const Color(0xFF2E7D32)),
      'q' => ('Q', const Color(0xFFEF6C00)),
      'e' => ('E', const Color(0xFFC62828)),
      _ => ('?', const Color(0xFF546E7A)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppTheme.chipRadius),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.2,
        ),
      ),
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
