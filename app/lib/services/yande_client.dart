import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../core/constants.dart';
import '../models/post.dart';
import '../models/posts_page.dart';
import '../models/tag.dart';

/// 投票类型。对应原 `YandeClient.VoteType`。
enum VoteType {
  bad(-1),
  none(0),
  good(1),
  great(2),
  favorite(3);

  const VoteType(this.value);
  final int value;

  /// 界面显示用的中文名。
  String get label => switch (this) {
        VoteType.bad => '差',
        VoteType.none => '取消',
        VoteType.good => '不错',
        VoteType.great => '很好',
        VoteType.favorite => '收藏',
      };
}

/// 登录结果。
class SignInResult {
  const SignInResult({required this.success, this.userId, this.message});

  final bool success;
  final String? userId;
  final String? message;
}

/// yande 系图站的 HTTP 客户端。
///
/// 移植自原 UWP 项目 `BooruViewer\\Services\\YandeClient.cs`（250 行）。
/// 原版用 `Windows.Web.Http.HttpClient` + `HtmlAgilityPack`；
/// Flutter 侧改用 `http` + `html` 包，接口语义保持一致。
///
/// 注意：原版所有方法都是 **静态** 且 HOST 是静态常量；
/// 这里改成实例，`host` 可变，以便支持用户自定义站点（如 konachan）。
class YandeClient {
  YandeClient({
    String? host,
    http.Client? httpClient,
  })  : _host = host ?? AppConstants.defaultHost,
        _http = httpClient ?? http.Client();

  String _host;
  final http.Client _http;

  String get host => _host;
  set host(String value) => _host = value.endsWith('/')
      ? value.substring(0, value.length - 1)
      : value;

  void dispose() => _http.close();

  /// 单次请求的超时。
  ///
  /// 必须显式设置：`http` 包底层是 `dart:io` 的 `HttpClient`，连接超时默认无限，
  /// 直连 yande.re 这种被墙的站点时会卡在 TCP 握手上一分多钟，界面上就是一直转圈。
  /// 12 秒足够正常的跨境代理往返，又不会让用户对着转圈等到放弃。
  static const Duration timeout = Duration(seconds: 12);

  Map<String, String> _headers({String? referer}) => <String, String>{
        'User-Agent': AppConstants.userAgent,
        'Referer': ?referer,
      };

  /// 统一包装 GET/POST：加超时，并把各种底层异常翻译成人能看懂的一句话。
  ///
  /// 原版跑在 UWP 里，网络异常由系统抛；桌面版要自己把
  /// `SocketException` / `TimeoutException` / `HandshakeException`
  /// 变成「连不上站点，检查代理」这种用户能行动的信息。
  Future<http.Response> _send(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw YandeException('连接站点超时（12 秒），请检查网络或代理设置');
    } on SocketException catch (e) {
      // e.message 常常自带句号（如「远程计算机拒绝网络连接。」），
      // 直接接中文句号会出现「。。」，先剥掉尾部标点再拼。
      final detail = e.message.replaceAll(RegExp(r'[。\.\s]+$'), '');
      throw YandeException('无法连接站点：$detail。请检查网络或代理设置');
    } on HandshakeException {
      throw YandeException('与站点的 TLS 握手失败，代理可能没有正确转发 HTTPS');
    } on http.ClientException catch (e) {
      final detail = e.message;
      throw YandeException('请求失败：$detail');
    }
  }

  /// 计算 yande 系站的密码哈希：把盐里的 `your-password` 换成明文密码，再取 SHA1。
  ///
  /// 原版：
  /// ```csharp
  /// string salt = PasswordHashSalt.Replace("your-password", password);
  /// return sha1(salt);
  /// ```
  static String hashPassword(String password, String salt) {
    final effectiveSalt = salt.replaceAll('your-password', password);
    return sha1.convert(utf8.encode(effectiveSalt)).toString();
  }

  /// 拉取一页帖子。
  ///
  /// [uri] 是站点查询路径（如 `/post.xml?tags=xxx`）。
  /// 原版拼接为 `{HOST}{uri}&page={page}&limit={limit}`。
  Future<PostsPage> downloadPosts({
    required String uri,
    required int page,
    int limit = AppConstants.postsPageLimit,
  }) async {
    final url = '$_host$uri&page=$page&limit=$limit';
    final response = await _send(
      () => _http.get(Uri.parse(url), headers: _headers()),
    );
    if (response.statusCode != 200) {
      throw YandeException('拉取帖子失败：HTTP ${response.statusCode}');
    }
    return parsePostsXml(response.body);
  }

  /// 解析 `/post.xml` 响应。
  ///
  /// 原版结构：
  /// `<posts count="123" offset="0"><post .../><post .../></posts>`
  static PostsPage parsePostsXml(String body) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(body);
    } catch (e) {
      throw YandeException('帖子 XML 解析失败：$e');
    }

    final root = doc.rootElement;
    final totalCount = int.tryParse(root.getAttribute('count') ?? '') ?? 0;
    final offset = int.tryParse(root.getAttribute('offset') ?? '') ?? 0;

    final items = <Post>[];
    for (final element in root.findElements('post')) {
      items.add(Post.fromXml(element));
    }

    return PostsPage(items: items, totalCount: totalCount, offset: offset);
  }

  /// 拉取标签数据库。
  ///
  /// 原版 `GET {HOST}/tag/summary.json`，响应形如
  /// `{"version": 123, "data": "1\`artist_name\`... 3\`copyright\`..."}`
  Future<String> downloadTagSummary() async {
    final response = await _send(
      () => _http.get(
        Uri.parse('$_host/tag/summary.json'),
        headers: _headers(),
      ),
    );
    if (response.statusCode != 200) {
      throw YandeException('拉取标签库失败：HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is String) return data;
    }
    throw YandeException('标签库格式异常');
  }

  /// 拉取并解析标签库到 [TagDatabase]。
  Future<TagDatabase> fetchTagDatabase() async {
    final data = await downloadTagSummary();
    final db = TagDatabase();
    db.loadFromSummaryString(data);
    return db;
  }

  /// 取登录页里的 CSRF token。
  ///
  /// 原版用 HtmlAgilityPack 的 `//meta[@name='csrf-token']` 的 content。
  Future<String?> fetchAuthenticityToken() async {
    final response = await _send(
      () => _http.get(
        Uri.parse('$_host/user/login'),
        headers: _headers(),
      ),
    );
    if (response.statusCode != 200) return null;
    final doc = html_parser.parse(response.body);
    final metas = doc.querySelectorAll('meta[name="csrf-token"]');
    if (metas.isEmpty) return null;
    return metas.first.attributes['content'];
  }

  /// 登录。成功时返回用户 ID。
  ///
  /// 原版表单字段：
  /// `authenticity_token`, `url`, `user[name]`, `user[password]`, `commit=Login`
  Future<SignInResult> signIn(String userName, String password) async {
    final token = await fetchAuthenticityToken();
    if (token == null) {
      return const SignInResult(success: false, message: '无法取得登录令牌（csrf-token）');
    }

    final response = await _send(
      () => _http.post(
        Uri.parse('$_host/user/authenticate'),
        headers: {
          ..._headers(referer: '$_host/user/login'),
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: <String, String>{
          'authenticity_token': token,
          'url': '',
          'user[name]': userName,
          'user[password]': password,
          'commit': 'Login',
        },
      ),
    );

    if (response.statusCode != 200 && response.statusCode != 302) {
      return SignInResult(
        success: false,
        message: '登录请求失败：HTTP ${response.statusCode}',
      );
    }

    // 原版从响应里找 "/user/show/" 之后、'">My Profile<' 之前的片段作为 UserID
    final body = response.body;
    final marker = '/user/show/';
    final start = body.indexOf(marker);
    if (start == -1) {
      return const SignInResult(success: false, message: '用户名或密码不正确');
    }
    final idStart = start + marker.length;
    final idEnd = body.indexOf('">My Profile<', idStart);
    if (idEnd == -1 || idEnd <= idStart) {
      return const SignInResult(success: false, message: '登录成功但无法解析用户 ID');
    }

    final userId = body.substring(idStart, idEnd).trim();
    if (userId.isEmpty) {
      return const SignInResult(success: false, message: '登录成功但用户 ID 为空');
    }
    return SignInResult(success: true, userId: userId);
  }

  /// 投票。对应原 `VoteAsync`。
  ///
  /// 原版：`POST {HOST}/post/vote.xml?login={u}&password_hash={h}&id={id}&score={score}`
  Future<bool> vote({
    required String userName,
    required String passwordHash,
    required int postId,
    required VoteType vote,
  }) async {
    final uri = Uri.parse('$_host/post/vote.xml').replace(queryParameters: {
      'login': userName,
      'password_hash': passwordHash,
      'id': '$postId',
      'score': '${vote.value}',
    });

    final response = await _send(
      () => _http.post(uri, headers: _headers()),
    );
    if (response.statusCode != 200) return false;
    // 站点对投票成功的响应包含 <success>true</success> 或直接给出新分值
    final body = response.body;
    return body.contains('<success>true</success>') ||
        body.contains('true') ||
        !body.contains('error');
  }

  /// 查询当前投票状态。对应原 `GetVoteAsync`。
  ///
  /// 原版判定：响应文本包含 "3" 即为 Favorite。这里保持同样（略显粗糙但兼容）的判定。
  Future<VoteType> fetchVote({
    required String userName,
    required String passwordHash,
    required int postId,
  }) async {
    final uri = Uri.parse('$_host/post/vote.xml').replace(queryParameters: {
      'login': userName,
      'password_hash': passwordHash,
      'id': '$postId',
    });

    final response = await _send(
      () => _http.post(uri, headers: _headers()),
    );
    if (response.statusCode != 200) return VoteType.none;

    final body = response.body;
    // 站点返回形如 <vote>3</vote>；退化为原版的 contains("3") 判定
    final match = RegExp(r'<vote>\s*(-?\d+)\s*</vote>').firstMatch(body);
    if (match != null) {
      final v = int.tryParse(match.group(1) ?? '');
      if (v != null) {
        for (final t in VoteType.values) {
          if (t.value == v) return t;
        }
      }
    }
    if (body.contains('3')) return VoteType.favorite;
    return VoteType.none;
  }

  /// 收藏 / 取消收藏。原版的 `AddFavoriteAsync` / `RemoveFavoriteAsync`。
  Future<bool> setFavorite({
    required String userName,
    required String passwordHash,
    required int postId,
    required bool favorite,
  }) =>
      vote(
        userName: userName,
        passwordHash: passwordHash,
        postId: postId,
        vote: favorite ? VoteType.favorite : VoteType.none,
      );

  /// 构造图片下载地址。原版下载时会带 Referer 头，否则站点会拒绝。
  Future<http.Response> downloadImage(String url) => _send(
        () => _http.get(
          Uri.parse(url),
          headers: _headers(referer: '$_host/'),
        ),
      );
}

/// 站点交互异常。
class YandeException implements Exception {
  YandeException(this.message);
  final String message;

  @override
  String toString() => 'YandeException: $message';
}
