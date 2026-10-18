import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/services.dart' show rootBundle;
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';

/// 动漫人脸检测器。移植自原 UWP 项目的 C++/WinRT 组件
/// `Imaging\\AnimeFaceDetector.cpp`（111 行）。
///
/// 原版用 `cv::CascadeClassifier` 加载 `lbpcascade_animeface.xml`，
/// 对传入的 BitmapFrame 做 `detectMultiScale`：
///
/// ```cpp
/// cascade.load("lbpcascade_animeface.xml");
/// cascade.detectMultiScale(im, faces, scaleFactor, minNeighbors,
///                          CV_HAAR_SCALE_IMAGE, cv::Size(minSize, minSize));
/// ```
///
/// 这里用 opencv_dart 复刻，参数保持一致（scaleFactor=1.05 / minNeighbors=5 / minSize=30）。
///
/// 移植差异：
/// - OpenCV 4 移除了 `CV_HAAR_SCALE_IMAGE`（该常量在 3.x 起由内部实现接管），
///   因此传 `flags = 0`，行为等价。
/// - 级联模型打进了 Flutter asset，需要先落盘，因为 OpenCV 的
///   `CascadeClassifier.load` 只认文件路径。
class AnimeFaceDetector {
  AnimeFaceDetector();

  cv.CascadeClassifier? _cascade;
  bool _loading = false;
  String? _cascadePath;

  bool get isReady => _cascade != null;

  /// 惰性加载级联模型；可重复调用。
  Future<bool> ensureLoaded() async {
    if (_cascade != null) return true;
    if (_loading) {
      // 已经有人在加载，等它完成
      for (var i = 0; i < 100 && _loading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return _cascade != null;
    }

    _loading = true;
    try {
      final path = await _materializeCascade();
      final cascade = cv.CascadeClassifier.empty();
      final ok = cascade.load(path);
      if (!ok) {
        cascade.dispose();
        return false;
      }
      _cascade = cascade;
      return true;
    } catch (_) {
      return false;
    } finally {
      _loading = false;
    }
  }

  /// 把打包的级联 XML 写到应用支持目录，返回绝对路径。
  Future<String> _materializeCascade() async {
    if (_cascadePath != null) return _cascadePath!;

    final dir = await getApplicationSupportDirectory();
    final target = File('${dir.path}${Platform.pathSeparator}lbpcascade_animeface.xml');

    if (!await target.exists()) {
      final data = await rootBundle.load(AppConstants.cascadeAsset);
      await target.parent.create(recursive: true);
      await target.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }

    _cascadePath = target.path;
    return target.path;
  }

  /// 对图片字节做检测，返回 **该图片自身坐标系** 下的人脸矩形。
  ///
  /// [imageBytes] 可以是原图，也可以是缩略图 —— 原版用 preview 图检测再
  /// 用 `ScaleFaces` 映射回原图，这里把映射交给调用方（见 `CropCalculator.scaleFaces`）。
  ///
  /// 返回空列表表示未检测到人脸，调用方应退化为 TopMiddle 裁剪。
  Future<List<Rect>> detectFromBytes(
    Uint8List imageBytes, {
    double scaleFactor = AppConstants.faceDetectScaleFactor,
    int minNeighbors = AppConstants.faceDetectMinNeighbors,
    int minSize = AppConstants.faceDetectMinSize,
  }) async {
    if (!await ensureLoaded()) return const <Rect>[];
    final cascade = _cascade;
    if (cascade == null) return const <Rect>[];

    cv.Mat? mat;
    cv.VecRect? rects;
    try {
      // LBP 级联只吃灰度图，转灰度同时提速
      mat = cv.imdecode(imageBytes, cv.IMREAD_GRAYSCALE);
      if (mat.isEmpty) return const <Rect>[];

      rects = cascade.detectMultiScale(
        mat,
        scaleFactor: scaleFactor,
        minNeighbors: minNeighbors,
        minSize: (minSize, minSize),
      );

      return <Rect>[
        for (final r in rects.toList())
          Rect.fromLTWH(
            r.x.toDouble(),
            r.y.toDouble(),
            r.width.toDouble(),
            r.height.toDouble(),
          ),
      ];
    } catch (_) {
      return const <Rect>[];
    } finally {
      rects?.dispose();
      mat?.dispose();
    }
  }

  void dispose() {
    _cascade?.dispose();
    _cascade = null;
  }
}
