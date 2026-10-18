import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:prpr/models/post.dart';
import 'package:prpr/models/post_filter.dart';
import 'package:prpr/models/tag.dart';
import 'package:prpr/services/crop.dart';
import 'package:prpr/services/daily_feature.dart';
import 'package:xml/xml.dart';

/// 这些测试只覆盖从原 UWP 版逐行移植过来的纯逻辑。
///
/// 之所以优先测它们：移植代码最怕「看着一样、算出来不一样」，
/// 而平台层（Win32、OpenCV、SharedPreferences）在单元测试里跑不了。
/// 裁剪与人脸相关的算术一旦偏了，出来的壁纸就会裁到脸上，肉眼很难发现。
void main() {
  group('Post.parse', () {
    test('从站点 XML 解析出全部字段', () {
      final doc = XmlDocument.parse('''
<posts count="1" offset="0">
  <post id="123" tags="landscape sky rating:s" created_at="1600000000"
        creator_id="7" author="someone" change="5" source="http://x/"
        file_ext="jpg" score="12" md5="abc" file_size="2048"
        file_url="https://yande.re/image/abc.jpg"
        is_shown_in_index="true" preview_url="https://yande.re/p.jpg"
        preview_width="100" preview_height="200"
        actual_preview_width="90" actual_preview_height="180"
        sample_url="https://yande.re/s.jpg" sample_width="800"
        sample_height="1600" sample_file_size="900"
        jpeg_url="https://yande.re/j.jpg" jpeg_width="1000"
        jpeg_height="2000" jpeg_file_size="1500"
        rating="s" has_children="false" status="active" parent_id="0"
        width="1920" height="1080" is_held="false" />
</posts>
''');
      final element = doc.rootElement.childElements.first;
      final post = Post.fromXml(element);

      expect(post.id, 123);
      expect(post.tagList, <String>['landscape', 'sky', 'rating:s']);
      expect(post.rating, 's');
      expect(post.width, 1920);
      expect(post.height, 1080);
      expect(post.isHorizontal, isTrue);
      // score 在原模型里是字符串，因为站点会给 "-1"
      expect(post.score, '12');
      expect(post.fileUrl, 'https://yande.re/image/abc.jpg');
      expect(post.createdAtUtc.isUtc, isTrue);
    });

    test('missing 属性时退化到安全默认值', () {
      final doc = XmlDocument.parse('<posts><post id="1" /></posts>');
      final post = Post.fromXml(doc.rootElement.childElements.first);
      expect(post.id, 1);
      expect(post.rating, '');
      expect(post.width, 0);
      // 宽高都是 0 时按横图处理，否则会被横竖筛选整个丢掉
      expect(post.isHorizontal, isTrue);
      expect(post.preferredRatio, 1.0);
    });
  });

  group('Post.urlFor', () {
    final base = Post.fromXml(
      XmlDocument.parse('<posts><post id="1" width="10" height="10" /></posts>')
          .rootElement
          .childElements
          .first,
    );

    test('没有原图时逐级降级', () {
      expect(base.urlFor(PostImageVersion.source), '');
      expect(base.urlFor(PostImageVersion.jpeg), '');
      expect(base.urlFor(PostImageVersion.sample), '');
      expect(base.urlFor(PostImageVersion.preview), '');
    });
  });

  group('PostFilter', () {
    Post postWith({
      String rating = 's',
      int width = 100,
      int height = 50,
      String tags = '',
      bool hidden = false,
      bool held = false,
    }) =>
        Post.fromXml(XmlDocument.parse(
          '<posts><post id="1" rating="$rating" width="$width" '
          'height="$height" tags="$tags" '
          'is_shown_in_index="${!hidden}" is_held="$held" /></posts>',
        ).rootElement.childElements.first);

    test('默认只放行 safe', () {
      const filter = PostFilter();
      expect(filter.apply(postWith(rating: 's')), isTrue);
      expect(filter.apply(postWith(rating: 'q')), isFalse);
      expect(filter.apply(postWith(rating: 'e')), isFalse);
    });

    test('未知分级放行，避免整站空列表', () {
      expect(const PostFilter().apply(postWith(rating: '')), isTrue);
    });

    test('横竖筛选按 width >= height 判定', () {
      const onlyHorizontal = PostFilter(isFilterVertical: false);
      expect(onlyHorizontal.apply(postWith(width: 100, height: 50)), isTrue);
      expect(onlyHorizontal.apply(postWith(width: 50, height: 100)), isFalse);
      // 正方形算横图（原版也是 >=）
      expect(onlyHorizontal.apply(postWith(width: 50, height: 50)), isTrue);
    });

    test('黑名单命中任一标签即过滤', () {
      const filter = PostFilter(tagBlacklist: 'bikini pantsu');
      expect(filter.apply(postWith(tags: 'sky landscape')), isTrue);
      expect(filter.apply(postWith(tags: 'sky bikini')), isFalse);
    });

    test('隐藏与 held 默认被过滤', () {
      const filter = PostFilter();
      expect(filter.apply(postWith(hidden: true)), isFalse);
      expect(filter.apply(postWith(held: true)), isFalse);
      expect(PostFilter.all.apply(postWith(hidden: true)), isTrue);
    });
  });

  group('CropCalculator', () {
    const image = Size(1920, 1080);
    const screen = Size(1920, 1200);

    test('不裁剪时返回整图', () {
      final r = CropCalculator.compute(CropMethod.none, image, screen);
      expect(r, const Rect.fromLTWH(0, 0, 1920, 1080));
    });

    test('居中裁剪保持目标比例的居中位置', () {
      final r = CropCalculator.compute(CropMethod.center, image, screen);
      // 目标比例 1.6，图比例 1.777… → 裁左右
      expect(r.height, 1080);
      expect(r.width, closeTo(1728, 0.001));
      expect(r.left, closeTo((1920 - 1728) / 2, 0.001));
      expect(r.top, 0);
    });

    test('顶部居中裁剪从 y=0 开始', () {
      final r = CropCalculator.compute(CropMethod.topMiddle, image, screen);
      expect(r.top, 0);
      expect(r.width, closeTo(1728, 0.001));
    });

    test('给定人脸时裁剪框必须包含人脸中心', () {
      // 一个偏右下的人脸，居中裁剪会把它切掉
      final face = Rect.fromLTWH(1500, 700, 200, 200);
      final r = CropCalculator.compute(
        CropMethod.biggestFace,
        image,
        screen,
        faces: <Rect>[face],
      );
      final center = face.center;
      expect(center.dx >= r.left && center.dx <= r.right, isTrue,
          reason: '人脸横向被切掉了：center=$center rect=$r');
      expect(center.dy >= r.top && center.dy <= r.bottom, isTrue,
          reason: '人脸纵向被切掉了：center=$center rect=$r');
    });

    test('没有检测到人脸时退化为顶部居中', () {
      final withFaces = CropCalculator.compute(
        CropMethod.mostFaces,
        image,
        screen,
        faces: <Rect>[Rect.fromLTWH(100, 100, 50, 50)],
      );
      expect(withFaces.top, 0);
      final noFaces = CropCalculator.compute(CropMethod.mostFaces, image, screen);
      expect(noFaces.top, 0);
    });

    test('scaleFaces 把缩略图坐标映射回原图', () {
      final scaled = CropCalculator.scaleFaces(
        <Rect>[const Rect.fromLTWH(10, 20, 30, 40)],
        const Size(100, 200),
        const Size(1000, 1000),
      );
      expect(scaled.single, const Rect.fromLTWH(100, 100, 300, 200));
    });
  });

  group('TagDatabase', () {
    test('从 summary 串加载并解析类型与别名', () {
      final db = TagDatabase();
      db.loadFromSummaryString('1`artist_name`other_name 0`landscape 3`touhou');
      final landscape = db.search('landscape');
      expect(landscape, isNotEmpty);
      expect(landscape.first.type, TagType.none);
      expect(db.search('touhou').first.type, TagType.copyright);
    });

    test('相似度算法对前缀匹配给高分', () {
      expect(TagDatabase.similarity('landscape', 'land'), isNotNull);
      // 精确匹配应优于部分匹配
      final exact = TagDatabase.similarity('landscape', 'landscape')!;
      final partial = TagDatabase.similarity('landscape', 'land')!;
      expect(exact >= partial, isTrue);
    });
  });

  group('DailyFeature', () {
    Post post(int id, int created, String score, String tags) =>
        Post.fromXml(XmlDocument.parse(
          '<posts><post id="$id" created_at="$created" score="$score" '
          'tags="$tags" width="100" height="100" /></posts>',
        ).rootElement.childElements.first);

    test('只保留 24 小时内的帖子并取分数前三', () {
      const now = 1700000000;
      final posts = <Post>[
        post(1, now, '5', 'a'),
        post(2, now - 60, '99', 'b'),
        post(3, now - 120, '50', 'c'),
        post(4, now - 120, '1', 'd'),
        // 超过 24 小时
        post(5, now - DailyFeature.windowSeconds - 1, '500', 'e'),
      ];
      final feature = DailyFeature.build(posts);
      expect(feature.topToday.map((p) => p.id), <int>[2, 3, 1]);
    });

    test('黑名单标签会把整张图排除', () {
      const now = 1700000000;
      final posts = <Post>[
        post(1, now, '5', 'sky bikini'),
        post(2, now, '9', 'sky'),
      ];
      final feature = DailyFeature.build(posts, tagBlacklist: 'bikini');
      expect(feature.topToday.map((p) => p.id), <int>[2]);
    });

    test('出现两次以上的标签才成为精选，且每条帖子只当一次封面', () {
      const now = 1700000000;
      final posts = <Post>[
        post(1, now, '5', 'sky'),
        post(2, now, '9', 'sky'),
        post(3, now, '3', 'ocean'),
      ];
      final feature = DailyFeature.build(posts);
      final names = feature.featuredTags.map((t) => t.name);
      expect(names, contains('sky'));
      expect(names, isNot(contains('ocean')));
      // sky 的封面应取分数最高的那条
      expect(feature.featuredTags.single.cover.id, 2);
    });

    test('空列表返回空结果而不是抛异常', () {
      final feature = DailyFeature.build(const <Post>[]);
      expect(feature.topToday, isEmpty);
      expect(feature.featuredTags, isEmpty);
    });
  });
}
