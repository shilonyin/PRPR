import 'package:flutter/material.dart';

/// 应用主题。
///
/// 原 UWP 版直接用系统默认的 `ApplicationTheme`，没有自定义配色；
/// Flutter 侧保留「跟随系统 / 浅色 / 深色」三档（对应原设置页的主题下拉），
/// 但用一套自己定义的种子色，避免默认蓝在大量图片背景上显得脏。
///
/// 尺寸类 token 全部收在这里，页面里不要再写字面量——评审时发现过
/// 3/6/10/14/28 这类碎片值，肉眼分不出但会累积成「哪里怪怪的」。
class AppTheme {
  AppTheme._();

  /// 种子色：偏冷的靛蓝。图片为主的界面里，彩色强调色要足够低调。
  static const Color seed = Color(0xFF5B6ABF);

  // ---------------------------------------------------------------- 间距
  //
  // 六档，全部是 4 的倍数。旧代码里的 3→gapXs、6→gapS、10→gapS 或 gapM、
  // 14→gapL、28→gapXl。

  static const double gapXs = 4;
  static const double gapS = 8;
  static const double gapM = 12;
  static const double gapL = 16;
  static const double gapXl = 24;
  static const double gapXxl = 32;

  // ---------------------------------------------------------------- 圆角
  //
  // 只留两档：12 给卡片 / 输入框 / 按钮 / 图片，8 给 chip / 徽章 / tooltip。
  // 以前是 12 / 10 / 8 三档，差 2px 屏幕上看不出「两种圆角」，只看出「对不齐」。

  static const double cardRadius = 12;

  /// 输入框与按钮圆角。与 [cardRadius] 同值，这样「卡片里的按钮」嵌套自洽。
  static const double inputRadius = 12;

  /// 小控件圆角：chip、徽章、tooltip。
  static const double chipRadius = 8;

  static const double pagePadding = 16;

  // ---------------------------------------------------------------- 图标

  static const double iconXs = 16;
  static const double iconSm = 20;
  static const double iconMd = 24;
  static const double iconXl = 40;

  // ------------------------------------------------------------ 表单标签列

  /// 设置页左标签列宽：4 个中文字（约 56px）+ 余量。
  static const double labelColumnSettings = 112;

  /// 详情页资料区标签列宽：2 个中文字或 3 个英文字符 + 余量。
  static const double labelColumnDetail = 64;

  /// 需要等宽数字的场景（计数、体积、尺寸、MD5）用这个。
  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
  ];

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    final fieldStroke =
        isDark ? const Color(0xFF32323C) : const Color(0xFFDCDCE6);

    // placeholder 用实色而不是 onSurfaceVariant + alpha：0.6 透明度在白底上
    // 只有 2.6:1、深色底 4.15:1，都低于 WCAG AA 的 4.5:1。而 placeholder 是
    // 用户唯一能读到「这个框填什么」的线索，不能省。
    final hintColor =
        isDark ? const Color(0xFF9EA0AA) : const Color(0xFF6B6D75);

    // 按钮统一形状：以前只有 FilledButton 改了圆角，Outlined/Text 还是 M3
    // 默认的胶囊，详情页三个按钮并排时是两种方言。
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(inputRadius),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF121216) : const Color(0xFFF7F7FA),
      visualDensity: VisualDensity.standard,
      // Windows 上 Roboto 没有中文字形，会逐字回退到微软雅黑，中英混排时
      // 字重字宽在同一句里跳变。显式给出回退链，让回退是整段一致的。
      fontFamilyFallback: const [
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'Segoe UI',
        'Noto Sans SC',
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF1A1A20) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : const Color(0xFF1A1A20),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: buttonShape,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: buttonShape,
        ),
      ),
      // 桌面端必须有明确可抓的滚动条：Windows 默认那条极细且颜色浅，
      // 深色主题里几乎看不见。
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(4),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          final hovered = states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged);
          return scheme.onSurfaceVariant.withValues(
            alpha: hovered ? 0.7 : 0.35,
          );
        }),
      ),
      // 最近搜索的 InputChip、详情页的 ChoiceChip 以前全走 M3 默认，
      // 和卡片语言脱节。
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chipRadius),
        ),
        side: BorderSide(color: fieldStroke),
        labelStyle: const TextStyle(fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),
      // rail 是 extended 模式，默认的胶囊指示器只包住图标不包文字，
      // 选中态看起来是「半截」。
      navigationRailTheme: NavigationRailThemeData(
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
      ),
      // 自动换壁纸的间隔滑块 divisions 上千，默认拇指 20 在鼠标下不好拖。
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),
      // 默认 tooltip 是小字浅底，深色界面里像异物。
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A33),
          borderRadius: BorderRadius.circular(chipRadius),
        ),
        textStyle: const TextStyle(fontSize: 12, color: Colors.white),
      ),
      // 所有文本输入的外观都收在这里：页面里只描述「标签 / 提示 / 说明 / 错误」，
      // 不再各写各的边框和填充。聚焦态用主题色描边 + 一层极淡的底色，替原版刺眼的
      // 默认下划线；错误态只用 errorText 呈现，颜色跟主题一致。
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: isDark ? const Color(0xFF1E1E26) : Colors.white,
        focusColor: scheme.primary.withValues(alpha: isDark ? 0.06 : 0.04),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: fieldStroke, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: fieldStroke, width: 1),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(
            color: fieldStroke.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: scheme.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(
            color: scheme.error.withValues(alpha: 0.7),
            width: 1,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: scheme.error, width: 1.8),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        floatingLabelStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: TextStyle(color: hintColor),
        helperStyle: TextStyle(
          fontSize: 12,
          height: 1.35,
          color: scheme.onSurfaceVariant,
        ),
        helperMaxLines: 3,
        errorStyle: TextStyle(
          fontSize: 12,
          height: 1.35,
          fontWeight: FontWeight.w500,
          color: scheme.error,
        ),
        errorMaxLines: 3,
        iconColor: scheme.onSurfaceVariant,
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        prefixIconConstraints:
            const BoxConstraints(minWidth: 44, minHeight: 44),
        suffixIconConstraints:
            const BoxConstraints(minWidth: 40, minHeight: 40),
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: isDark ? const Color(0xFF26262F) : const Color(0xFFE8E8EF),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(inputRadius),
        ),
      ),
    );
  }

  /// 设置项之间的分组标题样式。
  ///
  /// 颜色用 onSurface 而不是 primary：一屏有 8 个段标题时，8 行紫字等于
  /// 没有一行在强调什么，深色下 primary 是浅紫，跳跃感还压过正文。
  /// 需要品牌色时用 [sectionAccent]，它只占 3x16 一小条。
  static TextStyle? sectionTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
            letterSpacing: 0.5,
          );

  /// 段标题左侧的品牌色竖条。配合 [sectionTitle] 使用。
  static Widget sectionAccent(BuildContext context) => Container(
        width: 3,
        height: 16,
        margin: const EdgeInsets.only(right: gapS),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  /// 说明性小字。
  static TextStyle? hint(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          );
}
