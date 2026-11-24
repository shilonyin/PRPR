import 'dart:async';
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

  /// 正在落盘时共享的 Completer：并发调用都 await 同一个 Future，
  /// 取代原先 50ms×100 的轮询——轮询既可能空等满 5 秒，也可能在写盘
  /// 完成前就超时返回 null。Completer 让所有等待者精确地在完成那一刻醒来。
  Completer<String?>? _materializing;

  /// 级联文件是否已落盘（不代表后台 isolate 里已加载）。
  bool get isReady => _cascadePath != null;

  /// 确保级联 XML 已写进应用支持目录，返回其绝对路径；失败返回 null。
  /// 可重复调用，路径会被缓存。
  Future<String?> ensureCascadeFile() {
    if (_cascadePath != null) return Future<String?>.value(_cascadePath);
    final pending = _materializing;
    if (pending != null) return pending.future;

    final completer = Completer<String?>();
    _materializing = completer;
    // 用独立的 async 闭包驱动落盘，本方法同步返回共享 Future。
    () async {
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
        completer.complete(target.path);
      } catch (_) {
        completer.complete(null);
      } finally {
        _materializing = null;
      }
    }();
    return completer.future;
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
    cv.Mat? mat;
    try {
      // LBP 级联只吃灰度图，转灰度同时提速
      mat = cv.imdecode(bytes, cv.IMREAD_GRAYSCALE);
      if (mat.isEmpty) return Float64List(0);
      return detectOnDecodedMat(
        mat,
        cascadePath: cascadePath,
        scaleFactor: scaleFactor,
        minNeighbors: minNeighbors,
        minSize: minSize,
      );
    } catch (_) {
      return Float64List(0);
    } finally {
      mat?.dispose();
    }
  }

  /// 在「已解码 Mat 所在的 isolate」内直接做检测，不再重新解码图片。
  ///
  /// 为什么单独暴露它：壁纸管线把「解码→检测→裁剪→JPEG」合并进同一个
  /// Isolate.run 以省掉第二次全量解码，此时手里已经是 Mat 而不是字节，
  /// 不能再走 [detectFromBytes]（那会再 imdecode 一次）。这里复用同一套
  /// 级联加载与 detectMultiScale 参数，保证两条路径检测结果一致。
  ///
  /// [mat] 可以是彩色或灰度：非灰度会内部转灰度（不修改入参）。
  /// 返回平坦的 (x,y,w,h)*n 数组，坐标系为 [mat] 自身；失败/无脸返回空数组。
  /// 调用方负责 [mat] 的释放，本方法只释放自己新建的灰度副本与级联句柄。
  static Float64List detectOnDecodedMat(
    cv.Mat mat, {
    required String cascadePath,
    double scaleFactor = AppConstants.faceDetectScaleFactor,
    int minNeighbors = AppConstants.faceDetectMinNeighbors,
    int minSize = AppConstants.faceDetectMinSize,
  }) {
    cv.CascadeClassifier? cascade;
    cv.Mat? gray;
    cv.VecRect? rects;
    var ownsGray = false;
    try {
      cascade = cv.CascadeClassifier.empty();
      if (!cascade.load(cascadePath)) return Float64List(0);

      if (mat.channels == 1) {
        gray = mat;
      } else {
        gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
        ownsGray = true;
      }
      if (gray.isEmpty) return Float64List(0);

      rects = cascade.detectMultiScale(
        gray,
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
      if (ownsGray) gray?.dispose();
      cascade?.dispose();
    }
  }

  /// 现在不持有任何原生句柄（级联在后台 isolate 里加载、用完即释放），
  /// 保留此方法只为让调用方（`WallpaperEngine.dispose`）的清理链完整。
  void dispose() {
    _cascadePath = null;
  }
}
