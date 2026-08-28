import 'dart:ui';

import 'package:drawing_notes_app/features/drawing/presentation/editor_image_crop_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imageBounds = Rect.fromLTWH(10, 20, 100, 80);
  const cropRect = Rect.fromLTWH(20, 30, 60, 50);

  group('EditorImageCropGeometry', () {
    test('四个角手柄只移动各自可编辑的两条边', () {
      final topLeft = EditorImageCropGeometry.resizeCropRect(
        cropRect: cropRect,
        imageBounds: imageBounds,
        handle: EditorImageCropHandle.topLeft,
        canvasDelta: const Offset(5, 6),
      );
      final topRight = EditorImageCropGeometry.resizeCropRect(
        cropRect: cropRect,
        imageBounds: imageBounds,
        handle: EditorImageCropHandle.topRight,
        canvasDelta: const Offset(5, 6),
      );
      final bottomLeft = EditorImageCropGeometry.resizeCropRect(
        cropRect: cropRect,
        imageBounds: imageBounds,
        handle: EditorImageCropHandle.bottomLeft,
        canvasDelta: const Offset(5, 6),
      );
      final bottomRight = EditorImageCropGeometry.resizeCropRect(
        cropRect: cropRect,
        imageBounds: imageBounds,
        handle: EditorImageCropHandle.bottomRight,
        canvasDelta: const Offset(5, 6),
      );

      expect(topLeft, const Rect.fromLTRB(25, 36, 80, 80));
      expect(topRight, const Rect.fromLTRB(20, 36, 85, 80));
      expect(bottomLeft, const Rect.fromLTRB(25, 30, 80, 86));
      expect(bottomRight, const Rect.fromLTRB(20, 30, 85, 86));
    });

    test('边界与最小 10px 裁剪尺寸沿用既有钳制语义', () {
      const tight = Rect.fromLTWH(20, 30, 15, 15);
      final minimum = EditorImageCropGeometry.resizeCropRect(
        cropRect: tight,
        imageBounds: imageBounds,
        handle: EditorImageCropHandle.topLeft,
        canvasDelta: const Offset(100, 100),
      );
      final maximum = EditorImageCropGeometry.resizeCropRect(
        cropRect: imageBounds,
        imageBounds: imageBounds,
        handle: EditorImageCropHandle.bottomRight,
        canvasDelta: const Offset(100, 100),
      );

      expect(minimum, const Rect.fromLTRB(25, 35, 35, 45));
      expect(maximum, imageBounds);
    });

    test('画布裁剪区域以既有加一比例映射到原图像素', () {
      final sourceRect = EditorImageCropGeometry.sourceRectForCrop(
        cropRect: const Rect.fromLTWH(35, 30, 50, 40),
        imageBounds: imageBounds,
        sourceSize: const Size(1000, 800),
      );

      expect(sourceRect.left, closeTo(25 * 1000 / 101, 0.00001));
      expect(sourceRect.top, closeTo(10 * 800 / 81, 0.00001));
      expect(sourceRect.width, closeTo(50 * 1000 / 101, 0.00001));
      expect(sourceRect.height, closeTo(40 * 800 / 81, 0.00001));
    });

    test('几何计算不会修改输入矩形', () {
      EditorImageCropGeometry.resizeCropRect(
        cropRect: cropRect,
        imageBounds: imageBounds,
        handle: EditorImageCropHandle.bottomRight,
        canvasDelta: const Offset(10, 10),
      );
      EditorImageCropGeometry.sourceRectForCrop(
        cropRect: cropRect,
        imageBounds: imageBounds,
        sourceSize: const Size(1000, 800),
      );

      expect(cropRect, const Rect.fromLTWH(20, 30, 60, 50));
      expect(imageBounds, const Rect.fromLTWH(10, 20, 100, 80));
    });
  });
}
