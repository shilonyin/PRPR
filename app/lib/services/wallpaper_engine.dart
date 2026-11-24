import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:opencv_dart/opencv.dart' as cv;
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

      // ---------- 2. 下载（流式落盘） ----------
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

      final method = CropMethod.fromValue(settings.cropMethodIndex);
      final screen = ScreenInfo.primaryScreenSize();
      final workDir = await _workDir();
      final ext = post.fileExtension.isEmpty ? 'jpg' : post.fileExtension;
      final originalPath =
          '${workDir.path}${Platform.pathSeparator}${post.id}-original.$ext';

      // 流式下载直接写原图文件：慢代理下大图不再被 12s 整体超时截断。
      final downloaded =
          await client.downloadImageToFile(url, File(originalPath));
      if (!downloaded) {
        return ChangeResult(
          success: false,
          message: '图片下载失败：$url',
          postId: post.id,
        );
      }

      // ---------- 3. 解码 + 人脸检测 + 裁剪 + JPEG（单 isolate，一次全量解码） ----------
      // 不裁剪时直接把下载到的原图交给系统：省一次完整编解码。
      var croppedPath = originalPath;
      if (method != CropMethod.none) {
        final needFaces =
            method == CropMethod.mostFaces || method == CropMethod.biggestFace;
        if (needFaces) stage(ChangeStage.detecting);
        final cascadePath =
            needFaces ? await _detector.ensureCascadeFile() : null;
        stage(ChangeStage.cropping);
        croppedPath = '${workDir.path}${Platform.pathSeparator}${post.id}.jpg';
        final result = await Isolate.run(
          () => _processInIsolate((
            originalPath: originalPath,
            croppedPath: croppedPath,
            methodValue: method.value,
            screenW: screen.width,
            screenH: screen.height,
            cascadePath: cascadePath,
          )),
        );
        if (!result.ok) {
          return ChangeResult(
            success: false,
            message: '图片裁剪失败（帖子 #${post.id}）',
            postId: post.id,
          );
        }
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
      // 首屏全被过滤掉时退一步：放宽分级 / 横竖 / 可见性 / held，至少要能换一张；
      // 但黑名单始终保留——设置页承诺「黑名单不会出现在任何列表」，兜底也不能破例。
      // copyWith 不覆盖 tagBlacklist，用户的黑名单原样带进放宽后的筛选。
      final relaxed = filter.copyWith(
        isFilterSafe: true,
        isFilterQuestionable: true,
        isFilterExplicit: true,
        isFilterHorizontal: true,
        isFilterVertical: true,
        isFilterAllowHidden: true,
        isFilterAllowHeld: true,
      );
      final version = _versionForQuality(settings.qualityLevel);
      candidates = page.items
          .where((p) => relaxed.apply(p) && p.urlFor(version).isNotEmpty)
          .toList();
    }
    if (candidates.isEmpty) return null;

    final recent = history.recentPostIds(30);
    final fresh = candidates.where((p) => !recent.contains(p.id)).toList();
    final pool = fresh.isEmpty ? candidates : fresh;

    final window = math.min(settings.shuffleWindow, pool.length);
    return pool[_random.nextInt(window)];
  }

  /// 裁剪输出 JPEG 质量。Windows 的 SystemParametersInfo 认 jpg，
  /// 90 在肉眼无损与文件体积之间取平衡（原先 PNG 无损但编码慢、体积大）。
  static const int _jpegQuality = 90;

  /// 在单个后台 isolate 里完成「解码 → 尺寸 → 人脸检测 → 裁剪 → JPEG 写盘」。
  ///
  /// 为什么合并：原先 _decodeSize 全量解码一次拿尺寸、_cropImage 再全量解码
  /// 一次裁剪，外加 PNG 重编码与缩略图 PNG→cv.imdecode 往返。合并后整条管线
  /// 只对全分辨率图像解码 **一次**（cv.imdecode），检测直接在已解码的 Mat 上
  /// 做（必要时 cv.resize 出缩略图，不再二次解码全图），裁剪用 Mat.region，
  /// 输出 cv.imwrite JPEG。crop.dart 的几何算法保持纯函数不动，其输出的
  /// cropRect 在这里换算成整数 ROI 交给 cv 裁剪。
  ///
  /// 入参全是平坦数据（路径/数值/字符串），可安全跨 isolate；返回 record 同理。
  /// 原图已由流式下载写在 originalPath，这里直接读文件，避免主 isolate 持有大图字节。
  static ({bool ok, String? error}) _processInIsolate(
    ({
      String originalPath,
      String croppedPath,
      int methodValue,
      double screenW,
      double screenH,
      String? cascadePath,
    }) args,
  ) {
    cv.Mat? mat;
    cv.Mat? roi;
    cv.VecI32? params;
    try {
      final bytes = File(args.originalPath).readAsBytesSync();
      mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
      if (mat.isEmpty) return (ok: false, error: '图片解码失败');
      final imgW = mat.cols;
      final imgH = mat.rows;
      final method = CropMethod.fromValue(args.methodValue);

      var faces = const <Rect>[];
      final needFaces =
          method == CropMethod.mostFaces || method == CropMethod.biggestFace;
      if (needFaces && args.cascadePath != null) {
        faces = _detectFacesOnMat(mat, args.cascadePath!, imgW, imgH);
      }

      final cropRect = CropCalculator.compute(
        method,
        Size(imgW.toDouble(), imgH.toDouble()),
        Size(args.screenW, args.screenH),
        faces: faces,
      );

      // 夹紧到图内并取整：Mat.region 断言 right<=cols、bottom<=rows，
      // 浮点裁剪框可能越界，这里等价于原 _cropImage 的 intersect 处理。
      final src = cropRect
          .intersect(Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble()));
      final x = src.left.round().clamp(0, imgW - 1).toInt();
      final y = src.top.round().clamp(0, imgH - 1).toInt();
      final w = src.width.round().clamp(1, imgW - x).toInt();
      final h = src.height.round().clamp(1, imgH - y).toInt();
      roi = mat.region(cv.Rect(x, y, w, h));

      params = cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, _jpegQuality]);
      final ok = cv.imwrite(args.croppedPath, roi, params: params);
      return ok ? (ok: true, error: null) : (ok: false, error: 'JPEG 写盘失败');
    } catch (e) {
      return (ok: false, error: '$e');
    } finally {
      params?.dispose();
      roi?.dispose();
      mat?.dispose();
    }
  }

  /// 在已解码的全图 Mat 上检测人脸，并把坐标映射回原图。
  ///
  /// 长边超过 [AppConstants.faceDetectMaxDimension] 时先 cv.resize 出缩略图
  /// 再检测（级联参数是在预览图尺寸下调出来的，直接跑 4000px 原图会慢且误检），
  /// 拿到结果后按比例放大回原图——等价于原 _detectFaces + CropCalculator.scaleFaces。
  static List<Rect> _detectFacesOnMat(
    cv.Mat mat,
    String cascadePath,
    int imgW,
    int imgH,
  ) {
    final longest = math.max(imgW, imgH);
    cv.Mat? thumb;
    try {
      cv.Mat detectMat = mat;
      var sx = 1.0;
      var sy = 1.0;
      if (longest > AppConstants.faceDetectMaxDimension) {
        final scale = AppConstants.faceDetectMaxDimension / longest;
        final tw = (imgW * scale).round().clamp(1, 1 << 20).toInt();
        final th = (imgH * scale).round().clamp(1, 1 << 20).toInt();
        thumb = cv.resize(mat, (tw, th), interpolation: cv.INTER_AREA);
        detectMat = thumb;
        sx = imgW / tw;
        sy = imgH / th;
      }
      final flat = AnimeFaceDetector.detectOnDecodedMat(
        detectMat,
        cascadePath: cascadePath,
      );
      return <Rect>[
        for (var i = 0; i + 3 < flat.length; i += 4)
          Rect.fromLTWH(
            flat[i] * sx,
            flat[i + 1] * sy,
            flat[i + 2] * sx,
            flat[i + 3] * sy,
          ),
      ];
    } catch (_) {
      return const <Rect>[];
    } finally {
      thumb?.dispose();
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

      final method = CropMethod.fromValue(settings.cropMethodIndex);
      final screen = ScreenInfo.primaryScreenSize();
      final workDir = await _workDir();
      final ext = post.fileExtension.isEmpty ? 'jpg' : post.fileExtension;
      final originalPath =
          '${workDir.path}${Platform.pathSeparator}${post.id}-original.$ext';

      final downloaded =
          await client.downloadImageToFile(url, File(originalPath));
      if (!downloaded) {
        return ChangeResult(success: false, message: '图片下载失败', postId: post.id);
      }

      var croppedPath = originalPath;
      if (method != CropMethod.none) {
        final needFaces =
            method == CropMethod.mostFaces || method == CropMethod.biggestFace;
        if (needFaces) stage(ChangeStage.detecting);
        final cascadePath =
            needFaces ? await _detector.ensureCascadeFile() : null;
        stage(ChangeStage.cropping);
        croppedPath = '${workDir.path}${Platform.pathSeparator}${post.id}.jpg';
        final result = await Isolate.run(
          () => _processInIsolate((
            originalPath: originalPath,
            croppedPath: croppedPath,
            methodValue: method.value,
            screenW: screen.width,
            screenH: screen.height,
            cascadePath: cascadePath,
          )),
        );
        if (!result.ok) {
          return ChangeResult(
            success: false,
            message: '图片裁剪失败',
            postId: post.id,
          );
        }
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
