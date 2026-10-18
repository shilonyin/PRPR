import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/posts_page.dart';

/// 壁纸历史记录。对应原 UWP 用 EF Core 存的 `WallpaperRecords` / `LockScreenRecords`。
///
/// 原版为这两张表维护了完整的 EF Core 迁移（Migrations 目录 5 个文件）。
/// 迁移到 Flutter 后权衡：
/// - 数据量很小（一次换壁纸一条），且只用于「避免重复、查看历史」；
/// - 引入 sqflite/drift 会带来平台插件与迁移脚本维护负担；
/// - 因此改为 **单个 JSON 文件** + 内存环形缓冲。
///
/// 代价是失去并发写入能力（桌面单实例场景不构成问题），
/// 换来零依赖与人类可读的存储格式。
class HistoryStore {
  HistoryStore._(this._file, this._items);

  static const int maxEntries = 500;
  static const String _fileName = 'wallpaper_history.json';

  final File _file;
  final List<HistoryRecord> _items;

  static Future<HistoryStore> load() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}$_fileName');

    final items = <HistoryRecord>[];
    if (await file.exists()) {
      try {
        final raw = await file.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded) {
            if (e is Map<String, dynamic>) {
              items.add(HistoryRecord.fromJson(e));
            }
          }
        }
      } catch (_) {
        // 文件损坏时静默重置：历史记录不值得阻塞启动
      }
    }

    return HistoryStore._(file, items);
  }

  /// 最近一条记录。
  HistoryRecord? get latest => _items.isEmpty ? null : _items.first;

  /// 按时间倒序的全部记录（只读视图）。
  List<HistoryRecord> get all => List<HistoryRecord>.unmodifiable(_items);

  int get length => _items.length;

  /// 最近的帖子 ID 集合，用于避免连续重复。
  Set<int> recentPostIds([int window = 20]) =>
      _items.take(window).map((e) => e.postId).toSet();

  /// 追加一条记录并落盘。
  Future<void> add(HistoryRecord record) async {
    _items.insert(0, record);
    if (_items.length > maxEntries) {
      _items.removeRange(maxEntries, _items.length);
    }
    await _flush();
  }

  Future<void> clear() async {
    _items.clear();
    await _flush();
  }

  Future<void> _flush() async {
    try {
      final payload = jsonEncode(_items.map((e) => e.toJson()).toList());
      // 先写临时文件再改名，避免写一半崩溃留下坏文件
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(payload, flush: true);
      await tmp.rename(_file.path);
    } catch (_) {
      // 落盘失败不影响本次换壁纸
    }
  }
}

/// 一条壁纸历史记录。
class HistoryRecord {
  const HistoryRecord({
    required this.postId,
    required this.tags,
    required this.filePath,
    required this.appliedAtUnix,
    required this.cropMethodIndex,
    required this.success,
    this.message,
  });

  final int postId;
  final String tags;

  /// 实际设置为壁纸的本地文件路径（裁剪后）。
  final String filePath;
  final int appliedAtUnix;
  final int cropMethodIndex;
  final bool success;
  final String? message;

  DateTime get appliedAt =>
      DateTime.fromMillisecondsSinceEpoch(appliedAtUnix * 1000);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'postId': postId,
        'tags': tags,
        'filePath': filePath,
        'appliedAtUnix': appliedAtUnix,
        'cropMethodIndex': cropMethodIndex,
        'success': success,
        if (message != null) 'message': message,
      };

  factory HistoryRecord.fromJson(Map<String, dynamic> json) => HistoryRecord(
        postId: (json['postId'] as num?)?.toInt() ?? 0,
        tags: json['tags'] as String? ?? '',
        filePath: json['filePath'] as String? ?? '',
        appliedAtUnix: (json['appliedAtUnix'] as num?)?.toInt() ?? 0,
        cropMethodIndex: (json['cropMethodIndex'] as num?)?.toInt() ?? 0,
        success: json['success'] as bool? ?? false,
        message: json['message'] as String?,
      );

  /// 便于和 [PostRecord] 互转。
  static HistoryRecord fromPostRecord(
    PostRecord record, {
    required String filePath,
    required int cropMethodIndex,
    required bool success,
    String? message,
  }) =>
      HistoryRecord(
        postId: record.id,
        tags: record.tags,
        filePath: filePath,
        appliedAtUnix: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        cropMethodIndex: cropMethodIndex,
        success: success,
        message: message,
      );
}
