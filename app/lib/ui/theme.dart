import 'package:flutter/material.dart';

/// 应用主题。
///
/// 原 UWP 版直接用系统默认的 `ApplicationTheme`，没有自定义配色；
/// Flutter 侧保留「跟随系统 / 浅色 / 深色」三档（对应原设置页的主题下拉），
/// 但用一套自己定义的种子色，避免默认蓝在大量图片背景上显得脏。
class AppTheme {
  AppTheme._();

  /// 种子色：偏冷的靛蓝。图片为主的界面里，彩色强调色要足够低调。
  static const Color seed = Color(0xFF5B6ABF);

  /// 卡片圆角。原版瀑布流卡片是直角，这里统一改成 12，观感更现代。
  static const double cardRadius = 12;

  static const double pagePadding = 16;

  /// 输入框圆角。比卡片略小，密集表单里不显笨重。
  static const double inputRadius = 10;

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

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF121216) : const Color(0xFFF7F7FA),
      visualDensity: VisualDensity.standard,
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
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
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
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
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  /// 设置项之间的分组标题样式。
  static TextStyle? sectionTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 0.5,
          );

  /// 说明性小字。
  static TextStyle? hint(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          );
}
