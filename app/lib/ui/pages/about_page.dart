import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/app_topbar.dart';
import '../widgets/section_header.dart';

/// 关于页。对应原 UWP `AboutPage`。
///
/// 原版是静态文本；这里加上「打开数据目录」和「查看开源许可」两个实际有用的入口 ——
/// 换壁纸下载的图片存在数据目录里，用户迟早会想找到它们。
///
/// 版式：56px 顶栏（返回 + 页名 + 版本号）+ 单栏正文，正文限宽 720。
/// 不铺满整宽是因为这一页几乎全是句子，行宽超过 80 个汉字之后
/// 眼睛回行会丢行，反而不好读。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String version = '3.0.0';

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    final state = context.watch<AppState>();
    final settings = context.watch<AppSettings>();

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          AppTopBar(
            child: Row(
              children: [
                const AppBackButton(),
                const SizedBox(width: AppTheme.gapS),
                Text(
                  '关于',
                  style: AppType.section.copyWith(color: c.ink),
                ),
                const Spacer(),
                const AppTopBarLabel('v$version', emphasize: true),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(40, 36, 40, 48),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _header(c),
                        const SizedBox(height: AppTheme.gapXl),
                        Text(
                          '一个看图 + 换壁纸的小工具。原版是 Windows 10 的 UWP 应用，'
                          '在微软下架 UWP 应用商店后停止维护；这一版用 Flutter 重写，'
                          '目标是同样的功能能在当前的 Windows 上继续用。',
                          style: AppType.body.copyWith(
                            color: c.inkDim,
                            height: 1.75,
                          ),
                        ),
                        const SizedBox(height: AppTheme.gapXl),
                        _rule(c),
                        const SizedBox(height: AppTheme.gapXl),
                        const AppSectionHeader('致谢'),
                        const SizedBox(height: AppTheme.gapM),
                        ..._credits(c),
                        const SizedBox(height: AppTheme.gapXl),
                        _rule(c),
                        const SizedBox(height: AppTheme.gapXl),
                        const AppSectionHeader('运行时信息'),
                        const SizedBox(height: AppTheme.gapS),
                        _kv(c, '站点', settings.host),
                        _kv(
                          c,
                          '登录状态',
                          settings.isLoggedIn
                              ? '已登录（${settings.userName}）'
                              : '未登录',
                        ),
                        _kv(c, '历史记录', '${state.history.length} 条'),
                        const SizedBox(height: AppTheme.gapXl),
                        _rule(c),
                        const SizedBox(height: AppTheme.gapM),
                        _licenseRow(context, c),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(AppPalette c) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
              border: Border.all(color: c.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/app_logo.png',
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (context, _, _) => Icon(
                Icons.image_outlined,
                size: 22,
                color: c.inkFaint,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.gapL),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'PRPR',
                style: AppType.display.copyWith(color: c.ink),
              ),
              const SizedBox(height: 4),
              Text(
                'MoeCatnip · FLUTTER 重写版',
                style: AppType.kicker.copyWith(color: c.inkFaint),
              ),
            ],
          ),
        ],
      );

  Widget _rule(AppPalette c) => Container(height: 1, color: c.line);

  List<Widget> _credits(AppPalette c) => const [
        _Credit('laplamgor', '原 PRPR 项目作者（2017–2020）。功能设计、交互流程与裁剪算法都来自他的 UWP 原版。'),
        _Credit('nagadomi', 'lbpcascade_animeface 级联模型（MIT，2011），人脸检测靠它。'),
        _Credit('OpenCV / opencv_dart', '图像处理与级联推理。'),
        _Credit('yande.re / konchan', '被支持的图站，请遵守各站的使用条款。'),
        _Credit('Flutter / Dart / pub', '框架与全部第三方依赖。'),
      ];

  Widget _kv(AppPalette c, String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: AppTheme.labelColumnDetail,
              child: Text(
                key,
                style: AppType.caption.copyWith(color: c.inkFaint),
              ),
            ),
            const SizedBox(width: AppTheme.gapL),
            Expanded(
              child: SelectableText(
                value,
                style: AppType.monoData.copyWith(color: c.ink),
              ),
            ),
          ],
        ),
      );

  Widget _licenseRow(BuildContext context, AppPalette c) => InkWell(
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        onTap: () => showLicensePage(
          context: context,
          applicationName: 'PRPR',
          applicationVersion: version,
          applicationIcon: Image.asset(
            'assets/app_logo.png',
            width: 48,
            height: 48,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTheme.gapM),
          child: Row(
            children: [
              Icon(Icons.description_outlined, size: AppTheme.iconSm, color: c.inkDim),
              const SizedBox(width: AppTheme.gapM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '开源许可',
                      style: AppType.body.copyWith(color: c.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '查看所有第三方依赖的许可证',
                      style: AppType.caption.copyWith(color: c.inkFaint),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: AppTheme.iconSm, color: c.inkFaint),
            ],
          ),
        ),
      );
}

class _Credit extends StatelessWidget {
  const _Credit(this.name, this.text);

  final String name;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.gapM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 148,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                name,
                style: AppType.monoData.copyWith(color: c.goldText),
              ),
            ),
          ),
          const SizedBox(width: AppTheme.gapL),
          Expanded(
            child: Text(
              text,
              style: AppType.body.copyWith(color: c.inkDim, height: 1.7),
            ),
          ),
        ],
      ),
    );
  }
}
