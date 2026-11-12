// B11 语义覆盖门禁（增量，非全量普查）：锁定已落地的关键 Semantics 点，
// 防止后续重构静默丢掉读屏标签。全量普查仍为专项（ARCHITECTURE 4b）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('关键交互点已接 Semantics 标签（B11 增量锁）', () {
    final root = Directory('lib');
    // v1.17.21：AFFiNE Edgeless 模块整体移除（死代码清理）——
    // 原 edgeless_page.dart 的 edgelessCanvasSemantics 锁条目随之撤销。
    //
    // 画布手柄键盘等价：8 向缩放 / 线性端点 / 文字宽度三个手柄的 Semantics
    // 包装合并进了 `shared/widgets/canvas_drag_handle.dart`（同一控件、
    // 同一热区、同一焦点环），resize_handles.dart 只剩 label 引用。
    // 锁按「谁持有包装」重指；若仍要求调用点含 `Semantics(`，等于用门禁
    // 把这次合并改回去（逼着每个调用点再包一层空壳）。
    //
    // 值是 `(必须出现的标记, 本文件是否要求 Semantics( 包装)`。
    final required = <String, (String, bool)>{
      'features/drawing/presentation/resize_handles.dart': (
        'canvasShapeHandleSemantics',
        false,
      ),
      'shared/widgets/canvas_drag_handle.dart': ('button: true', true),
      'features/notes/presentation/presentation_page.dart': ('presNextSlide', true),
      'features/notes/presentation/notebook_reader_page.dart': (
        'nbOpenPageForEdit',
        true,
      ),
      'features/doc/presentation/embedded_block_view.dart': (
        'attPreviewImage',
        true,
      ),
    };
    for (final entry in required.entries) {
      final file = File(
        '${root.path}${Platform.pathSeparator}'
        '${entry.key.replaceAll('/', Platform.pathSeparator)}',
      );
      expect(file.existsSync(), isTrue, reason: entry.key);
      final text = file.readAsStringSync();
      final (marker, expectsWrapper) = entry.value;
      expect(
        text.contains(marker),
        isTrue,
        reason: '${entry.key} 应引用 $marker',
      );
      if (!expectsWrapper) continue;
      expect(
        text.contains('Semantics('),
        isTrue,
        reason: '${entry.key} 应含 Semantics 包装',
      );
    }
  });

  test('纯图标交互组件未退回无 Semantics 的 GestureDetector 样本', () {
    // 三个画布手柄共用 canvas_drag_handle.dart：包装（Semantics + button:true）
    // 必须在共用控件里，而不是散回各调用点。
    final handle = File(
      'lib/shared/widgets/canvas_drag_handle.dart',
    ).readAsStringSync();
    expect(handle.contains('button: true'), isTrue);
    expect(handle.contains('Semantics('), isTrue);
  });
}
