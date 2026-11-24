import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/history_store.dart';
import '../../services/wallpaper_engine.dart';
import '../../services/wallpaper_service.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_topbar.dart';
import '../widgets/state_message.dart';

/// 换壁纸历史页。
///
/// 原 UWP 版把历史存在 EF Core + SQLite 里，只用于「不要重复换到同一张」，
/// 没有界面。桌面端把它暴露出来，因为「刚才那张挺好看的，想找回来」是很自然的需求。
///
/// 版式：56px 顶栏（页名 + 条数 + 清空）+ 行式列表。行高 64、左缩进与
/// 搜索页的 pagePadding 对齐，缩略图 40 方圆角 4。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  /// 列表缩略图边长。分隔线的 indent 由它推出来，避免手写一个对不上的数。
  static const double _thumbSize = 40;

  Future<void> _clear() async {
    final state = context.read<AppState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final c = AppColor.of(context);
        return AlertDialog(
          backgroundColor: c.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            side: BorderSide(color: c.line),
          ),
          title: Text('清空历史', style: AppType.section.copyWith(color: c.ink)),
          content: Text(
            '只会清空记录列表，已经下载到本地的图片文件会保留。',
            style: AppType.body.copyWith(color: c.inkDim),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            // 破坏性确认统一用 danger 描边而不是金色实底：
            // 金色是「主行动」的语言，清空历史不该长得像鼓励用户点。
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.danger,
                side: BorderSide(color: c.danger),
              ),
              child: const Text('清空'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await state.history.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    final state = context.read<AppState>();
    // 记录只在 done 阶段前后写入：成功靠 wallpaperAppliedTick 重建，
    // 失败记录不递增 tick，靠 done 翻转补一次。两者都比 watch 整个
    // AppState 省——换壁纸途中的 fetching/downloading 等阶段与本页无关。
    context.select<AppState, bool>((s) => s.currentStage == ChangeStage.done);

    return ValueListenableBuilder<int>(
      valueListenable: state.wallpaperAppliedTick,
      builder: (context, _, _) => _buildBody(c, state),
    );
  }

  Widget _buildBody(AppPalette c, AppState state) {
    final items = state.history.all;

    return Column(
      children: [
        AppTopBar(
          child: Row(
            children: [
              Text('历史', style: AppType.section.copyWith(color: c.ink)),
              const SizedBox(width: AppTheme.gapM),
              AppTopBarLabel('${items.length} / ${HistoryStore.maxEntries}'),
              const Spacer(),
              TextButton.icon(
                onPressed: items.isEmpty ? null : _clear,
                icon: const Icon(Icons.delete_outline, size: AppTheme.iconXs),
                label: const Text('清空'),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const StateMessage(
                  icon: Icons.history,
                  title: '还没有换过壁纸',
                  hint: '换一张之后，这里会留下记录，方便找回刚才那张。',
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppTheme.gapS,
                    horizontal: AppTheme.pagePadding,
                  ),
                  itemCount: items.length,
                  // 分隔线从缩略图右侧起，跳过图片那一段。
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    indent: _thumbSize + AppTheme.gapM,
                    color: c.line.withValues(alpha: 0.7),
                  ),
                  itemBuilder: (context, index) {
                    final record = items[index];
                    // 只有刚写进来的那条才播入场：判定方式是「时间戳离现在很近」。
                    // 不用 compare 上一次列表快照，是因为用户可能在历史页停留时
                    // 换壁纸，那时列表会原地重建，快照法会把整列都当成新的。
                    final fresh = DateTime.now()
                            .difference(record.appliedAt)
                            .inSeconds <
                        3;
                    return _HistoryRow(
                      key: ValueKey<int>(record.appliedAtUnix * 1000 +
                          record.postId),
                      record: record,
                      animate: fresh,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatefulWidget {
  const _HistoryRow({super.key, required this.record, this.animate = false});

  final HistoryRecord record;

  /// 新的一行从上方 12px 滑进来，让「刚刚换上了」这件事有个落点。
  final bool animate;

  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColor.of(context);
    final row = _buildRow(c);
    if (!widget.animate) return row;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: -12, end: 0),
      duration: AppTheme.durSlow,
      curve: AppTheme.curveIn,
      builder: (context, dy, child) => Transform.translate(
        offset: Offset(0, dy),
        child: Opacity(
          opacity: (1 + dy / 12).clamp(0.0, 1.0),
          child: child,
        ),
      ),
      child: row,
    );
  }

  /// 点击行：把这条记录的本地裁剪图直接重设为壁纸。
  ///
  /// HistoryRecord 只有 postId/tags/filePath，凑不出完整 Post，走不了
  /// AppState.applyPost；而 filePath 正是上次设壁纸用的裁剪图，直接交给
  /// WallpaperService 就是「找回刚才那张」的最短路径，不依赖网络。
  Future<void> _reapply() async {
    final state = context.read<AppState>();
    // 引擎在跑时不插队：两条管线同时写系统壁纸会互相覆盖。
    if (state.engine.isBusy) {
      AppToast.info(context, '上一次更换尚未完成');
      return;
    }
    final record = widget.record;
    if (record.filePath.isEmpty || !await File(record.filePath).exists()) {
      if (mounted) AppToast.error(context, '本地图片已不存在，无法重设');
      return;
    }
    final result = await WallpaperService().setWallpaperAsync(
      record.filePath,
      fitMode: state.settings.fitMode,
    );
    if (!mounted) return;
    if (result.isSuccess) {
      // 不新增历史记录：这是「重设」不是「换一张」，列表不该多出一行。
      state.wallpaperAppliedTick.value++;
      AppToast.neutral(context, '已重设为壁纸：#${record.postId}');
    } else {
      AppToast.error(context, '重设失败：${result.message}');
    }
  }

  Widget _buildRow(AppPalette c) {
    final record = widget.record;
    final time = record.appliedAt;

    return Tooltip(
      message: '点击重设为壁纸',
      waitDuration: const Duration(milliseconds: 420),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: InkWell(
          onTap: _reapply,
          child: AnimatedContainer(
            duration: AppTheme.durFast,
            color: _hover ? c.panel : Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              children: [
                Container(
                  width: _HistoryPageState._thumbSize,
                  height: _HistoryPageState._thumbSize,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(AppTheme.imageRadius),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.file(
                    File(record.filePath),
                    fit: BoxFit.cover,
                    // filePath 是屏幕分辨率的裁剪 PNG，全尺寸解码一张
                    // 4K RGBA 约 33MB，十行可见就撑爆 imageCache。
                    // 按显示尺寸 × DPR 解码，40px 缩略图只花几十 KB。
                    cacheWidth: (_HistoryPageState._thumbSize *
                            MediaQuery.devicePixelRatioOf(context))
                        .round(),
                    // 用户可能手动删掉了下载目录，这里必须容错
                    errorBuilder: (context, _, _) => Icon(
                      Icons.image_outlined,
                      size: AppTheme.iconXs,
                      color: c.inkFaint,
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.gapM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        record.tags.isEmpty ? '#${record.postId}' : record.tags,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.body.copyWith(color: c.ink),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            _stamp(time),
                            style: AppType.monoData.copyWith(color: c.inkFaint),
                          ),
                          const SizedBox(width: AppTheme.gapM),
                          Text(
                            '#${record.postId}',
                            style: AppType.monoData.copyWith(color: c.inkFaint),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppTheme.gapM),
                if (!record.success)
                  Text(
                    '失败',
                    style: AppType.monoData.copyWith(color: c.danger),
                  )
                else
                  Icon(
                    Icons.check,
                    size: AppTheme.iconXs,
                    color: c.safe.withValues(alpha: 0.8),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _stamp(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';

  static String _two(int v) => v.toString().padLeft(2, '0');
}
