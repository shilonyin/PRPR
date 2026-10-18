import 'dart:math' as math;

/// 图片来源版本，对应原 `PostImageVersion`。
enum PostImageVersion { preview, sample, jpeg, source }

/// 一条 booru 帖子。
///
/// 对应原 UWP 项目 `BooruViewer\\Models\\Post.cs`。
/// 原版通过 `XmlSerializer` 把 `/post.xml` 的 `<post/>` 节点直接反序列化；
/// Flutter 侧改用 `xml` 包手动解析，字段名与原 XmlAttribute 保持一致。
class Post {
  final int id;
  final String tags;
  final int createdAtUnix;
  final int creatorId;
  final String author;
  final int change;
  final String source;
  final String fileExtension;
  final String score;

  /// 文件 md5，去重用。
  final String md5;
  final int fileSize;
  final String fileUrl;

  final bool isShownInIndex;
  final String previewUrl;
  final int previewWidth;
  final int previewHeight;
  final int actualPreviewWidth;
  final int actualPreviewHeight;

  final String sampleUrl;
  final int sampleWidth;
  final int sampleHeight;
  final int sampleFileSize;

  final String jpegUrl;
  final int jpegWidth;
  final int jpegHeight;
  final int jpegFileSize;

  /// 分级：s = safe，q = questionable，e = explicit。
  final String rating;

  final bool hasChildren;
  final String status;
  final int parentId;

  final int width;
  final int height;
  final bool isHeld;

  const Post({
    required this.id,
    required this.tags,
    required this.createdAtUnix,
    required this.creatorId,
    required this.author,
    required this.change,
    required this.source,
    required this.fileExtension,
    required this.score,
    required this.md5,
    required this.fileSize,
    required this.fileUrl,
    required this.isShownInIndex,
    required this.previewUrl,
    required this.previewWidth,
    required this.previewHeight,
    required this.actualPreviewWidth,
    required this.actualPreviewHeight,
    required this.sampleUrl,
    required this.sampleWidth,
    required this.sampleHeight,
    required this.sampleFileSize,
    required this.jpegUrl,
    required this.jpegWidth,
    required this.jpegHeight,
    required this.jpegFileSize,
    required this.rating,
    required this.hasChildren,
    required this.status,
    required this.parentId,
    required this.width,
    required this.height,
    required this.isHeld,
  });

  DateTime get createdAtUtc =>
      DateTime.fromMillisecondsSinceEpoch(createdAtUnix * 1000, isUtc: true);

  /// 原版 `IsJpeg => JpegFileSize == 0` 的语义有些反直觉：
  /// 站点对「原图本身就是 jpeg」的帖子不再单独生成 jpeg 版本，因此 jpeg 尺寸为 0。
  bool get isJpeg => jpegFileSize == 0;

  bool get isHorizontal => width >= height;

  /// 宽高比，用于瀑布流布局。
  double get preferredRatio => height == 0 ? 1.0 : width / height;

  /// 标签列表（已按空格拆开）。
  List<String> get tagList =>
      tags.isEmpty ? const <String>[] : tags.split(' ').where((e) => e.isNotEmpty).toList();

  /// 按指定版本取图片地址。找不到时逐级降级，保证永远有结果。
  ///
  /// 对应原 `PostImageVersion` 的用途。
  String urlFor(PostImageVersion version) {
    switch (version) {
      case PostImageVersion.source:
        if (fileUrl.isNotEmpty) return fileUrl;
        return urlFor(PostImageVersion.jpeg);
      case PostImageVersion.jpeg:
        if (jpegUrl.isNotEmpty) return jpegUrl;
        return urlFor(PostImageVersion.sample);
      case PostImageVersion.sample:
        if (sampleUrl.isNotEmpty) return sampleUrl;
        return urlFor(PostImageVersion.preview);
      case PostImageVersion.preview:
        return previewUrl;
    }
  }

  /// 按版本取该版本的已知宽高。返回 `null` 表示该版本尺寸未知，
  /// 调用方应回退到原图尺寸。
  math.Point<int>? sizeFor(PostImageVersion version) {
    switch (version) {
      case PostImageVersion.source:
        return math.Point(width, height);
      case PostImageVersion.jpeg:
        return jpegFileSize == 0 ? null : math.Point(jpegWidth, jpegHeight);
      case PostImageVersion.sample:
        return sampleWidth == 0 || sampleHeight == 0
            ? null
            : math.Point(sampleWidth, sampleHeight);
      case PostImageVersion.preview:
        return previewWidth == 0 || previewHeight == 0
            ? null
            : math.Point(previewWidth, previewHeight);
    }
  }

  /// 站点上的帖子详情页。
  String detailUrl(String host) => '$host/post/show/$id';

  static int _asInt(String? v, [int fallback = 0]) =>
      v == null ? fallback : (int.tryParse(v.trim()) ?? fallback);

  static bool _asBool(String? v) => v == 'true' || v == '1';

  /// 从 `<post .../>` 元素解析。缺失字段用安全默认值填充，不抛异常。
  factory Post.fromXml(dynamic element) {
    String attr(String name) {
      // element 为 xml 包中的 XmlElement，属性值可能为 null。
      final v = element.getAttribute(name);
      return v ?? '';
    }

    return Post(
      id: _asInt(attr('id')),
      // 注意：站点把属性名拼成 `tag-string` 与 XML 标签的 `tags` 不同，
      // 原版 XmlAttribute("tags") 能对上，这里两者都试。
      tags: attr('tags').isNotEmpty ? attr('tags') : attr('tag_string'),
      createdAtUnix: _asInt(attr('created_at')),
      creatorId: _asInt(attr('creator_id')),
      author: attr('author'),
      change: _asInt(attr('change')),
      source: attr('source'),
      fileExtension: attr('file_ext'),
      score: attr('score'),
      md5: attr('md5'),
      fileSize: _asInt(attr('file_size')),
      fileUrl: attr('file_url'),
      isShownInIndex: _asBool(attr('is_shown_in_index')),
      previewUrl: attr('preview_url'),
      previewWidth: _asInt(attr('preview_width')),
      previewHeight: _asInt(attr('preview_height')),
      actualPreviewWidth: _asInt(attr('actual_preview_width')),
      actualPreviewHeight: _asInt(attr('actual_preview_height')),
      sampleUrl: attr('sample_url'),
      sampleWidth: _asInt(attr('sample_width')),
      sampleHeight: _asInt(attr('sample_height')),
      sampleFileSize: _asInt(attr('sample_file_size')),
      jpegUrl: attr('jpeg_url'),
      jpegWidth: _asInt(attr('jpeg_width')),
      jpegHeight: _asInt(attr('jpeg_height')),
      jpegFileSize: _asInt(attr('jpeg_file_size')),
      rating: attr('rating'),
      hasChildren: _asBool(attr('has_children')),
      status: attr('status'),
      parentId: _asInt(attr('parent_id')),
      width: _asInt(attr('width')),
      height: _asInt(attr('height')),
      isHeld: _asBool(attr('is_held')),
    );
  }
}
