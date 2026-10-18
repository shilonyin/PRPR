import 'dart:math' as math;
import 'dart:ui' show Rect, Size, Offset;

/// 裁剪方式。对应原 `AnimePersonalization.CropMethod`。
enum CropMethod {
  none(0),
  topMiddle(1),
  center(2),
  biggestFace(3),
  mostFaces(4);

  const CropMethod(this.value);
  final int value;

  static CropMethod fromValue(int v) {
    for (final m in CropMethod.values) {
      if (m.value == v) return m;
    }
    return CropMethod.topMiddle;
  }
}

/// 壁纸裁剪算法。逐行移植自原 UWP 项目
/// `BooruViewer\\Services\\CropBitmap.cs`（264 行）。
///
/// 移植时刻意保持与原版一致的分支顺序与浮点运算顺序，
/// 这样同一张图 + 同一组人脸框会得到与原版像素级接近的结果。
class CropCalculator {
  CropCalculator._();

  /// 居中裁剪：按目标宽高比决定裁掉左右还是上下。
  static Rect centerCrop(Size imageSize, Size requiredSize) {
    final imageRatio = imageSize.width / imageSize.height;
    final requiredRatio = requiredSize.width / requiredSize.height;

    if (imageRatio > requiredRatio) {
      // 图太宽 → 裁左右
      final newWidth = imageSize.height * requiredRatio;
      final left = (imageSize.width - newWidth) / 2;
      return Rect.fromLTWH(left, 0, newWidth, imageSize.height);
    } else {
      // 图太高 → 裁上下
      final newHeight = imageSize.width / requiredRatio;
      final top = (imageSize.height - newHeight) / 2;
      return Rect.fromLTWH(0, top, imageSize.width, newHeight);
    }
  }

  /// 顶部居中裁剪：横图裁左右居中；竖图从顶部裁。
  ///
  /// 这是「让脸尽量留在画面上半部分」的朴素策略，也是无人脸时的兜底。
  static Rect topMiddleCrop(Size imageSize, Size requiredSize) {
    final imageRatio = imageSize.width / imageSize.height;
    final requiredRatio = requiredSize.width / requiredSize.height;

    if (imageRatio > requiredRatio) {
      final newWidth = imageSize.height * requiredRatio;
      final left = (imageSize.width - newWidth) / 2;
      return Rect.fromLTWH(left, 0, newWidth, imageSize.height);
    } else {
      final newHeight = imageSize.width / requiredRatio;
      return Rect.fromLTWH(0, 0, imageSize.width, newHeight);
    }
  }

  /// 贪心裁剪：在保证装下尽可能多的脸的前提下，让裁剪窗口尽量贴合人脸区域。
  ///
  /// 对应原 `GetGreedyCropRect`：
  /// 1. 没有人脸 → 退化为 topMiddle；
  /// 2. 脸按尺寸降序排序（横图按宽、竖图按高）；
  /// 3. 循环剔除最小的脸，直到剩余脸能全部装进窗口；
  /// 4. 装得下 → 用 OptimizedCrop 贴合人脸包围盒；
  ///    装不下（单张最大的脸都超出窗口）→ 以最大脸中心开窗。
  static Rect greedyCrop(
    Size imageSize,
    Size requiredSize,
    List<Rect> faces,
  ) {
    if (faces.isEmpty) return topMiddleCrop(imageSize, requiredSize);

    final isImageTooWide = imageSize.width / imageSize.height >
        requiredSize.width / requiredSize.height;

    // 拷贝一份，避免修改调用方数据
    final working = List<Rect>.from(faces);

    // 按尺寸降序：横图看宽度，竖图看高度
    if (isImageTooWide) {
      working.sort((a, b) => b.width.compareTo(a.width));
    } else {
      working.sort((a, b) => b.height.compareTo(a.height));
    }

    // 窗口在该方向上的长度是固定的：横图受限于高，竖图受限于宽
    final windowExtent = isImageTooWide
        ? imageSize.height * requiredSize.width / requiredSize.height
        : imageSize.width * requiredSize.height / requiredSize.width;

    // 从最小的脸开始剔除，直到剩余脸能被窗口容下
    while (working.length > 1) {
      if (_fitsInWindow(working, windowExtent, isImageTooWide)) break;
      working.removeLast();
    }

    // 只剩一张脸且仍装不下 → 围绕这张脸的中心开窗
    if (!_fitsInWindow(working, windowExtent, isImageTooWide)) {
      final face = working.first;
      return cropAroundCenter(
        imageSize,
        requiredSize,
        face.center,
      );
    }

    return isImageTooWide
        ? _optimizedCropH(imageSize, requiredSize, working)
        : _optimizedCropV(imageSize, requiredSize, working);
  }

  /// 人脸在某个方向上的跨度是否不超过窗口长度。
  static bool _fitsInWindow(
    List<Rect> faces,
    double windowExtent,
    bool isImageTooWide,
  ) {
    if (faces.isEmpty) return false;
    double minEdge;
    double maxEdge;
    if (isImageTooWide) {
      minEdge = faces.map((f) => f.left).reduce(math.min);
      maxEdge = faces.map((f) => f.right).reduce(math.max);
    } else {
      minEdge = faces.map((f) => f.top).reduce(math.min);
      maxEdge = faces.map((f) => f.bottom).reduce(math.max);
    }
    return (maxEdge - minEdge) <= windowExtent;
  }

  /// 横图版贴合：窗口宽度固定（= 高度 × 目标比例），
  /// 左右留白按人脸包围盒的左右剩余空间比例分配。
  static Rect _optimizedCropH(
    Size imageSize,
    Size requiredSize,
    List<Rect> faces,
  ) {
    final left = faces.map((f) => f.left).reduce(math.min);
    final right = faces.map((f) => f.right).reduce(math.max);

    final finalWidth = imageSize.height * requiredSize.width / requiredSize.height;

    final leftSpace = left;
    final rightSpace = imageSize.width - right;
    final totalSpace = leftSpace + rightSpace;

    // 两侧都没有余量时（贴边）直接左对齐，避免除零
    final leftRightRatio = totalSpace <= 0 ? 0.0 : leftSpace / totalSpace;

    final overflow = finalWidth - (right - left);
    final leftFinalSpace = left - overflow * leftRightRatio;

    return Rect.fromLTWH(leftFinalSpace, 0, finalWidth, imageSize.height);
  }

  /// 竖图版贴合：窗口高度固定，上下留白按比例分配。
  static Rect _optimizedCropV(
    Size imageSize,
    Size requiredSize,
    List<Rect> faces,
  ) {
    final top = faces.map((f) => f.top).reduce(math.min);
    final bottom = faces.map((f) => f.bottom).reduce(math.max);

    final finalHeight =
        imageSize.width * requiredSize.height / requiredSize.width;

    final topSpace = top;
    final bottomSpace = imageSize.height - bottom;
    final totalSpace = topSpace + bottomSpace;

    final topBottomRatio = totalSpace <= 0 ? 0.0 : topSpace / totalSpace;

    final overflow = finalHeight - (bottom - top);
    final topFinalSpace = top - overflow * topBottomRatio;

    return Rect.fromLTWH(0, topFinalSpace, imageSize.width, finalHeight);
  }

  /// 以指定点为中心开窗，窗口按目标宽高比取最大。
  ///
  /// 对应原 `CropAroundCenter`。结果会被夹紧到图片边界内。
  static Rect cropAroundCenter(
    Size imageSize,
    Size requiredSize,
    Offset center,
  ) {
    final imageRatio = imageSize.width / imageSize.height;
    final requiredRatio = requiredSize.width / requiredSize.height;

    double w;
    double h;
    if (imageRatio > requiredRatio) {
      h = imageSize.height;
      w = h * requiredRatio;
    } else {
      w = imageSize.width;
      h = w / requiredRatio;
    }

    var left = center.dx - w / 2;
    var top = center.dy - h / 2;

    // 夹紧，保证窗口完全落在图内
    left = left.clamp(0.0, math.max(0.0, imageSize.width - w));
    top = top.clamp(0.0, math.max(0.0, imageSize.height - h));

    return Rect.fromLTWH(left, top, w, h);
  }

  /// 按方式分派。人脸框为空时 MostFaces / BiggestFace 都会退化为 topMiddle。
  static Rect compute(
    CropMethod method,
    Size imageSize,
    Size requiredSize, {
    List<Rect> faces = const <Rect>[],
  }) {
    switch (method) {
      case CropMethod.none:
        return Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
      case CropMethod.center:
        return centerCrop(imageSize, requiredSize);
      case CropMethod.topMiddle:
        return topMiddleCrop(imageSize, requiredSize);
      case CropMethod.biggestFace:
        if (faces.isEmpty) return topMiddleCrop(imageSize, requiredSize);
        final biggest =
            faces.reduce((a, b) => a.width * a.height >= b.width * b.height ? a : b);
        return greedyCrop(imageSize, requiredSize, <Rect>[biggest]);
      case CropMethod.mostFaces:
        if (faces.isEmpty) return topMiddleCrop(imageSize, requiredSize);
        return greedyCrop(imageSize, requiredSize, faces);
    }
  }

  /// 把人脸坐标从「检测时用的缩略图尺寸」映射回「原图尺寸」。
  ///
  /// 对应原 `ImageCropper.ScaleFaces`。原版在缩略图上做检测是为了速度，
  /// 检测结果必须按比例放大才能用于原图裁剪。
  static List<Rect> scaleFaces(
    List<Rect> faces,
    Size from,
    Size to,
  ) {
    if (from.width <= 0 || from.height <= 0) return faces;
    final sx = to.width / from.width;
    final sy = to.height / from.height;
    return faces
        .map((f) => Rect.fromLTWH(
              f.left * sx,
              f.top * sy,
              f.width * sx,
              f.height * sy,
            ))
        .toList();
  }
}
