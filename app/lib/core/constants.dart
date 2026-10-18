/// 应用级常量。对应原 UWP 版的 `YandeClient` / `AnimePersonalization` 里的硬编码值。
class AppConstants {
  AppConstants._();

  /// 默认站点地址。用户可在设置中改为其他 yande 系站（如 konachan）。
  static const String defaultHost = 'https://yande.re';

  /// 密码哈希盐。yande 系站使用 salt 替换占位符后做 SHA1。
  /// 原文：`salt.Replace("your-password", password)`
  static const String defaultPasswordHashSalt = 'choujin-steiner--your-password--';

  /// 帖子列表每页条数。原 `Posts.limit = 100`。
  static const int postsPageLimit = 100;

  /// 人脸检测缩放因子。原 `DetechFromBufferAsync` 固定 1.05。
  static const double faceDetectScaleFactor = 1.05;

  /// 人脸检测默认最小邻居数。
  static const int faceDetectMinNeighbors = 5;

  /// 人脸检测默认最小尺寸（像素）。
  static const int faceDetectMinSize = 30;

  /// 送去做人脸检测的图片长边上限。
  ///
  /// 级联模型和 minSize=30 这套参数是在长边约 1024 的预览图上调出来的：
  /// 直接拿 4000px 的原图去跑 detectMultiScale 会慢到几十秒，
  /// 而且远处的细小图案会被当成脸大量误检。
  static const int faceDetectMaxDimension = 1024;

  /// 级联模型文件名，随 assets 打包。
  static const String cascadeAsset = 'assets/lbpcascade_animeface.xml';

  /// 下载图片时使用的 User-Agent。原版为 `Mozilla/5.0 (Windows NT 6.3; WOW64; Trident/7.0; rv:11.0) like Gecko`。
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// 默认标签黑名单。
  static const String defaultTagBlacklist = 'bikini buruma ass pantsu bra torn_clothes no_pan';

  /// 可选的每页图片拉取上限（防止 settings 里填错导致内存爆炸）。
  static const int maxShuffleWindow = 200;
}
