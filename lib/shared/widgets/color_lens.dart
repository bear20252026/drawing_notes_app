import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 颜色选择器放大镜组件。
///
/// 灵感来源：Inspira UI lens
/// 功能：在画布上移动时放大显示像素级颜色信息，用于精确取色。
///
/// 支持颜色自定义（放大镜边框颜色、背景色等）。
class ColorLens extends StatefulWidget {
  /// 是否显示放大镜。
  final bool visible;

  /// 放大镜位置。
  final Offset position;

  /// 放大倍数。
  final double magnification;

  /// 放大镜半径。
  final double radius;

  /// 边框颜色。
  final Color borderColor;

  /// 边框宽度。
  final double borderWidth;

  /// 子组件（画布）。
  final Widget child;

  const ColorLens({
    super.key,
    this.visible = true,
    required this.position,
    this.magnification = 3.0,
    this.radius = 50.0,
    this.borderColor = Colors.white,
    this.borderWidth = 2.0,
    required this.child,
  });

  @override
  State<ColorLens> createState() => _ColorLensState();
}

class _ColorLensState extends State<ColorLens> {
  @override
  Widget build(BuildContext context) {
    if (!widget.visible) {
      return widget.child;
    }

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: widget.position.dx - widget.radius,
          top: widget.position.dy - widget.radius,
          child: _buildLens(),
        ),
      ],
    );
  }

  Widget _buildLens() {
    return Container(
      width: widget.radius * 2,
      height: widget.radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: widget.borderColor,
          width: widget.borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: CustomPaint(
          painter: _LensPainter(
            center: widget.position,
            radius: widget.radius,
            magnification: widget.magnification,
            canvasKey: _canvasKey,
            onColorSampled: (color) {
              // Color sampling callback - can be used for external color preview.
            },
          ),
        ),
      ),
    );
  }

  final GlobalKey _canvasKey = GlobalKey();
}

/// 放大镜绘制器。
class _LensPainter extends CustomPainter {
  final Offset center;
  final double radius;
  final double magnification;
  final GlobalKey canvasKey;
  final ValueChanged<Color>? onColorSampled;

  _LensPainter({
    required this.center,
    required this.radius,
    required this.magnification,
    required this.canvasKey,
    this.onColorSampled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // 绘制放大区域。
    final srcRect = Rect.fromCircle(
      center: center,
      radius: radius / magnification,
    );
    final dstRect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: radius,
    );

    // 使用 ImageShader 放大绘制。
    final boundary = canvasKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary != null) {
      boundary.toImage().then((image) {
        final src = Rect.fromLTWH(
          srcRect.left.clamp(0, image.width.toDouble()),
          srcRect.top.clamp(0, image.height.toDouble()),
          srcRect.width.clamp(0, image.width.toDouble()),
          srcRect.height.clamp(0, image.height.toDouble()),
        );
        canvas.drawImageRect(image, src, dstRect, paint);

        // 采样中心颜色。
        _sampleColor(image, onColorSampled);
      });
    }

    // 绘制十字准星。
    final crossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 1.0;

    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      crossPaint,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      crossPaint,
    );
  }

  Future<void> _sampleColor(
    ui.Image image,
    ValueChanged<Color>? callback,
  ) async {
    if (callback == null) return;

    final byteData = await image.toByteData();
    if (byteData == null) return;

    final centerX = image.width ~/ 2;
    final centerY = image.height ~/ 2;
    final offset = (centerY * image.width + centerX) * 4;

    if (offset + 3 < byteData.lengthInBytes) {
      final r = byteData.getUint8(offset);
      final g = byteData.getUint8(offset + 1);
      final b = byteData.getUint8(offset + 2);
      final a = byteData.getUint8(offset + 3);
      callback(Color.fromARGB(a, r, g, b));
    }
  }

  @override
  bool shouldRepaint(covariant _LensPainter oldDelegate) {
    return center != oldDelegate.center ||
        radius != oldDelegate.radius ||
        magnification != oldDelegate.magnification;
  }
}

/// 简化版颜色放大镜组件。
///
/// 不依赖图像采样，仅显示放大区域。
class SimpleColorLens extends StatelessWidget {
  /// 是否显示放大镜。
  final bool visible;

  /// 放大镜位置。
  final Offset position;

  /// 放大倍数。
  final double magnification;

  /// 放大镜半径。
  final double radius;

  /// 边框颜色。
  final Color borderColor;

  /// 边框宽度。
  final double borderWidth;

  /// 子组件。
  final Widget child;

  /// 当前选中颜色。
  final Color currentColor;

  const SimpleColorLens({
    super.key,
    this.visible = true,
    required this.position,
    this.magnification = 3.0,
    this.radius = 50.0,
    this.borderColor = Colors.white,
    this.borderWidth = 2.0,
    required this.child,
    required this.currentColor,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return child;
    }

    return Stack(
      children: [
        child,
        Positioned(
          left: position.dx - radius,
          top: position.dy - radius,
          child: _buildLens(context),
        ),
      ],
    );
  }

  Widget _buildLens(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor,
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: Stack(
          children: [
            // 背景网格（透明度指示）。
            CustomPaint(
              size: Size(radius * 2, radius * 2),
              painter: _CheckerboardPainter(),
            ),
            // 当前颜色。
            Container(
              color: currentColor,
            ),
            // 十字准星。
            Center(
              child: Container(
                width: radius * 1.5,
                height: radius * 1.5,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
            Center(
              child: SizedBox(
                width: radius * 1.8,
                height: radius * 1.8,
                child: CustomPaint(
                  painter: _CrosshairPainter(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 棋盘格绘制器（透明度指示）。
class _CheckerboardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    const tileSize = 8.0;

    for (var y = 0.0; y < size.height; y += tileSize) {
      for (var x = 0.0; x < size.width; x += tileSize) {
        paint.color = ((x ~/ tileSize + y ~/ tileSize) % 2 == 0)
            ? Colors.grey.shade300
            : Colors.white;
        canvas.drawRect(
          Rect.fromLTWH(x, y, tileSize, tileSize),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 十字准星绘制器。
class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 1.0;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // 垂直线。
    canvas.drawLine(
      Offset(centerX, 0),
      Offset(centerX, size.height),
      paint,
    );
    // 水平线。
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
