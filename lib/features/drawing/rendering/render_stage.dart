import 'render_context.dart';

/// A composable rendering stage.
///
/// Stages can later be provided by plugins without changing the canvas host.
abstract interface class RenderStage {
  void render(RenderContext context);
}

/// Adapts an existing renderer without adding a dependency on its host.
final class CallbackRenderStage implements RenderStage {
  const CallbackRenderStage(this._paint);

  final void Function(RenderContext) _paint;

  @override
  void render(RenderContext context) => _paint(context);
}
