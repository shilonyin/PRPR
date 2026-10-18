import 'post.dart';

/// 帖子的分级筛选条件。对应原 `BooruViewer\\Models\\PostFilter.cs`。
///
/// 原版把这些字段放在一个可观察类里、通过 `ToFunc()` 编译成一个谓词；
/// 这里改成纯粹的值对象 + `apply` 方法，方便在纯 Dart 环境下测试。
class PostFilter {
  const PostFilter({
    this.isFilterSafe = true,
    this.isFilterQuestionable = false,
    this.isFilterExplicit = false,
    this.isFilterHorizontal = true,
    this.isFilterVertical = true,
    this.isFilterAllowHidden = false,
    this.isFilterAllowHeld = false,
    this.tagBlacklist = '',
  });

  final bool isFilterSafe;
  final bool isFilterQuestionable;
  final bool isFilterExplicit;
  final bool isFilterHorizontal;
  final bool isFilterVertical;
  final bool isFilterAllowHidden;
  final bool isFilterAllowHeld;

  /// 空格分隔的标签黑名单，命中任一即过滤掉。
  final String tagBlacklist;

  static const PostFilter all = PostFilter(
    isFilterSafe: true,
    isFilterQuestionable: true,
    isFilterExplicit: true,
    isFilterHorizontal: true,
    isFilterVertical: true,
    isFilterAllowHidden: true,
    isFilterAllowHeld: true,
  );

  List<String> get blacklistTerms =>
      tagBlacklist.isEmpty ? const <String>[] : tagBlacklist.split(' ').where((e) => e.isNotEmpty).toList();

  PostFilter copyWith({
    bool? isFilterSafe,
    bool? isFilterQuestionable,
    bool? isFilterExplicit,
    bool? isFilterHorizontal,
    bool? isFilterVertical,
    bool? isFilterAllowHidden,
    bool? isFilterAllowHeld,
    String? tagBlacklist,
  }) {
    return PostFilter(
      isFilterSafe: isFilterSafe ?? this.isFilterSafe,
      isFilterQuestionable: isFilterQuestionable ?? this.isFilterQuestionable,
      isFilterExplicit: isFilterExplicit ?? this.isFilterExplicit,
      isFilterHorizontal: isFilterHorizontal ?? this.isFilterHorizontal,
      isFilterVertical: isFilterVertical ?? this.isFilterVertical,
      isFilterAllowHidden: isFilterAllowHidden ?? this.isFilterAllowHidden,
      isFilterAllowHeld: isFilterAllowHeld ?? this.isFilterAllowHeld,
      tagBlacklist: tagBlacklist ?? this.tagBlacklist,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'isFilterSafe': isFilterSafe,
        'isFilterQuestionable': isFilterQuestionable,
        'isFilterExplicit': isFilterExplicit,
        'isFilterHorizontal': isFilterHorizontal,
        'isFilterVertical': isFilterVertical,
        'isFilterAllowHidden': isFilterAllowHidden,
        'isFilterAllowHeld': isFilterAllowHeld,
        'tagBlacklist': tagBlacklist,
      };

  factory PostFilter.fromJson(Map<String, dynamic> json) => PostFilter(
        isFilterSafe: json['isFilterSafe'] as bool? ?? true,
        isFilterQuestionable: json['isFilterQuestionable'] as bool? ?? false,
        isFilterExplicit: json['isFilterExplicit'] as bool? ?? false,
        isFilterHorizontal: json['isFilterHorizontal'] as bool? ?? true,
        isFilterVertical: json['isFilterVertical'] as bool? ?? true,
        isFilterAllowHidden: json['isFilterAllowHidden'] as bool? ?? false,
        isFilterAllowHeld: json['isFilterAllowHeld'] as bool? ?? false,
        tagBlacklist: json['tagBlacklist'] as String? ?? '',
      );

  /// 单个帖子是否通过筛选。
  ///
  /// 严格对应原 `ToFunc()` 的组合逻辑：
  /// 分级匹配 && 横竖匹配 && (在索引中可见 || 允许隐藏) && (允许 held || 未被 held) && 标签未命中黑名单。
  bool apply(Post post) {
    // 1. 分级
    var ratingOk = false;
    switch (post.rating) {
      case 's':
        ratingOk = isFilterSafe;
        break;
      case 'q':
        ratingOk = isFilterQuestionable;
        break;
      case 'e':
        ratingOk = isFilterExplicit;
        break;
      default:
        // 未知分级一律放行，避免整站空列表
        ratingOk = true;
    }
    if (!ratingOk) return false;

    // 2. 横竖。注意原版用 Width >= Height 判定「横图」
    final horizontal = post.width >= post.height;
    if (horizontal ? !isFilterHorizontal : !isFilterVertical) return false;

    // 3. 索引可见性
    if (!post.isShownInIndex && !isFilterAllowHidden) return false;

    // 4. held 状态
    if (!isFilterAllowHeld && post.isHeld) return false;

    // 5. 标签黑名单
    final terms = blacklistTerms;
    if (terms.isNotEmpty) {
      final postTags = post.tagList.toSet();
      for (final term in terms) {
        if (postTags.contains(term)) return false;
      }
    }

    return true;
  }
}
