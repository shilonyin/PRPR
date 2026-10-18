import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/history_store.dart';
import '../app_state.dart';

/// 换壁纸历史页。
///
/// 原 UWP 版把历史存在 EF Core + SQLite 里，只用于「不要重复换到同一张」，
/// 没有界面。桌面端把它暴露出来，因为「刚才那张挺好看的，想找回来」是很自然的需求。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  Future<void> _clear() async {
    final state = context.read<AppState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空历史'),
        content: const Text('只会清空记录列表，已经下载到本地的图片文件会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await state.history.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final items = state.history.all;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '共 ${items.length} 条记录（最多保留 ${HistoryStore.maxEntries} 条）',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                onPressed: items.isEmpty ? null : _clear,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('清空'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('还没有换过壁纸'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                  itemBuilder: (context, index) => _HistoryRow(record: items[index]),
                ),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.record});

  final HistoryRecord record;

  @override
  Widget build(BuildContext context) {
    final time = DateTime.fromMillisecondsSinceEpoch(record.appliedAtUnix * 1000);
    final subtitle = StringBuffer()
      ..write('${time.year}-${_two(time.month)}-${_two(time.day)} ')
      ..write('${_two(time.hour)}:${_two(time.minute)}');

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Image.file(
            File(record.filePath),
            fit: BoxFit.cover,
            // 用户可能手动删掉了下载目录，这里必须容错
            errorBuilder: (context, _, _) => const Icon(Icons.image_outlined),
          ),
        ),
      ),
      title: Text(
        record.tags.isEmpty ? '#${record.postId}' : record.tags,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle.toString()),
      trailing: Icon(
        record.success ? Icons.check_circle_outline : Icons.error_outline,
        color: record.success ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
