import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Rect, Size;

import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import '../models/post.dart';
import 'app_settings.dart';
import 'crop.dart';
import 'face_detector.dart';
import 'history_store.dart';
import 'screen_info.dart';
import 'wallpaper_service.dart';
import 'yande_client.dart';

/// 更换壁纸的结果。
class ChangeResult {
  const ChangeResult({
    required this.success,
    required this.message,
    this.postId,
    this.filePath,
  });

  final bool success;
  final String message;
  final int? postId;
  final String? filePath;

  static const ChangeResult cancelled =
      ChangeResult(success: false, message: '没有可用的图片');
}

/// 更换壁纸时的阶段，用于向 UI 反馈进度。
enum ChangeStage {
  fetching('正在拉取列表'),
  selecting('正在挑选图片'),
  downloading('正在下载'),
  detecting('正在检测人脸'),
  cropping('正在裁剪'),
  applying('正在设置壁纸'),
  done('完成');

  const ChangeStage(this.label);
  final String label;
}

/// 壁纸引擎。移植自原 UWP 的 `BooruViewer\\Services\\AnimePersonalization.cs`（359 行）。
///
/// 原版流程（`SetBackgroundImageAsync`）：
/// 1. `Random.Next(postShuffle)` 在已加载的帖子中取一张；
/// 2. 按 `qualityLevel` 选 FileUrl / JpegUrl / SampleUrl；
/// 3. 下载并存成 `{post.Id}.jpg` 与 `{post.Id}-original.jpg`；
/// 4. `CropImageFile` 按 `CropMethod` 分派裁剪；需要人脸时先检测再 `ScaleFaces`；
/// 5. 调 `UserProfilePersonalizationSettings` 设置壁纸；
/// 6. 成功则写数据库记录。
///
/// 已移除的功能：`SetTileAsync`（Windows 磁贴）。Win11 已移除开始菜单磁贴，
/// 该功能没有移植价值。
///
/// 与原版的实现差异：
/// - 原版在 UI 线程外用手动 `BitmapDecoder` + `BitmapTransform` 裁剪；
///   这里借助 `dart:ui` 的 `instantiateImageCodec`（在 isolate 里做），
///   不引入 image 包，避免额外的大依赖。
/// - 原版只换壁纸不换锁屏时也走同一条路径；这里锁屏独立，见 `changeLockScreen`。
class WallpaperEngine {
  WallpaperEngine({
    required this.client,
    required this.settings,
    required this.history,
    AnimeFaceDetector? detector,
    WallpaperService? wallpaperService,
  })  : _detector = detector ?? AnimeFaceDetector(),
        _wallpaper = wallpaperService ?? WallpaperService();

  final YandeClient client;
  final AppSettings settings;
  final HistoryStore history;
  final AnimeFaceDetector _detector;
  final WallpaperService _wallpaper;

  final math.Random _random = math.Random();

  bool _busy = false;
  bool get isBusy => _busy;

  /// 本地工作目录，存放下载与裁剪后的图片。
  Future<Directory> _workDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}wallpapers');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 换一张壁纸。
  ///
  /// [onStage] 用于向 UI 上报当前阶段。
  /// 返回 [ChangeResult]，失败时 `message` 是可直接展示的中文原因。
  Future<ChangeResult> changeWallpaper({
    String? tags,
    void Function(ChangeStage stage)? onStage,
  }) async {
    if (_busy) {
      return const ChangeResult(success: false, message: '上一次更换尚未完成');
    }
    _busy = true;
    try {
      return await _change(tags: tags, onStage: onStage);
    } finally {
      _busy = false;
    }
  }

  /// 换锁屏。
  ///
  /// Win32 桌面没有对等的接口：UWP 的 `UserProfilePersonalizationSettings`
  /// 只在 AppContainer 里可用，注册表也查不到锁屏图片项。这里直接返回失败，
  /// 不去下载一组图片再报错——那只会让用户等半天才看到一句「不支持」。
  Future<ChangeResult> changeLockScreen({
    String? tags,
    void Function(ChangeStage stage)? onStage,
  }) async {
    return const ChangeResult(
      success: false,
      message: '当前版本不支持设置锁屏壁纸',
    );
  }

  Future<ChangeResult> _change({
    required String? tags,
    void Function(ChangeStage stage)? onStage,
  }) async {
    void stage(ChangeStage s) => onStage?.call(s);

    try {
      // ---------- 1. 取候选图片 ----------
      stage(ChangeStage.fetching);
      final queryTags = (tags ?? settings.defaultTags).trim();
      final post = await _pickPost(queryTags);
      if (post == null) {
        return const ChangeResult(success: false, message: '没有筛选出可用的图片，请检查标签与过滤设置');
      }

      // ---------- 2. 下载 ----------
      stage(ChangeStage.downloading);
      final version = _versionForQuality(settings.qualityLevel);
      final url = post.urlFor(version);
      if (url.isEmpty) {
        return ChangeResult(
          success: false,
          message: '帖子 #${post.id} 没有可下载的图片地址',
          postId: post.id,
        );
      }

      final downloaded = await _downloadBytes(url);
      if (downloaded == null) {
        return ChangeResult(
          success: false,
          message: '图片下载失败：$url',
          postId: post.id,
        );
      }

      // ---------- 3. 解码 + 人脸检测 ----------
      final method = CropMethod.fromValue(settings.cropMethodIndex);
      final screen = ScreenInfo.primaryScreenSize();

      final decoded = await _decodeSize(downloaded);
      final imageSize = decoded ?? screen;

      var faces = const <Rect>[];
      if (method == CropMethod.mostFaces || method == CropMethod.biggestFace) {
        stage(ChangeStage.detecting);
        faces = await _detectFaces(downloaded, imageSize);
      }

      // ---------- 4. 裁剪 ----------
      stage(ChangeStage.cropping);
      final cropRect = CropCalculator.compute(
        method,
        imageSize,
        screen,
        faces: faces,
      );

      final workDir = await _workDir();
      final ext = post.fileExtension.isEmpty ? 'jpg' : post.fileExtension;
      final originalPath =
          '${workDir.path}${Platform.pathSeparator}${post.id}-original.$ext';
      await File(originalPath).writeAsBytes(downloaded, flush: true);

      // 不裁剪时直接把下载到的原图交给系统：省一次完整编解码，
      // 也避免把 JPEG 字节写进 .png 文件名里。
      var croppedPath = originalPath;
      if (method != CropMethod.none) {
        croppedPath = '${workDir.path}${Platform.pathSeparator}${post.id}.png';
        final cropped = await _cropImage(downloaded, cropRect);
        if (cropped == null) {
          return ChangeResult(
            success: false,
            message: '图片裁剪失败（帖子 #${post.id}）',
            postId: post.id,
          );
        }
        await File(croppedPath).writeAsBytes(cropped, flush: true);
      }

      // ---------- 5. 应用 ----------
      stage(ChangeStage.applying);
      final applied = await _wallpaper.setWallpaperAsync(
        croppedPath,
        fitMode: settings.fitMode,
      );

      final ok = applied.isSuccess;

      // ---------- 6. 记录 ----------
      await history.add(HistoryRecord(
        postId: post.id,
        tags: post.tags,
        filePath: croppedPath,
        appliedAtUnix: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        cropMethodIndex: method.value,
        success: ok,
        message: ok ? null : applied.message,
      ));

      stage(ChangeStage.done);

      if (!ok) {
        return ChangeResult(
          success: false,
          message: '设置壁纸失败：${applied.message}',
          postId: post.id,
          filePath: croppedPath,
        );
      }

      return ChangeResult(
        success: true,
        message: '已更换壁纸：帖子 #${post.id}（${_methodLabel(method)}）',
        postId: post.id,
        filePath: croppedPath,
      );
    } catch (e) {
      return ChangeResult(success: false, message: '更换壁纸出错：$e');
    }
  }

  String _methodLabel(CropMethod m) {
    switch (m) {
      case CropMethod.none:
        return '不裁剪';
      case CropMethod.topMiddle:
        return '顶部居中';
      case CropMethod.center:
        return '居中';
      case CropMethod.biggestFace:
        return '最大人脸';
      case CropMethod.mostFaces:
        return '尽可能多人脸';
    }
  }

  PostImageVersion _versionForQuality(int qualityLevel) {
    switch (qualityLevel) {
      case 2:
        return PostImageVersion.source;
      case 1:
        return PostImageVersion.jpeg;
      default:
        return PostImageVersion.sample;
    }
  }

  /// 拉取一批帖子并随机挑一张。
  ///
  /// 原版用 `postShuffle` 作为随机窗口大小，在已加载的集合里取；
  /// 这里每次拉第一页（100 条），在过滤后的结果里随机，
  /// 并跳过最近用过的若干条，避免连续重复。
  Future<Post?> _pickPost(String tags) async {
    final query = tags.isEmpty ? '' : 'tags=${Uri.encodeQueryComponent(tags)}&';
    final uri = '/post.xml?$query';

    final page = await client.downloadPosts(uri: uri, page: 1);

    final filter = settings.filter;
    var candidates = page.items.where(filter.apply).toList();

    if (candidates.isEmpty) {
      // 首屏全被过滤掉时退一步：放宽过滤，至少要能换一张
      candidates = page.items.where((p) => p.urlFor(_versionForQuality(settings.qualityLevel)).isNotEmpty).toList();
    }
    if (candidates.isEmpty) return null;

    final recent = history.recentPostIds(30);
    final fresh = candidates.where((p) => !recent.contains(p.id)).toList();
    final pool = fresh.isEmpty ? candidates : fresh;

    final window = math.min(settings.shuffleWindow, pool.length);
    return pool[_random.nextInt(window)];
  }

  Future<Uint8List?> _downloadBytes(String url) async {
    try {
      final response = await client.downloadImage(url);
      if (response.statusCode != 200) return null;
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// 解码出图片尺寸，不做完整解码。
  Future<Size?> _decodeSize(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      codec.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  /// 检测人脸并把结果映射回原图坐标。
  ///
  /// 原版是在站点给的 preview 图上做检测、再用 `ScaleFaces` 把坐标放大回原图；
  /// 这里等价：原图长边超过 [AppConstants.faceDetectMaxDimension] 时先缩到该尺寸
  /// 再送去检测，拿到结果后按比例映射回原图。
  ///
  /// 为什么要缩：级联参数（minSize=30）是在预览图这一档尺寸下调出来的。
  /// 直接对 4000px 原图跑 `detectMultiScale` 会慢到几十秒，而且大量细小图案
  /// 会被误判成人脸，反而把裁剪框拉偏。
  Future<List<Rect>> _detectFaces(Uint8List bytes, Size fullSize) async {
    final longest = math.max(fullSize.width, fullSize.height);
    if (longest <= AppConstants.faceDetectMaxDimension) {
      return _detector.detectFromBytes(bytes);
    }

    final scale = AppConstants.faceDetectMaxDimension / longest;
    final targetWidth = (fullSize.width * scale).round().clamp(1, 1 << 20);
    final smallBytes = await _decodeResized(bytes, targetWidth);
    if (smallBytes == null) {
      // 缩放失败就退回原图检测：慢，但至少还能出结果
      return _detector.detectFromBytes(bytes);
    }

    final smallSize = await _decodeSize(smallBytes) ?? fullSize;
    final faces = await _detector.detectFromBytes(smallBytes);
    return CropCalculator.scaleFaces(faces, smallSize, fullSize);
  }

  /// 按目标宽度把图片解码成 PNG 字节，用作检测用的缩略图。
  Future<Uint8List?> _decodeResized(Uint8List bytes, int targetWidth) async {
    try {
      final codec =
          await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      codec.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return null;
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// 按裁剪矩形裁剪并输出 PNG 字节。
  ///
  /// 输出 PNG 而不是 JPEG：`dart:ui` 只能编码 PNG。Windows 的壁纸设置
  /// 认文件内容不认扩展名，所以写 `.png` 后缀是正确的做法。
  Future<Uint8List?> _cropImage(Uint8List bytes, Rect cropRect) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      codec.dispose();

      // 用 dart:ui 的 Canvas 做一次子区域重绘，等价于原版的 BitmapTransform.CroppedBitmap
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final src = cropRect.intersect(
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      );
      final dst = Rect.fromLTWH(0, 0, src.width, src.height);
      canvas.drawImageRect(image, src, dst, ui.Paint());
      final picture = recorder.endRecording();
      final croppedImage = await picture.toImage(
        src.width.round().clamp(1, 1 << 20),
        src.height.round().clamp(1, 1 << 20),
      );
      picture.dispose();
      image.dispose();

      final byteData = await croppedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      croppedImage.dispose();
      if (byteData == null) return null;
      return byteData.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// 用指定帖子直接设壁纸（用户点「设为壁纸」时走这里，不随机）。
  ///
  /// [onStage] 与 [changeWallpaper] 同义：详情页也要能让用户看到走到了哪一步，
  /// 否则点了按钮之后除了按钮变灰没有任何反馈。
  Future<ChangeResult> applyPost(
    Post post, {
    void Function(ChangeStage stage)? onStage,
  }) async {
    if (_busy) {
      return const ChangeResult(success: false, message: '上一次更换尚未完成');
    }
    _busy = true;
    void stage(ChangeStage s) => onStage?.call(s);
    try {
      stage(ChangeStage.downloading);
      final version = _versionForQuality(settings.qualityLevel);
      final url = post.urlFor(version);
      if (url.isEmpty) {
        return ChangeResult(
          success: false,
          message: '该帖子没有可用的图片地址',
          postId: post.id,
        );
      }

      final bytes = await _downloadBytes(url);
      if (bytes == null) {
        return ChangeResult(success: false, message: '图片下载失败', postId: post.id);
      }

      final method = CropMethod.fromValue(settings.cropMethodIndex);
      final screen = ScreenInfo.primaryScreenSize();
      final decoded = await _decodeSize(bytes);
      final imageSize = decoded ?? screen;

      var faces = const <Rect>[];
      if (method == CropMethod.mostFaces || method == CropMethod.biggestFace) {
        stage(ChangeStage.detecting);
        faces = await _detectFaces(bytes, imageSize);
      }

      stage(ChangeStage.cropping);
      final cropRect =
          CropCalculator.compute(method, imageSize, screen, faces: faces);

      final workDir = await _workDir();
      final ext = post.fileExtension.isEmpty ? 'jpg' : post.fileExtension;
      var croppedPath = '${workDir.path}${Platform.pathSeparator}${post.id}-original.$ext';
      await File(croppedPath).writeAsBytes(bytes, flush: true);

      if (method != CropMethod.none) {
        croppedPath = '${workDir.path}${Platform.pathSeparator}${post.id}.png';
        final cropped = await _cropImage(bytes, cropRect);
        if (cropped == null) {
          return ChangeResult(
            success: false,
            message: '图片裁剪失败',
            postId: post.id,
          );
        }
        await File(croppedPath).writeAsBytes(cropped, flush: true);
      }

      stage(ChangeStage.applying);
      final applied = await _wallpaper.setWallpaperAsync(
        croppedPath,
        fitMode: settings.fitMode,
      );
      final ok = applied.isSuccess;

      await history.add(HistoryRecord(
        postId: post.id,
        tags: post.tags,
        filePath: croppedPath,
        appliedAtUnix: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        cropMethodIndex: method.value,
        success: ok,
        message: ok ? null : applied.message,
      ));

      stage(ChangeStage.done);

      return ChangeResult(
        success: ok,
        message: ok ? '已设为壁纸（帖子 #${post.id}）' : '设置失败：${applied.message}',
        postId: post.id,
        filePath: croppedPath,
      );
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _detector.dispose();
    client.dispose();
  }
}
