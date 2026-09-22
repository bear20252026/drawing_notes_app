// B11 语义覆盖门禁（增量，非全量普查）：锁定已落地的关键 Semantics 点，
// 防止后续重构静默丢掉读屏标签。全量普查仍为专项（ARCHITECTURE 4b）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('关键交互点已接 Semantics 标签（B11 增量锁）', () {
    final root = Directory('lib');
    final required = <String, String>{
      'features/notes/presentation/edgeless_page.dart':
          'edgelessCanvasSemantics',
      'features/drawing/presentation/resize_handles.dart':
          'canvasShapeHandleSemantics',
      'features/notes/presentation/presentation_page.dart': 'presNextSlide',
      'features/notes/presentation/notebook_reader_page.dart':
          'nbOpenPageForEdit',
      'features/doc/presentation/embedded_block_view.dart': 'attPreviewImage',
    };
    for (final entry in required.entries) {
      final file = File(
        '${root.path}${Platform.pathSeparator}'
        '${entry.key.replaceAll('/', Platform.pathSeparator)}',
      );
      expect(file.existsSync(), isTrue, reason: entry.key);
      final text = file.readAsStringSync();
      expect(
        text.contains(entry.value),
        isTrue,
        reason: '${entry.key} 应引用 ${entry.value}',
      );
      expect(
        text.contains('Semantics('),
        isTrue,
        reason: '${entry.key} 应含 Semantics 包装',
      );
    }
  });

  test('纯图标交互组件未退回无 Semantics 的 GestureDetector 样本', () {
    // resize handles：必须同时存在 button:true 与 label。
    final resize = File(
      'lib/features/drawing/presentation/resize_handles.dart',
    ).readAsStringSync();
    expect(resize.contains('button: true'), isTrue);
  });
}
