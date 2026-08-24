// editor_v2——MagnifierOverlay 取色放大镜（用户需�?#7—�?026-08-24）�?//
// 用户需求：取色板功能困难——应在鼠标所指位置中央生成小放大镜—�?// 放大显示那到底是什么颜色�?//
// Excalidraw 借鉴：取色放大镜 + 十字准线 + HEX 颜色值显示�?library;

import 'package:flutter/material.dart';

import '../../../core/theme/text_scale_helper.dart';
import 'package:editor_core/editor_core.dart';

/// 取色放大镜覆盖层（用户需求——长�?吸管显示放大取色环）�?///
/// 显示效果�?/// - 圆形放大镜（显示 cursor 周围区域的放大视图）
/// - 十字准线（标记取色中心点�?/// - HEX 颜色值标签（放大镜下方显示当前颜色）
/// - 圆形边框（高亮当前取色区域）
class MagnifierOverlay extends StatelessWidget {
  const MagnifierOverlay({
    super.key,
    required this.cursorPosition,
    required this.pickedColor,
    this.config = const MagnifierConfig(),
    this.child,
  });

  /// 光标位置（屏幕坐标）�?  final Offset cursorPosition;

  /// 当前取色结果�?  final PickedColor pickedColor;

  /// 放大镜配置�?  final MagnifierConfig config;

  /// 被放大的�?widget（可选——通常是画布）�?  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final magnifierSize = const ColorMagnifier().magnifierSize(config);
    final displayWidth = magnifierSize.width.toDouble();
    final displayHeight = magnifierSize.height.toDouble();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // �?widget（画布）�?        if (child != null) child!,

        // 放大镜主体�?        Positioned(
          left: cursorPosition.dx - displayWidth / 2,
          top: cursorPosition.dy - displayHeight / 2 - 40,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 放大镜圆形区域�?              Container(
                width: displayWidth,
                height: displayHeight,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 2.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: CustomPaint(
                    size: Size(displayWidth, displayHeight),
                    painter: _MagnifierPainter(
                      config: config,
                      pickedColor: pickedColor,
                    ),
                  ),
                ),
              ),

              // HEX 颜色值标签�?              if (config.showHex)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    pickedColor.hex,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: TextScaleHelper.scaled(context, 12),
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 放大镜自定义绘制器（Excalidraw 借鉴——像素网�?+ 十字准线）�?class _MagnifierPainter extends CustomPainter {
  _MagnifierPainter({
    required this.config,
    required this.pickedColor,
  });

  final MagnifierConfig config;
  final PickedColor pickedColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 背景色（显示当前取色的背景）�?    final bgPaint = Paint()
      ..color = Color.fromRGBO(pickedColor.r, pickedColor.g, pickedColor.b, 1.0);
    canvas.drawCircle(center, radius, bgPaint);

    // 网格线（模拟像素放大效果——Excalidraw 像素网格风格）�?    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..strokeWidth = 0.5;
    final gridSize = config.zoom.toDouble();
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 十字准线（标记取色中心）�?    if (config.showCrosshair) {
      final crosshairPaint = Paint()
        ..color = Colors.red
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      // 水平线�?      canvas.drawLine(
        Offset(center.dx - radius * 0.6, center.dy),
        Offset(center.dx + radius * 0.6, center.dy),
        crosshairPaint,
      );
      // 垂直线�?      canvas.drawLine(
        Offset(center.dx, center.dy - radius * 0.6),
        Offset(center.dx, center.dy + radius * 0.6),
        crosshairPaint,
      );
      // 中心点�?      final dotPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 2.0, dotPaint);
    }

    // 圆形边框�?    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius - 1, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _MagnifierPainter oldDelegate) {
    return pickedColor != oldDelegate.pickedColor;
  }
}
