import 'dart:ui';

import 'package:drawing_notes_app/features/drawing/rendering/render_context.dart';
import 'package:drawing_notes_app/features/drawing/rendering/render_pipeline.dart';
import 'package:drawing_notes_app/features/drawing/rendering/render_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'each stage receives caller transform and clip without peer leakage',
    () async {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 20, 20));
      canvas.translate(2, 0);
      final initialSaveCount = canvas.getSaveCount();
      final pipeline = RenderPipeline(
        stages: [
          CallbackRenderStage((context) {
            context.canvas.save();
            context.canvas.translate(10, 0);
            context.canvas.clipRect(const Rect.fromLTWH(0, 0, 1, 1));
            // Intentionally leave this extra save outstanding.
          }),
          CallbackRenderStage((context) {
            context.canvas.drawRect(
              const Rect.fromLTWH(0, 0, 4, 4),
              Paint()..color = const Color(0xFFFF0000),
            );
          }),
        ],
      );
      pipeline.render(RenderContext(canvas: canvas, size: const Size(20, 20)));
      expect(canvas.getSaveCount(), initialSaveCount);
      final picture = recorder.endRecording();
      final image = await picture.toImage(20, 20);
      final bytes = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
      expect(bytes.getUint8((1 * 20 + 3) * 4), 255);
      expect(bytes.getUint8((1 * 20 + 3) * 4 + 3), 255);
      expect(bytes.getUint8((1 * 20 + 13) * 4 + 3), 0);
      image.dispose();
      picture.dispose();
    },
  );

  test('stage exceptions restore canvas state and propagate to caller', () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final count = canvas.getSaveCount();
    var laterStageRan = false;
    final pipeline = RenderPipeline(
      stages: [
        CallbackRenderStage((context) {
          context.canvas.save();
          context.canvas.translate(100, 100);
          throw StateError('stage failed');
        }),
        CallbackRenderStage((_) {
          laterStageRan = true;
        }),
      ],
    );
    expect(
      () => pipeline.render(
        RenderContext(canvas: canvas, size: const Size(20, 20)),
      ),
      throwsStateError,
    );
    expect(canvas.getSaveCount(), count);
    expect(laterStageRan, isFalse);
    recorder.endRecording().dispose();
  });

  test('stages added during rendering begin on the next frame', () {
    final recorder = PictureRecorder();
    final context = RenderContext(canvas: Canvas(recorder), size: Size.zero);
    final events = <String>[];
    late final RenderPipeline pipeline;
    var registered = false;
    pipeline = RenderPipeline(
      stages: [
        CallbackRenderStage((_) {
          events.add('first');
          if (!registered) {
            registered = true;
            pipeline.addStage(
              CallbackRenderStage((_) {
                events.add('new');
              }),
            );
          }
        }),
      ],
    );
    pipeline.render(context);
    expect(events, ['first']);
    pipeline.render(context);
    expect(events, ['first', 'first', 'new']);
    expect(() => pipeline.stages.clear(), throwsUnsupportedError);
    recorder.endRecording().dispose();
  });
}
