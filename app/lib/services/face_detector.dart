import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/services.dart' show rootBundle;
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';

/// 动漫人脸检测器。移植自原 UWP 项目的 C++/WinRT 组件
/// `Imaging\AnimeFaceDetector.cpp`（111 行）。
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
/// - **检测跑在后台 isolate**。`detectMultiScale` 是同步 FFI 调用，在 4000px
///   的图上动辄几百毫秒，放主 isolate 会把「正在检测人脸」的进度指示冻住。
///   opencv 的 FFI 在后台 isolate 可用（已用 `Isolate.run` 验证），所以整段
///   解码 + 检测都搬过去；`rootBundle` / `path_provider` 在后台 isolate 不可用，
///   因此级联文件路径由主 isolate 先算好再传进去。
class AnimeFaceDetector {
  AnimeFaceDetector();

  String? _cascadePath;
  bool _materializing = false;

  /// 级联文件是否已落盘（不代表后台 isolate 里已加载）。
  bool get isReady => _cascadePath != null;

  /// 确保级联 XML 已写进应用支持目录，返回其绝对路径；失败返回 null。
  /// 可重复调用，路径会被缓存。
  Future<String?> ensureCascadeFile() async {
    if (_cascadePath != null) return _cascadePath;
    if (_materializing) {
      // 已经有人在写，等它完成
      for (var i = 0; i < 100 && _materializing; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return _cascadePath;
    }

    _materializing = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final target =
          File('${dir.path}${Platform.pathSeparator}lbpcascade_animeface.xml');
      if (!await target.exists()) {
        final data = await rootBundle.load(AppConstants.cascadeAsset);
        await target.parent.create(recursive: true);
        await target.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
      _cascadePath = target.path;
      return target.path;
    } catch (_) {
      return null;
    } finally {
      _materializing = false;
    }
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
    final path = await ensureCascadeFile();
    if (path == null) return const <Rect>[];

    // 只传「平坦的 double 数组」而不是 List<Rect>：跨 isolate 传 dart:ui 的
    // Rect 虽然多半能过，但没有任何文档保证；四个 double 一组最稳。
    final flat = await Isolate.run<Float64List>(
      () => _detectInIsolate(
        cascadePath: path,
        bytes: imageBytes,
        scaleFactor: scaleFactor,
        minNeighbors: minNeighbors,
        minSize: minSize,
      ),
    );

    return <Rect>[
      for (var i = 0; i + 3 < flat.length; i += 4)
        Rect.fromLTWH(flat[i], flat[i + 1], flat[i + 2], flat[i + 3]),
    ];
  }

  /// 后台 isolate 入口：加载级联 + 灰度解码 + 多尺度检测，一次做完。
  ///
  /// 每次调用都会重新解析一遍 253KB 的级联 XML（几十到一百多毫秒），
  /// 换来的是无需维护一个常驻 worker isolate 及其生命周期 ——
  /// 换一次壁纸只走一条检测路径，这笔账划算。
  static Float64List _detectInIsolate({
    required String cascadePath,
    required Uint8List bytes,
    required double scaleFactor,
    required int minNeighbors,
    required int minSize,
  }) {
    cv.CascadeClassifier? cascade;
    cv.Mat? mat;
    cv.VecRect? rects;
    try {
      cascade = cv.CascadeClassifier.empty();
      if (!cascade.load(cascadePath)) return Float64List(0);

      // LBP 级联只吃灰度图，转灰度同时提速
      mat = cv.imdecode(bytes, cv.IMREAD_GRAYSCALE);
      if (mat.isEmpty) return Float64List(0);

      rects = cascade.detectMultiScale(
        mat,
        scaleFactor: scaleFactor,
        minNeighbors: minNeighbors,
        minSize: (minSize, minSize),
      );

      final list = rects.toList();
      final out = Float64List(list.length * 4);
      for (var i = 0; i < list.length; i++) {
        final r = list[i];
        out[i * 4] = r.x.toDouble();
        out[i * 4 + 1] = r.y.toDouble();
        out[i * 4 + 2] = r.width.toDouble();
        out[i * 4 + 3] = r.height.toDouble();
      }
      return out;
    } catch (_) {
      return Float64List(0);
    } finally {
      rects?.dispose();
      mat?.dispose();
      cascade?.dispose();
    }
  }

  /// 现在不持有任何原生句柄（级联在后台 isolate 里加载、用完即释放），
  /// 保留此方法只为让调用方（`WallpaperEngine.dispose`）的清理链完整。
  void dispose() {
    _cascadePath = null;
  }
}
