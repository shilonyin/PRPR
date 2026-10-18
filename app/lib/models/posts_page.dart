import 'dart:convert';

import 'post.dart';

/// 一页帖子。对应原 `Posts.cs` 里的 `SerializablePosts`。
class PostsPage {
  const PostsPage({
    required this.items,
    required this.totalCount,
    required this.offset,
  });

  final List<Post> items;

  /// 站点声明的总条数，用于判断还有没有下一页。
  final int totalCount;

  /// 本页起始偏移。
  final int offset;

  /// 原版 `HasMoreItems => Offset + Count < TotalCount`。
  bool get hasMore => offset + items.length < totalCount;

  static const PostsPage empty = PostsPage(items: <Post>[], totalCount: 0, offset: 0);
}

/// 本地缓存的帖子条目。
///
/// 原 UWP 版用 EF Core + SQLite 存 `WallpaperRecords` / `LockScreenRecords` 与帖子元数据。
/// 这里用一个轻量结构，`toJson` 后直接丢进 SQLite 的 TEXT 列，避免维护复杂迁移。
class PostRecord {
  const PostRecord({
    required this.id,
    required this.tags,
    required this.rating,
    required this.width,
    required this.height,
    required this.fileUrl,
    required this.previewUrl,
    required this.jpegUrl,
    required this.sampleUrl,
    required this.createdAtUnix,
    required this.savedAtUnix,
  });

  final int id;
  final String tags;
  final String rating;
  final int width;
  final int height;
  final String fileUrl;
  final String previewUrl;
  final String jpegUrl;
  final String sampleUrl;
  final int createdAtUnix;
  final int savedAtUnix;

  factory PostRecord.fromPost(Post p) => PostRecord(
        id: p.id,
        tags: p.tags,
        rating: p.rating,
        width: p.width,
        height: p.height,
        fileUrl: p.fileUrl,
        previewUrl: p.previewUrl,
        jpegUrl: p.jpegUrl,
        sampleUrl: p.sampleUrl,
        createdAtUnix: p.createdAtUnix,
        savedAtUnix: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'tags': tags,
        'rating': rating,
        'width': width,
        'height': height,
        'fileUrl': fileUrl,
        'previewUrl': previewUrl,
        'jpegUrl': jpegUrl,
        'sampleUrl': sampleUrl,
        'createdAtUnix': createdAtUnix,
        'savedAtUnix': savedAtUnix,
      };

  factory PostRecord.fromJson(Map<String, dynamic> json) => PostRecord(
        id: (json['id'] as num?)?.toInt() ?? 0,
        tags: json['tags'] as String? ?? '',
        rating: json['rating'] as String? ?? 's',
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
        fileUrl: json['fileUrl'] as String? ?? '',
        previewUrl: json['previewUrl'] as String? ?? '',
        jpegUrl: json['jpegUrl'] as String? ?? '',
        sampleUrl: json['sampleUrl'] as String? ?? '',
        createdAtUnix: (json['createdAtUnix'] as num?)?.toInt() ?? 0,
        savedAtUnix: (json['savedAtUnix'] as num?)?.toInt() ?? 0,
      );

  String encode() => jsonEncode(toJson());

  static PostRecord decode(String raw) =>
      PostRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
