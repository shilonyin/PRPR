import 'package:flutter/material.dart';

import '../theme.dart';

/// 小节标题。
///
/// 旧版是「3x16 的金色竖条 + 15px 半粗标题」，一页里重复五六次之后，
/// 每条竖条都在跟内容抢注意力，而且竖条和标题的中线永远差 1px。
///
/// 新版没有竖条：标题就是一行 13px 的等宽大写标签（`PALETTE` / `危险操作`），
/// 靠字距和颜色和正文区分开。需要更强的分隔时在外面加一条 Divider，
/// 而不是给标题加装饰。
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader(
    this.title, {
    super.key,
    this.trailing,
    this.hint,
    this.danger = false,
  });

  final String title;

  /// 右侧的附加控件（刷新按钮、数量）。
  final Widget? trailing;

  /// 标题下面的一行说明。
  final String? hint;

  /// 危险区：标题与分隔线都走 danger 色。
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    final color = danger ? c.danger : c.inkDim;
    final h = hint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: AppType.kicker.copyWith(color: color),
              ),
            ),
            ?trailing,
          ],
        ),
        if (h != null) ...[
          const SizedBox(height: 2),
          Text(
            h,
            style: AppType.caption.copyWith(color: c.inkFaint),
          ),
        ],
      ],
    );
  }
}
