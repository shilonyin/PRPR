import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prpr/services/yande_client.dart';

/// 网络解析层测试。
///
/// 为什么补这些：评审 P0 指出投票/收藏的成功判定不可靠——原实现把任何不含
/// "error" 的 200 响应都判成功，登录过期返回的 HTML 也算投票成功。这里把
/// 判定收紧成纯函数 [YandeClient.parseVoteSuccess]，并用 MockClient 注入
/// 构造函数（早已支持的 httpClient 缝）覆盖 fetchVote 的正则解析，确保
/// 「含 3 的 HTML 被误判成收藏」这类回归被钉死。
///
/// 风格与 prpr_test.dart 一致：只测纯逻辑与可注入的网络解析，不碰平台层。
void main() {
  group('parsePostsXml', () {
    test('正常解析 count / offset / 帖子列表', () {
      final page = YandeClient.parsePostsXml(
        '<posts count="42" offset="10"><post id="1"/><post id="2"/></posts>',
      );
      expect(page.totalCount, 42);
      expect(page.offset, 10);
      expect(page.items.length, 2);
      expect(page.items.first.id, 1);
    });

    test('坏 XML 抛 YandeException 而不是静默返回空', () {
      expect(
        () => YandeClient.parsePostsXml('<posts><post></posts>'),
        throwsA(isA<YandeException>()),
      );
    });

    test('count 缺失时退化到 0，不影响帖子解析', () {
      final page = YandeClient.parsePostsXml(
        '<posts offset="5"><post id="7"/></posts>',
      );
      expect(page.totalCount, 0);
      expect(page.offset, 5);
      expect(page.items.single.id, 7);
    });
  });

  group('hashPassword', () {
    // 已知 SHA1 向量：盐里的 your-password 被替换成明文后再取 SHA1。
    test('占位符替换为明文（sha1("abc")）', () {
      expect(
        YandeClient.hashPassword('abc', 'your-password'),
        'a9993e364706816aba3e25717850c26c9cd0d89d',
      );
    });

    test('空密码（sha1("")）', () {
      expect(
        YandeClient.hashPassword('', 'your-password'),
        'da39a3ee5e6b4b0d3255bfef95601890afd80709',
      );
    });

    test('盐前后有其它字符（sha1("salt-abc-end")）', () {
      expect(
        YandeClient.hashPassword('abc', 'salt-your-password-end'),
        'a6a1b23e8d11eba05184f8e54eb2b5bb94a3267a',
      );
    });

    test('占位符出现多次时全部替换（sha1("abcabc")）', () {
      expect(
        YandeClient.hashPassword('abc', 'your-passwordyour-password'),
        'f8c1d87006fbf7e5cc4b026c3138bc046883dc71',
      );
    });
  });

  group('parseVoteSuccess', () {
    test('成功 XML <success>true</success>', () {
      expect(YandeClient.parseVoteSuccess('<success>true</success>'), isTrue);
      expect(
        YandeClient.parseVoteSuccess(
          '<?xml version="1.0"?><response><success> true </success></response>',
        ),
        isTrue,
      );
    });

    test('成功 JSON {"success":true}', () {
      expect(YandeClient.parseVoteSuccess('{"success":true}'), isTrue);
      expect(YandeClient.parseVoteSuccess('{"success": true}'), isTrue);
    });

    test('明确分值响应也算成功', () {
      expect(YandeClient.parseVoteSuccess('<vote>3</vote>'), isTrue);
      expect(YandeClient.parseVoteSuccess('<score>-1</score>'), isTrue);
      expect(YandeClient.parseVoteSuccess('{"score":3}'), isTrue);
    });

    test('含 error 的响应一律 false', () {
      expect(YandeClient.parseVoteSuccess('<error>invalid</error>'), isFalse);
      expect(YandeClient.parseVoteSuccess('{"error":"bad"}'), isFalse);
      expect(YandeClient.parseVoteSuccess('{"success":false}'), isFalse);
    });

    test('登录页 HTML 不算成功（P0 回归）', () {
      expect(
        YandeClient.parseVoteSuccess(
          '<html><body>Please log in to vote.</body></html>',
        ),
        isFalse,
      );
      // 含 true 字样但不是 success 字段，也不能算成功
      expect(
        YandeClient.parseVoteSuccess('<html>a true story</html>'),
        isFalse,
      );
    });

    test('空响应 / 纯空白 / 裸 true 一律 false', () {
      expect(YandeClient.parseVoteSuccess(''), isFalse);
      expect(YandeClient.parseVoteSuccess('   '), isFalse);
      expect(YandeClient.parseVoteSuccess('true'), isFalse);
    });
  });

  group('fetchVote（MockClient 注入）', () {
    YandeClient clientWith(String body, {int status = 200}) {
      final mock = MockClient((request) async => http.Response(body, status));
      return YandeClient(host: 'https://yande.re', httpClient: mock);
    }

    Future<VoteType> fetch(YandeClient c) => c.fetchVote(
          userName: 'u',
          passwordHash: 'h',
          postId: 1,
        );

    test('<vote>3</vote> → favorite', () async {
      expect(await fetch(clientWith('<vote>3</vote>')), VoteType.favorite);
    });

    test('各分值映射到对应枚举', () async {
      expect(await fetch(clientWith('<vote>-1</vote>')), VoteType.bad);
      expect(await fetch(clientWith('<vote>0</vote>')), VoteType.none);
      expect(await fetch(clientWith('<vote>1</vote>')), VoteType.good);
      expect(await fetch(clientWith('<vote>2</vote>')), VoteType.great);
    });

    test('含 3 的 HTML 不再误判成收藏（P0 回归）', () async {
      expect(
        await fetch(clientWith('<html>post 3 says hello</html>')),
        VoteType.none,
      );
    });

    test('非 200 返回 none', () async {
      expect(await fetch(clientWith('', status: 500)), VoteType.none);
    });
  });

  group('vote（MockClient 注入）', () {
    test('成功 XML → true，登录页 HTML → false', () async {
      Future<bool> voteWith(String body) {
        final mock = MockClient((request) async => http.Response(body, 200));
        final c = YandeClient(host: 'https://yande.re', httpClient: mock);
        return c.vote(
          userName: 'u',
          passwordHash: 'h',
          postId: 1,
          vote: VoteType.favorite,
        );
      }

      expect(await voteWith('<success>true</success>'), isTrue);
      expect(await voteWith('<html>please log in</html>'), isFalse);
    });
  });
}
