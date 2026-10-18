import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings.dart';
import '../app_state.dart';
import '../theme.dart';

/// 关于页。对应原 UWP `AboutPage`。
///
/// 原版是静态文本；这里加上「打开数据目录」和「查看开源许可」两个实际有用的入口 ——
/// 换壁纸下载的图片存在数据目录里，用户迟早会想找到它们。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String version = '3.0.0';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = context.watch<AppSettings>();
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.pagePadding),
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                child: Image.asset(
                  'assets/app_logo.png',
                  width: 64,
                  height: 64,
                  errorBuilder: (context, _, _) => const SizedBox(
                    width: 64,
                    height: 64,
                    child: Icon(Icons.image_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PRPR', style: textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text('版本 $version', style: AppTheme.hint(context)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            '一个看图 + 换壁纸的小工具。原版是 Windows 10 的 UWP 应用，'
            '在微软下架 UWP 应用商店后停止维护；这一版用 Flutter 重写，'
            '目标是同样的功能能在当前的 Windows 上继续用。',
            style: textTheme.bodyMedium,
          ),
          const Divider(height: 40),
          Row(
            children: [
              AppTheme.sectionAccent(context),
              Text('致谢', style: AppTheme.sectionTitle(context)),
            ],
          ),
          const SizedBox(height: 8),
          const _Bullet('laplamgor — 原 PRPR 项目作者（2017–2020）。功能设计、交互流程与裁剪算法都来自他的 UWP 原版。'),
          const _Bullet('nagadomi — lbpcascade_animeface 级联模型（MIT，2011），人脸检测靠它。'),
          const _Bullet('OpenCV / opencv_dart — 图像处理与级联推理。'),
          const _Bullet('yande.re / konachan — 被支持的图站，请遵守各站的使用条款。'),
          const _Bullet('Flutter、Dart 及 pub 上的一切依赖。'),
          const Divider(height: 40),
          Row(
            children: [
              AppTheme.sectionAccent(context),
              Text('运行时信息', style: AppTheme.sectionTitle(context)),
            ],
          ),
          const SizedBox(height: 8),
          _kv(context, '站点', settings.host),
          _kv(context, '登录状态', settings.isLoggedIn ? '已登录（${settings.userName}）' : '未登录'),
          _kv(context, '历史记录', '${state.history.length} 条'),
          const Divider(height: 40),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: const Text('开源许可'),
            subtitle: const Text('查看所有第三方依赖的许可证'),
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
          ),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 80,
              child: Text(key, style: AppTheme.hint(context)),
            ),
            Expanded(child: SelectableText(value)),
          ],
        ),
      );
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('· '),
            Expanded(child: Text(text)),
          ],
        ),
      );
}
