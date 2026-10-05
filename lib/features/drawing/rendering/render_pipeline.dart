import 'render_context.dart';
import 'render_stage.dart';

/// v2 rendering pipeline boundary.
///
/// Existing CanvasPainter remains the host during migration. New render work can
/// be introduced as independent stages and moved here incrementally.
final class RenderPipeline {
  RenderPipeline({Iterable<RenderStage> stages = const []})
    : _stages = List<RenderStage>.of(stages);

  final List<RenderStage> _stages;

  List<RenderStage> get stages => List.unmodifiable(_stages);

  void addStage(RenderStage stage) {
    _stages.add(stage);
  }

  void render(RenderContext context) {
    // Stage registration during a frame takes effect on the next frame.
    for (final stage in List<RenderStage>.of(_stages)) {
      final canvas = context.canvas;
      final saveCount = canvas.getSaveCount();
      canvas.save();
      try {
        stage.render(context);
      } finally {
        // A stage must never restore saves owned by its caller.
        canvas.restoreToCount(saveCount);
      }
    }
  }
}
