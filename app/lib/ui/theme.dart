import 'package:flutter/material.dart';

/// 应用主题。
///
/// 一套自建 token：颜色走 AppPalette / AppColor，字号走 AppType，
/// 尺寸与动效走 AppTheme。页面里**不允许**再出现颜色字面量、字号字面量——
/// 评审时发现过 13/11/10 三种正文字号和 3/6/10/14/28 四种碎片间距，
/// 单看每处都合理，连起来就没有节奏。
///
/// 设计稿见 automation/designs/prpr-ui.figcraft，
/// 落地说明见 docs/ui-redesign.md。
class AppTheme {
  AppTheme._();

  /// 种子色。M3 的 ColorScheme 需要一个种子，但强调色不走它——
  /// 实际强调色是 AppColor.of(context).gold，由手写 ColorScheme 直接指定。
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

  /// 页面左右留白。32 而不是 16：新外壳没有 AppBar 的内边距兜底，
  /// 瀑布流与顶栏必须共用同一条左基线。
  static const double pagePadding = 32;

  // ---------------------------------------------------------------- 圆角
  //
  // 四级，按「内容 / 控件 / 容器 / 胶囊」分层：
  //   4    图片、标签 chip
  //   8    按钮、输入框、下拉框、分段、导航当前项 —— 凡是「手能点」的都在这档
  //   12   卡片、浮层、Snackbar —— 凡是「装东西的」都在这档
  //   胶囊  只有开关和头像，r = 高/2
  //
  // 8 这个值的依据：Fluent 2 的 OverlayCornerRadius、Tailwind 的 rounded-lg
  // 都是 8，且满足同心圆角（外层 12 = 内层 8 + 内距 4）。早期版本的按钮沿用
  // 12，结果 38px 高的按钮圆角比它所在的卡片还大，读起来像「药丸」，不像控件。

  static const double cardRadius = 12;

  /// 图片圆角。瓦片缩略图、列表缩略图、hero 图共用。
  /// 图是内容，圆角越小它越完整地铺满自己的格子——12 会在四角啃掉插画。
  static const double imageRadius = 4;

  /// 按钮圆角。四个按钮主题（Filled / Outlined / Text / Elevated）共用。
  static const double buttonRadius = 8;

  /// 输入框、下拉框、分段控件的圆角。与 buttonRadius 同值，
  /// 这样一行里「左边输入、右边按钮」时边缘弧度一致。
  static const double inputRadius = 8;

  /// 标签 chip 的圆角。比 inputRadius 再小一档：chip 高度只有 26，
  /// 用 8 会接近半圆；4 保留「标签」的方形感，也不会和按钮混为一谈。
  static const double chipRadius = 4;

  /// 导航轨当前项的底。40 见方的块用 10 会接近圆形，8 保持方块的识别度。
  static const double railItemRadius = 8;

  // ---------------------------------------------------------------- 尺寸

  /// 左侧导航轨宽度。单值，没有展开/折叠两态——图标轨只承担「去哪」，
  /// 文字标签是额外的 180px 常驻成本。
  static const double railWidth = 56;

  /// 导航图标按钮的命中区域。
  static const double railItemSize = 40;

  /// 搜索页顶栏高度（要容纳语法提示行）。
  static const double topbarHeightSearch = 79;

  /// 其他页顶栏高度。
  static const double topbarHeight = 56;

  /// 瀑布流列间距。图片圆角收到 4 之后缝可以更紧。
  static const double gridGap = 12;

  /// 瀑布流目标列宽。1440 宽减去导轨 56 与左右留白 64，剩 1320；
  /// 4 列 × 325 + 3 × 12 = 1336，取整后正好 4 列。
  static const double columnWidth = 325;

  /// 详情页右侧信息栏固定宽度。固定而不是按比例：长标题换行时
  /// 图片区域不能跟着抖。
  static const double sideWidth = 440;

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

  /// 设置页左侧编号导航宽度。
  static const double settingsNavWidth = 176;

  /// 需要等宽数字的场景（计数、体积、尺寸、MD5）用这个。
  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
  ];

  // ---------------------------------------------------------------- 字体

  /// 正文与 UI 字体。
  static const String fontUi = 'Microsoft YaHei UI';

  /// 等宽字体族名。Cascadia Mono 是 Win10 1809+ 自带。
  static const String fontMono = 'Cascadia Mono';

  /// 等宽字体回退链，缺 Cascadia Mono 时落到 Consolas。
  static const List<String> fontMonoFallback = ['Cascadia Mono', 'Consolas'];

  /// 衬线字体，只在 About 页艺术字用一次。
  static const String fontSerif = 'SimSun';

  // ---------------------------------------------------------------- 动效
  //
  // 桌面鼠标的操作节奏比触屏快：超过 240ms 的 micro-interaction 会被读成
  // 「迟钝」，而 300ms 的页面转场又刚好让人盯着等。所以整套值压在
  // 90~260ms 这个区间里，只有「长任务进度」例外。

  /// 按下 / 抬起。
  static const Duration durMicro = Duration(milliseconds: 90);

  /// 图标、遮罩、chip、小范围淡入。
  static const Duration durFast = Duration(milliseconds: 140);

  /// tab 内容、标题、透明度变化。
  static const Duration durBase = Duration(milliseconds: 180);

  /// 图片渐显、状态切换、SnackBar。
  static const Duration durMed = Duration(milliseconds: 220);

  /// 页面转场、详情页换画质、列表新行入场。
  static const Duration durSlow = Duration(milliseconds: 260);

  /// 长任务的分段进度爬行。
  static const Duration durTask = Duration(milliseconds: 400);

  /// 出现用这个：第一帧就基本可见，桌面用户切完就开始读内容了。
  static const Curve curveIn = Curves.easeOutCubic;

  /// 消失用这个。比 curveIn 慢一点收尾，避免「啪」地没了。
  static const Curve curveOut = Curves.easeInCubic;

  /// 整体状态变幻（主题切换、侧栏宽度）。
  static const Curve curveEmph = Curves.easeInOutCubic;

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final c = isDark ? AppPalette.dark : AppPalette.light;
    final scheme = _scheme(c, brightness);

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(buttonRadius),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      visualDensity: VisualDensity.standard,
      // Windows 上 Roboto 没有中文字形，会逐字回退到微软雅黑，中英混排时
      // 字重字宽在同一句里跳变。显式给出回退链，让回退是整段一致的。
      fontFamily: fontUi,
      fontFamilyFallback: const [
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'Segoe UI',
        'Noto Sans SC',
      ],
      textTheme: _textTheme(c),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppType.section.copyWith(color: c.ink),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.gold,
          foregroundColor: c.onGold,
          disabledBackgroundColor: c.gold.withValues(alpha: 0.24),
          // 按钮在页面里被 SizedBox 定了高度（38–42）。body 的 height 1.6
          // 会把 13px 的字撑到 20.8 行高，再叠上 14 的上下内边距，正文就被
          // 挤出按钮框、只露下半截。按钮内文字统一压到 1.2、上下留 8：
          // 42 - 16 = 26 ≥ 13×1.2，任何字号都不会再被裁。
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          textStyle:
              AppType.body.copyWith(fontWeight: FontWeight.w600, height: 1.2),
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          side: BorderSide(color: c.lineStrong),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: AppType.body.copyWith(height: 1.2),
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.inkDim,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          textStyle: AppType.body.copyWith(height: 1.2),
          shape: buttonShape,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.surface,
          foregroundColor: c.ink,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          textStyle: AppType.body.copyWith(height: 1.2),
          shape: buttonShape,
        ),
      ),
      // 桌面端必须有明确可抓的滚动条：Windows 默认那条极细且颜色浅，
      // 深色主题里几乎看不见。
      scrollbarTheme: ScrollbarThemeData(
        // 常态 6、悬停/拖动 10：8 在 4K 上太细，10 常驻又太抢眼。
        thickness: WidgetStateProperty.resolveWith((states) {
          final active = states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged);
          return active ? 10 : 6;
        }),
        radius: const Radius.circular(4),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          final hovered = states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged);
          return c.inkDim.withValues(alpha: hovered ? 0.7 : 0.35);
        }),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chipRadius),
        ),
        side: BorderSide(color: c.line),
        backgroundColor: Colors.transparent,
        selectedColor: c.gold.withValues(alpha: 0.14),
        labelStyle: AppType.chip.copyWith(color: c.inkDim),
        secondaryLabelStyle: AppType.chip.copyWith(color: c.gold),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: c.gold,
        inactiveTrackColor: c.line,
        thumbColor: c.gold,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(inputRadius),
        ),
        textStyle: AppType.caption.copyWith(color: c.ink),
      ),
      // 所有文本输入的外观都收在这里：页面里只描述「标签 / 提示 / 说明 / 错误」，
      // 不再各写各的边框和填充。
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: isDark ? c.panel : Colors.white,
        focusColor: c.gold.withValues(alpha: isDark ? 0.06 : 0.04),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: c.lineStrong, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: c.lineStrong, width: 1),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: c.lineStrong.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: c.gold, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: c.danger.withValues(alpha: 0.7)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: c.danger, width: 1.4),
        ),
        labelStyle: AppType.body.copyWith(color: c.inkDim),
        floatingLabelStyle:
            AppType.caption.copyWith(color: c.gold, fontWeight: FontWeight.w600),
        // placeholder 用实色而不是 onSurfaceVariant + alpha：
        // 0.6 透明度在白底上只有 2.6:1、深色底 4.15:1，都低于 WCAG AA 的 4.5:1。
        hintStyle: AppType.body.copyWith(color: c.inkFaint),
        helperStyle: AppType.caption.copyWith(color: c.inkDim),
        helperMaxLines: 3,
        errorStyle: AppType.caption
            .copyWith(fontWeight: FontWeight.w500, color: c.danger),
        errorMaxLines: 3,
        iconColor: c.inkDim,
        prefixIconColor: c.inkFaint,
        suffixIconColor: c.inkDim,
        prefixIconConstraints:
            const BoxConstraints(minWidth: 44, minHeight: 44),
        suffixIconConstraints:
            const BoxConstraints(minWidth: 40, minHeight: 40),
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: c.line,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        textColor: c.ink,
        iconColor: c.inkDim,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.surface,
        contentTextStyle: AppType.body.copyWith(color: c.ink),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          side: BorderSide(color: c.line),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.gold,
        linearTrackColor: c.line,
        circularTrackColor: c.line,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? c.bg : c.inkFaint),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? c.gold : c.line),
        trackOutlineColor:
            WidgetStateProperty.resolveWith((states) => Colors.transparent),
      ),
      focusColor: c.gold.withValues(alpha: 0.24),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
  }

  static ColorScheme _scheme(AppPalette c, Brightness b) => ColorScheme(
        brightness: b,
        primary: c.gold,
        onPrimary: c.onGold,
        primaryContainer: c.gold.withValues(alpha: 0.14),
        onPrimaryContainer: c.gold,
        secondary: c.inkDim,
        onSecondary: c.bg,
        secondaryContainer: c.surface,
        onSecondaryContainer: c.ink,
        tertiary: c.safe,
        onTertiary: c.bg,
        tertiaryContainer: c.surface,
        onTertiaryContainer: c.safe,
        error: c.danger,
        onError: c.bg,
        errorContainer: c.danger.withValues(alpha: 0.14),
        onErrorContainer: c.danger,
        surface: c.bg,
        onSurface: c.ink,
        surfaceDim: c.bg,
        surfaceBright: c.surface,
        surfaceContainerLowest: c.bg,
        surfaceContainerLow: c.rail,
        surfaceContainer: c.panel,
        surfaceContainerHigh: c.surface,
        surfaceContainerHighest: c.surface,
        onSurfaceVariant: c.inkDim,
        outline: c.lineStrong,
        outlineVariant: c.line,
        inverseSurface: c.ink,
        onInverseSurface: c.bg,
        inversePrimary: c.gold,
        shadow: const Color(0xFF000000),
        scrim: const Color(0xFF000000),
      );

  /// 把 Material 的 textTheme 映射到 AppType，页面拿到的默认字号就是对的。
  static TextTheme _textTheme(AppPalette c) => TextTheme(
        displayLarge: AppType.display.copyWith(color: c.ink),
        displayMedium: AppType.display.copyWith(color: c.ink),
        displaySmall: AppType.title.copyWith(color: c.ink),
        headlineLarge: AppType.title.copyWith(color: c.ink),
        headlineMedium: AppType.section.copyWith(color: c.ink),
        headlineSmall: AppType.section.copyWith(color: c.ink),
        titleLarge: AppType.section.copyWith(color: c.ink),
        titleMedium:
            AppType.body.copyWith(color: c.ink, fontWeight: FontWeight.w600),
        titleSmall:
            AppType.body.copyWith(color: c.ink, fontWeight: FontWeight.w600),
        bodyLarge: AppType.body.copyWith(color: c.ink),
        bodyMedium: AppType.body.copyWith(color: c.ink),
        bodySmall: AppType.caption.copyWith(color: c.inkDim),
        labelLarge:
            AppType.body.copyWith(color: c.ink, fontWeight: FontWeight.w500),
        labelMedium: AppType.monoData.copyWith(color: c.inkDim),
        labelSmall: AppType.kicker.copyWith(color: c.inkFaint),
      );

  /// 说明性小字。
  static TextStyle hint(BuildContext context) => AppType.caption
      .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
}

/// 语义色板。
///
/// 页面的第一反应是写 Color(0xFF...)，因为「就一个颜色」。一屏三十个这样的
/// 决定之后，同一个灰会出现四个值。所有颜色必须从这里取。
class AppPalette {
  const AppPalette({
    required this.bg,
    required this.rail,
    required this.panel,
    required this.surface,
    required this.line,
    required this.lineStrong,
    required this.ink,
    required this.inkDim,
    required this.inkFaint,
    required this.gold,
    required this.goldText,
    required this.safe,
    required this.danger,
    required this.canvas,
    required this.onGold,
  });

  /// scaffold 底。
  final Color bg;

  /// 左导航轨、详情右栏。
  final Color rail;

  /// 输入框、下拉框底。
  final Color panel;

  /// 浮层、当前项底、次按钮 hover。
  final Color surface;

  /// 常规描边、分隔线。
  final Color line;

  /// 控件描边。
  final Color lineStrong;

  /// 主文字。
  final Color ink;

  /// 次文字。
  final Color inkDim;

  /// 说明、非当前编号。
  final Color inkFaint;

  /// 强调色。只出现在主按钮、当前项、计数器、光标。
  final Color gold;

  /// 需要金色文字时的版本。深色底上用 gold，浅色底上用这个压深。
  final Color goldText;

  /// rating:s 圆点。
  final Color safe;

  /// 危险动作文字与描边。
  final Color danger;

  /// 沉浸式看图的画布底。比 bg 再暗一档，图片才是页面上唯一的亮块。
  final Color canvas;

  /// 金色实底上的字。金色明度高到 0.65 左右，压深字才够对比。
  final Color onGold;

  /// 深色：标本室。四层底全部低明度，靠 1px 描边而不是投影分隔。
  static const AppPalette dark = AppPalette(
    bg: Color(0xFF0B0C0E),
    rail: Color(0xFF0E1014),
    panel: Color(0xFF111318),
    surface: Color(0xFF191C22),
    line: Color(0xFF24272F),
    lineStrong: Color(0xFF333845),
    ink: Color(0xFFECEFF3),
    inkDim: Color(0xFF9AA1AE),
    inkFaint: Color(0xFF666D7C),
    gold: Color(0xFFD8A657),
    goldText: Color(0xFFD8A657),
    safe: Color(0xFF6FBF8B),
    danger: Color(0xFFE06C75),
    canvas: Color(0xFF08090B),
    onGold: Color(0xFF14110A),
  );

  /// 浅色：同一套语义反相。金色在浅底上只有 2.6:1，
  /// 所以只用于描边与图形，需要金色**文字**时用 goldText。
  static const AppPalette light = AppPalette(
    bg: Color(0xFFF7F7FA),
    rail: Color(0xFFFFFFFF),
    panel: Color(0xFFFFFFFF),
    surface: Color(0xFFEFF0F4),
    line: Color(0xFFE4E5EC),
    lineStrong: Color(0xFFD2D4DE),
    ink: Color(0xFF1A1C22),
    inkDim: Color(0xFF5A6070),
    inkFaint: Color(0xFF858B99),
    gold: Color(0xFFD8A657),
    goldText: Color(0xFF8A6414),
    safe: Color(0xFF2E8B57),
    danger: Color(0xFFC0392B),
    canvas: Color(0xFFEDEEF3),
    onGold: Color(0xFF241B08),
  );
}

/// 语义色。AppColor.of(context).gold —— 跟随当前亮/暗档。
class AppColor {
  AppColor._();

  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppPalette.dark
          : AppPalette.light;
}

/// 字阶。
///
/// 八档，每档都写死字号 / 行高 / 字重 / 字体族。页面只从这些里挑，
/// 不再出现 fontSize: 13。
class AppType {
  AppType._();

  /// About 页题图。全应用唯一使用衬线的地方。
  static const TextStyle display = TextStyle(
    fontFamily: AppTheme.fontSerif,
    fontSize: 27,
    height: 1.3,
    fontWeight: FontWeight.w400,
    letterSpacing: 2,
  );

  /// 详情页帖子名、页面主标题。
  static const TextStyle title = TextStyle(
    fontFamily: AppTheme.fontMono,
    fontFamilyFallback: AppTheme.fontMonoFallback,
    fontSize: 19,
    height: 1.35,
    fontWeight: FontWeight.w500,
    fontFeatures: AppTheme.tabularFigures,
  );

  /// 顶栏页面名、设置组名。
  static const TextStyle section = TextStyle(
    fontSize: 17,
    height: 1.4,
    fontWeight: FontWeight.w600,
  );

  /// 正文、表单标签。
  static const TextStyle body = TextStyle(
    fontSize: 13,
    height: 1.6,
    fontWeight: FontWeight.w400,
  );

  /// 辅助说明。
  static const TextStyle caption = TextStyle(
    fontSize: 11,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );

  /// 计数、尺寸、体积、MD5、来源。
  static const TextStyle monoData = TextStyle(
    fontFamily: AppTheme.fontMono,
    fontFamilyFallback: AppTheme.fontMonoFallback,
    fontSize: 11,
    height: 1.4,
    fontWeight: FontWeight.w400,
    fontFeatures: AppTheme.tabularFigures,
  );

  /// 小标题（PALETTE / 危险操作）。字号小于 caption，靠字距立起来。
  static const TextStyle kicker = TextStyle(
    fontFamily: AppTheme.fontMono,
    fontFamilyFallback: AppTheme.fontMonoFallback,
    fontSize: 9.5,
    height: 1.2,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.5,
    fontFeatures: AppTheme.tabularFigures,
  );

  /// 标签 chip 内文字。
  static const TextStyle chip = TextStyle(
    fontFamily: AppTheme.fontMono,
    fontFamilyFallback: AppTheme.fontMonoFallback,
    fontSize: 10.5,
    height: 1.4,
    fontWeight: FontWeight.w400,
    fontFeatures: AppTheme.tabularFigures,
  );
}
