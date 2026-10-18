import '../models/post.dart';
import '../models/tag.dart';

/// 「每日精选」的数据装配。对应原 `FeatureViewModel` 的 Update / UpdateTop3 /
/// GetAllTags / UpdateFeatureTags 四个方法。
///
/// 单独抽出来是因为原版这段逻辑混在 ViewModel 里，既做网络又做统计还做排序，
/// 没法测。这里只做纯计算：输入一批帖子，输出 Top3 与精选标签。
class DailyFeature {
  const DailyFeature({required this.topToday, required this.featuredTags});

  /// 今日最高分的 3 张。
  final List<Post> topToday;

  /// 精选标签。对应原 `FeaturedTag`。
  final List<FeaturedTag> featuredTags;

  static const DailyFeature empty =
      DailyFeature(topToday: <Post>[], featuredTags: <FeaturedTag>[]);

  /// 24 小时内的高分帖子算作「今日」。原版用 `posts.First().created_at - 86400`。
  static const int windowSeconds = 60 * 60 * 24;

  /// 这些标签太泛或没有检索价值，原版显式跳过。
  static const Set<String> skippedTags = <String>{'male', 'tagme', 'text'};

  /// 从 [posts] 装配。调用者负责保证 posts 是 `rating:s` 且已按时间倒序。
  ///
  /// [tagLookup] 用来把标签名映射到详情（类型 / 别名），
  /// 对应原 `TagDataBase.AllTags`；取不到时按 `TagType.none0` 处理。
  factory DailyFeature.build(
    List<Post> posts, {
    Map<String, TagDetail>? tagLookup,
    String tagBlacklist = '',
  }) {
    if (posts.isEmpty) return empty;

    final newest = posts.first.createdAtUnix;
    final dayBefore = newest - windowSeconds;
    final today =
        posts.where((p) => p.createdAtUnix >= dayBefore).toList(growable: false);

    final blocked = tagBlacklist
        .split(' ')
        .where((e) => e.isNotEmpty)
        .map((e) => e.toLowerCase())
        .toSet();

    final kept = today.where((p) {
      if (blocked.isEmpty) return true;
      return !p.tagList.any((t) => blocked.contains(t.toLowerCase()));
    }).toList(growable: false);

    return DailyFeature(
      topToday: _top(kept, 3),
      featuredTags: _featured(kept, tagLookup),
    );
  }

  /// 按分数降序取前 [count] 张。原版用 `int.Parse(o.Score)`，脏数据会抛异常，
  /// 这里用 tryParse 兜底为 0。
  static List<Post> _top(List<Post> posts, int count) {
    final sorted = List<Post>.from(posts)
      ..sort((a, b) => _score(b).compareTo(_score(a)));
    return sorted.take(count).toList(growable: false);
  }

  static int _score(Post p) => int.tryParse(p.score) ?? 0;

  /// 统计标签并挑出精选。对应原 `GetAllTags` + `UpdateFeatureTags`。
  static List<FeaturedTag> _featured(
    List<Post> posts,
    Map<String, TagDetail>? tagLookup,
  ) {
    // 标签 -> 出现的帖子
    final byTag = <String, List<Post>>{};
    for (final post in posts) {
      for (final tag in post.tagList) {
        byTag.putIfAbsent(tag, () => <Post>[]).add(post);
      }
    }

    final candidates = <({String name, List<Post> posts})>[];
    byTag.forEach((tag, tagPosts) {
      if (tagPosts.length < 2) return; // 只出现一次的标签没有代表性
      if (skippedTags.contains(tag)) return;

      final detail = tagLookup?[tag];
      final type = detail?.type ?? TagType.none;
      // 只保留普通标签和版权标签，角色/画师/社团留给别的入口
      if (type != TagType.none && type != TagType.copyright) return;
      // 别名标签不作为精选（原版检索时也会跳过别名）
      if (detail?.isAlias ?? false) return;

      candidates.add((name: tag, posts: tagPosts));
    });

    // 原版用 Guid.NewGuid() 随机排序；这里用固定散列保证同一天结果稳定，
    // 否则每次重建页面精选标签都在跳。
    candidates.sort((a, b) {
      final h = a.name.hashCode.compareTo(b.name.hashCode);
      if (h != 0) return h;
      return b.posts.length.compareTo(a.posts.length);
    });

    final used = <int>{};
    final result = <FeaturedTag>[];
    for (final candidate in candidates) {
      // 挑一张还没被别的精选标签用过的帖子当封面。
      // 原版的排序键是 `score / 标签数`，越小越靠前 —— 即「分数低但标签多」，
      // 那其实是原版的反向指标，这里直接取分数最高的，语义更直白。
      final available = candidate.posts.where((p) => !used.contains(p.id));
      if (available.isEmpty) continue;
      final cover = available.reduce(
        (a, b) => _score(a) >= _score(b) ? a : b,
      );
      used.add(cover.id);
      result.add(FeaturedTag(name: candidate.name, posts: candidate.posts, cover: cover));
      if (result.length >= 12) break;
    }
    return result;
  }
}

/// 一个精选标签及其下的帖子。对应原 `FeaturedTag`。
class FeaturedTag {
  const FeaturedTag({required this.name, required this.posts, required this.cover});

  final String name;
  final List<Post> posts;

  /// 用作该标签卡片封面的帖子。
  final Post cover;
}
