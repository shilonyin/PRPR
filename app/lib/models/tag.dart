/// 标签类型。对应原 `TagDataBase.TagType`。
///
/// 数值与原版一致，因为站点 `tag/summary.json` 里用数字表示类型。
enum TagType {
  none(0),
  artist(1),
  notUsed(2),
  copyright(3),
  character(4),
  circle(5),
  faults(6);

  const TagType(this.value);
  final int value;

  static TagType fromValue(int v) {
    for (final t in TagType.values) {
      if (t.value == v) return t;
    }
    return TagType.none;
  }
}

/// 一个标签的详情。
///
/// `parent` 非空表示这是别名，指向规范名。对应原 `TagDetail.IsAlias`。
class TagDetail {
  const TagDetail({
    required this.name,
    required this.type,
    this.parent,
  });

  final String name;
  final TagType type;
  final String? parent;

  bool get isAlias => parent != null;

  /// 别名解析到规范名；非别名返回自身。
  String get canonicalName => parent ?? name;
}

/// 标签数据库。对应原 `BooruViewer\\Services\\TagDataBase.cs`。
///
/// 原版是静态类 + 静态字典；这里保留单例语义以便测试注入。
class TagDatabase {
  TagDatabase();

  static final TagDatabase instance = TagDatabase();

  final Map<String, TagDetail> _tags = <String, TagDetail>{};

  /// 平滑权重计算的特殊字符集合。原版 `specialChars`。
  static const Set<String> _specialChars = {'_', '(', '/'};

  int get length => _tags.length;

  bool get isEmpty => _tags.isEmpty;

  TagDetail? operator [](String name) => _tags[name];

  Iterable<TagDetail> get all => _tags.values;

  /// 清空并载入。`data` 形如 `1`name`alias1`alias2 3`copyright`...`（按空格分词）。
  ///
  /// 对应原 `DownloadLatestTagDBAsync` 的解析逻辑：
  /// 每段再按反引号拆分，第一段是类型数字，第二段是规范名，其后都是别名。
  void loadFromSummaryString(String data) {
    _tags.clear();
    final entries = data.split(' ').where((e) => e.isNotEmpty);
    for (final entry in entries) {
      final parts = entry.split('\u0060'); // 反引号
      if (parts.length < 2) continue;

      final type = TagType.fromValue(int.tryParse(parts[0].trim()) ?? 0);
      final name = parts[1].trim();
      if (name.isEmpty) continue;

      _tags[name] = TagDetail(name: name, type: type);

      for (var i = 2; i < parts.length; i++) {
        final alias = parts[i].trim();
        if (alias.isEmpty || _tags.containsKey(alias)) continue;
        _tags[alias] = TagDetail(name: alias, type: type, parent: name);
      }
    }
  }

  /// 标签自动补全的相似度打分。
  ///
  /// 逐字符还原原版 `Similiarity`：先判断 `key` 是否是 `name` 的子串，
  /// 命中后按「越靠前越好、后缀完整更好」给分，最后减去长度差。
  /// 完全不含 key 时返回 `null`（原版用 `int.MinValue`，Dart 侧用 null 更安全）。
  static int? similarity(String name, String key) {
    if (key.isEmpty) return null;
    final index = name.indexOf(key);
    if (index == -1) return null;

    var baseValue = 0x7FFFFFFF; // int.MaxValue
    var lengthDiff = name.length - key.length;

    if (index != 0) {
      // key 不在开头：优先级降低
      baseValue >>= 1;
      // 前一个字符不是特殊字符，说明是词中截断，再降一次
      final prev = name[index - 1];
      if (!_specialChars.contains(prev)) {
        baseValue >>= 1;
      }
    }

    final afterIndex = index + key.length;
    if (afterIndex < name.length) {
      // key 后面还有内容：尾部不匹配
      baseValue >>= 1;
      final next = name[afterIndex];
      if (!_specialChars.contains(next)) {
        baseValue >>= 1;
      }
    }

    return baseValue - lengthDiff;
  }

  /// 按前缀/子串检索标签，按相似度降序。
  List<TagDetail> search(String key, {int limit = 30}) {
    if (key.isEmpty) return const <TagDetail>[];
    final scored = <MapEntry<TagDetail, int>>[];
    for (final tag in _tags.values) {
      // 别名不重复出现在补全里
      if (tag.isAlias) continue;
      final s = similarity(tag.name, key);
      if (s != null) scored.add(MapEntry(tag, s));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(limit).map((e) => e.key).toList();
  }
}
