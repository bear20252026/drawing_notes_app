import 'dart:ui';

import 'package:drawing_notes_app/features/drawing/rendering/pencil_shader.dart';
import 'package:drawing_notes_app/features/drawing/rendering/stroke_renderer.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Stroke pencilStroke() => Stroke(
    type: BrushType.pencil,
    color: const Color(0xFF444444),
    width: 8,
    points: const [
      StrokePoint(10, 10, 0.4),
      StrokePoint(40, 30, 0.8),
      StrokePoint(80, 25, 0.5),
    ],
  );

  test('init 幂等且不抛异常（加载失败也静默回退）', () async {
    // 无论测试环境能否编译 Shader，init 都不应抛出。
    await PencilShader.init();
    await PencilShader.init(); // 幂等：第二次直接返回。
  });

  test('未就绪时 create 返回 null，不会返回无效着色器', () {
    // 若环境不支持 Shader 编译，isReady 为 false，create 必须返回 null。
    final shader = PencilShader.create(
      color: const Color(0xFF444444),
      grainScale: 3.6,
      opacity: 0.8,
    );
    if (PencilShader.isReady) {
      expect(shader, isNotNull);
    } else {
      expect(shader, isNull);
    }
  });

  test('铅笔笔画在着色器未就绪时仍可正常绘制（回退）', () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    // 无论是否已加载 Shader，铅笔绘制路径都不应崩溃；
    // 回退路径保持原低透明度石墨绘制。
    StrokeRenderer.drawStroke(canvas, pencilStroke());
    final picture = recorder.endRecording();
    expect(picture, isNotNull);
    picture.dispose();
  });
}
