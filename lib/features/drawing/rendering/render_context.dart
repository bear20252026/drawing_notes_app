import 'dart:ui';

/// Rendering state passed through the v2 render pipeline.
///
/// This keeps future render stages independent from CanvasPainter.
final class RenderContext {
  RenderContext({required this.canvas, required this.size});

  final Canvas canvas;
  final Size size;
}
