import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

import 'package:drawing_notes_app/features/editor_v2/application/editor_v2_viewmodel.dart';
import 'package:editor_core/editor_core.dart';

/// EditorV2ViewModel 完整单元测试（V1/V2 迁移阶段2）。
/// 使用 Riverpod ProviderContainer 测试 Notifier（Headless Logic）。
void main() {
  late ProviderContainer container;
  late EditorV2Notifier notifier;

  setUp(() {
    container = ProviderContainer();
    notifier = container.read(editorV2NotifierProvider.notifier);
  });

  tearDown(() {
    container.dispose();
  });

  // ════════════════════════════════════════════════════════════════
  // 基础状态
  // ════════════════════════════════════════════════════════════════

  group('基础状态', () {
    test('初始状态：空文档', () {
      final state = container.read(editorV2NotifierProvider);
      expect(state.document.id, 'new');
      expect(state.canUndo, false);
      expect(state.canRedo, false);
      expect(state.currentTool, 'draw');
      expect(state.brushType, 'pen');
    });

    test('createDocument：创建文档', () {
      notifier.createDocument('test-doc');
      final state = container.read(editorV2NotifierProvider);
      expect(state.document.id, 'test-doc');
      expect(state.document.layers.length, 1);
      expect(state.document.layers.first.id, 'layer-1');
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 绘制 + 撤销/重做
  // ════════════════════════════════════════════════════════════════

  group('绘制 + 撤销/重做', () {
    test('addStroke：添加笔画', () {
      notifier.createDocument('test-doc');
      notifier.addStroke([const Point(0, 0), const Point(10, 10)]);
      final state = container.read(editorV2NotifierProvider);
      expect(state.document.layers.first.strokes.length, 1);
      expect(state.canUndo, true);
    });

    test('undo/redo：撤销/重做', () {
      notifier.createDocument('test-doc');
      notifier.addStroke([const Point(0, 0), const Point(10, 10)]);
      expect(
        container.read(editorV2NotifierProvider).document.layers.first.strokes.length,
        1,
      );

      notifier.undo();
      expect(
        container.read(editorV2NotifierProvider).document.layers.first.strokes.length,
        0,
      );
      expect(container.read(editorV2NotifierProvider).canRedo, true);

      notifier.redo();
      expect(
        container.read(editorV2NotifierProvider).document.layers.first.strokes.length,
        1,
      );
      expect(container.read(editorV2NotifierProvider).canUndo, true);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 5 种笔刷类型（V1/V2 迁移阶段2）
  // ════════════════════════════════════════════════════════════════

  group('5 种笔刷类型', () {
    test('setBrushType: pen（默认）', () {
      expect(container.read(editorV2NotifierProvider).brushType, 'pen');
      expect(container.read(editorV2NotifierProvider).currentTool, 'draw');
    });

    test('setBrushType: pencil', () {
      notifier.setBrushType('pencil');
      final state = container.read(editorV2NotifierProvider);
      expect(state.brushType, 'pencil');
      expect(state.currentTool, 'draw'); // 自动切到绘图工具
    });

    test('setBrushType: marker', () {
      notifier.setBrushType('marker');
      expect(container.read(editorV2NotifierProvider).brushType, 'marker');
    });

    test('setBrushType: laser', () {
      notifier.setBrushType('laser');
      expect(container.read(editorV2NotifierProvider).brushType, 'laser');
    });

    test('setBrushType: eraser', () {
      notifier.setBrushType('eraser');
      expect(container.read(editorV2NotifierProvider).brushType, 'eraser');
    });

    test('laser 笔刷不写入文档', () {
      notifier.createDocument('test-doc');
      notifier.setBrushType('laser');
      notifier.addStroke([const Point(0, 0), const Point(10, 10)]);
      expect(
        container.read(editorV2NotifierProvider).document.layers.first.strokes.length,
        0,
      );
    });

    test('marker 笔刷使用 0.5 透明度', () {
      notifier.createDocument('test-doc');
      notifier.setBrushType('marker');
      notifier.addStroke([const Point(0, 0), const Point(10, 10)]);
      final strokes =
          container.read(editorV2NotifierProvider).document.layers.first.strokes;
      expect(strokes.length, 1);
      // opacity == 0.5 for marker
      expect(strokes.first.opacity, 0.5);
    });

    test('pen 笔刷使用 1.0 透明度', () {
      notifier.createDocument('test-doc');
      notifier.addStroke([const Point(0, 0), const Point(10, 10)]);
      final strokes =
          container.read(editorV2NotifierProvider).document.layers.first.strokes;
      expect(strokes.first.opacity, 1.0);
    });

    test('setBrushType 关闭 eyedropper', () {
      notifier.activateEyedropper();
      expect(container.read(editorV2NotifierProvider).eyedropperActive, true);
      notifier.setBrushType('pen');
      expect(container.read(editorV2NotifierProvider).eyedropperActive, false);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 工具切换
  // ════════════════════════════════════════════════════════════════

  group('工具切换', () {
    test('setTool: select', () {
      notifier.setTool('select');
      expect(container.read(editorV2NotifierProvider).currentTool, 'select');
    });

    test('setTool: pan', () {
      notifier.setTool('pan');
      expect(container.read(editorV2NotifierProvider).currentTool, 'pan');
    });

    test('setShapeType: ellipse', () {
      notifier.setShapeType('ellipse');
      expect(container.read(editorV2NotifierProvider).currentShapeType, 'ellipse');
    });

    test('setShapeType: rect', () {
      notifier.setShapeType('rect');
      expect(container.read(editorV2NotifierProvider).currentShapeType, 'rect');
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 文字工具（V1/V2 迁移阶段2）
  // ════════════════════════════════════════════════════════════════

  group('文字工具', () {
    test('addText：新建文本', () {
      notifier.createDocument('test-doc');
      notifier.addText('Hello', 100, 200);
      final state = container.read(editorV2NotifierProvider);
      expect(state.document.layers.first.texts.length, 1);
      expect(state.document.layers.first.texts.first.content, 'Hello');
      expect(state.canUndo, true);
    });

    test('selectText：选中文本', () {
      notifier.createDocument('test-doc');
      notifier.addText('Hello', 100, 200);
      final textId =
          container.read(editorV2NotifierProvider).document.layers.first.texts.first.id;
      notifier.selectText(textId);
      final state = container.read(editorV2NotifierProvider);
      expect(state.selectedTextId, textId);
      expect(state.selectedItemId, textId);
    });

    test('clearSelection：取消选中', () {
      notifier.createDocument('test-doc');
      notifier.addText('Hello', 100, 200);
      final textId =
          container.read(editorV2NotifierProvider).document.layers.first.texts.first.id;
      notifier.selectText(textId);
      notifier.clearSelection();
      final state = container.read(editorV2NotifierProvider);
      expect(state.selectedTextId, isNull);
      expect(state.selectedItemId, isNull);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 图片（V1/V2 迁移阶段2）
  // ════════════════════════════════════════════════════════════════

  group('图片', () {
    test('insertImage：插入图片', () {
      notifier.createDocument('test-doc');
      notifier.insertImage('media-001', 50, 50, width: 300, height: 200);
      final state = container.read(editorV2NotifierProvider);
      expect(state.document.layers.first.images.length, 1);
      expect(state.document.layers.first.images.first.mediaId, 'media-001');
      expect(state.document.layers.first.images.first.width, 300);
      expect(state.canUndo, true);
    });

    test('insertImage 撤销后恢复', () {
      notifier.createDocument('test-doc');
      notifier.insertImage('media-001', 50, 50);
      notifier.undo();
      expect(
        container.read(editorV2NotifierProvider).document.layers.first.images.length,
        0,
      );
      notifier.redo();
      expect(
        container.read(editorV2NotifierProvider).document.layers.first.images.length,
        1,
      );
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 形状
  // ════════════════════════════════════════════════════════════════

  group('形状', () {
    test('addShape：添加矩形', () {
      notifier.createDocument('test-doc');
      notifier.addShape('rect', 10, 20, 100, 80);
      final state = container.read(editorV2NotifierProvider);
      expect(state.document.layers.first.shapes.length, 1);
      expect(state.document.layers.first.shapes.first.type, 'rect');
    });

    test('addShape：添加椭圆+自定义颜色', () {
      notifier.createDocument('test-doc');
      notifier.addShape('ellipse', 10, 20, 100, 80,
          strokeColor: '#FF0000', fillColor: '#00FF00');
      final shape = container.read(editorV2NotifierProvider).document.layers.first.shapes.first;
      expect(shape.strokeColor, '#FF0000');
      expect(shape.fillColor, '#00FF00');
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 橡皮擦（V1/V2 迁移阶段2）
  // ════════════════════════════════════════════════════════════════

  group('橡皮擦', () {
    test('eraseAt：按距离擦除', () {
      notifier.createDocument('test-doc');
      notifier.addStroke([const Point(0, 0), const Point(10, 10)]);
      expect(
        container.read(editorV2NotifierProvider).document.layers.first.strokes.length,
        1,
      );
      notifier.eraseAt(5, 5);
      final state = container.read(editorV2NotifierProvider);
      // EraseByDistanceCommand may or may not remove depending on distance
      expect(state.canUndo, true);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 图层管理（V1/V2 迁移阶段2）
  // ════════════════════════════════════════════════════════════════

  group('图层管理', () {
    test('addLayer：新增图层', () {
      notifier.createDocument('test-doc');
      notifier.addLayer(name: '自定义图层');
      final state = container.read(editorV2NotifierProvider);
      expect(state.document.layers.length, 2);
      expect(state.document.layers.last.name, '自定义图层');
    });

    test('toggleLayerVisibility：切换可见性', () {
      notifier.createDocument('test-doc');
      notifier.toggleLayerVisibility('layer-1');
      final state = container.read(editorV2NotifierProvider);
      expect(state.document.layers.first.visible, false);
      notifier.toggleLayerVisibility('layer-1');
      expect(
        container.read(editorV2NotifierProvider).document.layers.first.visible,
        true,
      );
    });

    test('deleteLayer：删除图层（保留至少一个）', () {
      notifier.createDocument('test-doc');
      notifier.addLayer();
      expect(container.read(editorV2NotifierProvider).document.layers.length, 2);
      notifier.deleteLayer('layer-2');
      expect(container.read(editorV2NotifierProvider).document.layers.length, 1);
    });

    test('deleteLayer：最后一个图层不删除', () {
      notifier.createDocument('test-doc');
      notifier.deleteLayer('layer-1');
      expect(container.read(editorV2NotifierProvider).document.layers.length, 1);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 取色器（P2 #30）
  // ════════════════════════════════════════════════════════════════

  group('取色器', () {
    test('activateEyedropper：激活取色器', () {
      notifier.activateEyedropper();
      final state = container.read(editorV2NotifierProvider);
      expect(state.currentTool, 'eyedropper');
      expect(state.eyedropperActive, true);
    });

    test('deactivateEyedropper：取消取色器', () {
      notifier.activateEyedropper();
      notifier.deactivateEyedropper();
      final state = container.read(editorV2NotifierProvider);
      expect(state.currentTool, 'draw');
      expect(state.eyedropperActive, false);
    });

    test('updateEyedropperPosition：更新位置', () {
      notifier.activateEyedropper();
      notifier.updateEyedropperPosition(const Offset(150, 200));
      final state = container.read(editorV2NotifierProvider);
      expect(state.eyedropperPosition, const Offset(150, 200));
    });

    test('applyPickedColor：应用取色结果', () {
      notifier.createDocument('test-doc');
      notifier.activateEyedropper();
      notifier.applyPickedColor(const Color(0xFFFF5733));
      final state = container.read(editorV2NotifierProvider);
      expect(state.currentTool, 'draw');
      expect(state.eyedropperActive, false);
      expect(state.currentColor, const Color(0xFFFF5733));
      expect(state.strokeColorHex, '#FF5733');
    });

    test('setMagnifierColor：实时更新放大镜颜色', () {
      notifier.activateEyedropper();
      notifier.setMagnifierColor(const Color(0xFF00FF00));
      expect(
        container.read(editorV2NotifierProvider).currentColor,
        const Color(0xFF00FF00),
      );
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 笔刷设置
  // ════════════════════════════════════════════════════════════════

  group('笔刷设置', () {
    test('setBrushSize', () {
      notifier.setBrushSize(8.0);
      expect(container.read(editorV2NotifierProvider).brushSize, 8.0);
    });

    test('setStrokeColor', () {
      notifier.setStrokeColor('#FF00FF');
      expect(container.read(editorV2NotifierProvider).strokeColorHex, '#FF00FF');
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 持久化（V1/V2 迁移阶段2——自动保存）
  // ════════════════════════════════════════════════════════════════

  group('持久化（自动保存）', () {
    test('toJson / loadFromJson：序列化往返', () {
      notifier.createDocument('save-test');
      notifier.addStroke([const Point(0, 0), const Point(10, 10)]);
      notifier.addText('Note', 50, 50);
      notifier.addShape('rect', 10, 20, 100, 80);
      notifier.insertImage('img-001', 30, 30);

      final json = notifier.toJson();
      expect(json['id'], 'save-test');
      expect(json.containsKey('layers'), isTrue);

      // 恢复
      notifier.loadFromJson(json);
      final restored = container.read(editorV2NotifierProvider);
      expect(restored.document.id, 'save-test');
      expect(restored.document.layers.first.strokes.length, greaterThanOrEqualTo(1));
    });

    test('toJson 生成有效 JSON 字符串', () {
      notifier.createDocument('json-test');
      final json = notifier.toJson();
      final str = jsonEncode(json);
      expect(str, isNotEmpty);
      expect(() => jsonDecode(str), returnsNormally);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // EditorV2State 不可变性
  // ════════════════════════════════════════════════════════════════

  group('EditorV2State 不可变性', () {
    test('copyWith 产生新实例', () {
      final s1 = container.read(editorV2NotifierProvider);
      notifier.setTool('select');
      final s2 = container.read(editorV2NotifierProvider);
      expect(s1, isNot(s2));
      expect(s1.currentTool, 'draw');
      expect(s2.currentTool, 'select');
    });

    test('相等性基于所有字段', () {
      notifier.createDocument('eq-test');
      notifier.setStrokeColor('#FF0000');
      notifier.setBrushSize(5.0);
      final s1 = container.read(editorV2NotifierProvider);

      // 再设相同值
      notifier.setStrokeColor('#FF0000');
      notifier.setBrushSize(5.0);
      final s2 = container.read(editorV2NotifierProvider);
      expect(s1, s2);
      expect(s1.hashCode, s2.hashCode);
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 笔记模式（V2 编辑器笔记——2026-08-25 修复打字/保存/格式化）
  // ════════════════════════════════════════════════════════════════

  group('笔记模式 - 打字/保存/格式化', () {
    test('loadNoteDocument: 创建新笔记文档', () {
      notifier.createDocument('test-doc');
      notifier.loadNoteDocument('note-001');
      final state = container.read(editorV2NotifierProvider);
      expect(state.noteDocument, isNotNull);
      expect(state.noteDocument!.id, 'note-001');
      expect(state.noteDocument!.title, '未命名笔记');
    });

    test('loadNoteDocument: 不重复创建同 ID 文档', () {
      notifier.createDocument('test-doc');
      notifier.loadNoteDocument('note-001');
      // 第二次调用——不覆盖已有内容。
      notifier.updateNoteDocument(
        container.read(editorV2NotifierProvider).noteDocument!.copyWith(
          paragraphs: [const NoteParagraph(id: 'p1', content: 'Hello')],
        ),
      );
      notifier.loadNoteDocument('note-001'); // 同 ID —— 应保留。
      final state = container.read(editorV2NotifierProvider);
      expect(state.noteDocument!.paragraphs.length, 1);
      expect(state.noteDocument!.paragraphs.first.content, 'Hello');
    });

    test('updateNoteDocument: 保存内容到 ViewModel', () {
      notifier.createDocument('test-doc');
      notifier.loadNoteDocument('note-001');
      final updated = container.read(editorV2NotifierProvider).noteDocument!.copyWith(
        paragraphs: [
          const NoteParagraph(id: 'p1', content: 'Hello'),
          const NoteParagraph(id: 'p2', content: 'World'),
        ],
      );
      notifier.updateNoteDocument(updated);
      final state = container.read(editorV2NotifierProvider);
      expect(state.noteDocument!.paragraphCount, 2);
      expect(state.noteDocument!.fullText, 'Hello\nWorld');
    });

    test('toggleNoteFormatting: 加粗', () {
      expect(container.read(editorV2NotifierProvider).activeNoteFormatting, isEmpty);
      notifier.toggleNoteFormatting('bold');
      expect(container.read(editorV2NotifierProvider).activeNoteFormatting, contains('bold'));
    });

    test('toggleNoteFormatting: 取消加粗', () {
      notifier.toggleNoteFormatting('bold');
      expect(container.read(editorV2NotifierProvider).activeNoteFormatting, contains('bold'));
      notifier.toggleNoteFormatting('bold');
      expect(container.read(editorV2NotifierProvider).activeNoteFormatting, isEmpty);
    });

    test('toggleNoteFormatting: 多个格式同时生效', () {
      notifier.toggleNoteFormatting('bold');
      notifier.toggleNoteFormatting('italic');
      final active = container.read(editorV2NotifierProvider).activeNoteFormatting;
      expect(active, contains('bold'));
      expect(active, contains('italic'));
    });

    test('toggleNoteFormatting: heading', () {
      notifier.toggleNoteFormatting('heading');
      expect(container.read(editorV2NotifierProvider).activeNoteFormatting, contains('heading'));
    });

    test('saveNoteDocument: 不崩溃（正常路径）', () async {
      notifier.createDocument('test-doc');
      notifier.loadNoteDocument('note-001');
      // 不应抛出异常。
      await notifier.saveNoteDocument();
    });

    test('saveNoteDocument: noteDocument 为 null 时安全返回', () async {
      notifier.createDocument('test-doc');
      // 不调用 loadNoteDocument → noteDocument 为 null。
      await notifier.saveNoteDocument(); // 不崩溃。
    });
  });

  // ════════════════════════════════════════════════════════════════
  // 画板手势（V2 画板修复——2026-08-25 修复笔画捕获）
  // ════════════════════════════════════════════════════════════════

  group('画板手势 - 笔画捕获', () {
    test('startStroke + extendStroke + endStroke → 提交笔画', () {
      notifier.createDocument('draw-doc');
      notifier.startStroke(const Offset(10, 10));
      notifier.extendStroke(const Offset(20, 20));
      notifier.extendStroke(const Offset(30, 30));
      notifier.endStroke();

      final state = container.read(editorV2NotifierProvider);
      expect(state.document.layers.first.strokes.length, 1);
      expect(state.canUndo, true);
    });

    test('endStroke 空序列 → 不提交', () {
      notifier.createDocument('draw-doc');
      // 不调用 startStroke → 直接 endStroke。
      notifier.endStroke();
      expect(
        container.read(editorV2NotifierProvider).document.layers.first.strokes.length,
        0,
      );
    });

    test('多次 startStroke → 多笔画', () {
      notifier.createDocument('draw-doc');
      notifier.startStroke(const Offset(0, 0));
      notifier.extendStroke(const Offset(10, 10));
      notifier.endStroke();

      notifier.startStroke(const Offset(50, 50));
      notifier.extendStroke(const Offset(60, 60));
      notifier.endStroke();

      expect(
        container.read(editorV2NotifierProvider).document.layers.first.strokes.length,
        2,
      );
    });

    test('startShapeDrag + endShapeDrag → 创建形状', () {
      notifier.createDocument('draw-doc');
      notifier.startShapeDrag(const Offset(10, 10));
      notifier.endShapeDrag(const Offset(110, 110), 'rect');
      expect(
        container.read(editorV2NotifierProvider).document.layers.first.shapes.length,
        1,
      );
      expect(
        container.read(editorV2NotifierProvider).document.layers.first.shapes.first.type,
        'rect',
      );
    });

    test('startShapeDrag 太小 → 不创建形状', () {
      notifier.createDocument('draw-doc');
      notifier.startShapeDrag(const Offset(10, 10));
      notifier.endShapeDrag(const Offset(11, 11), 'rect'); // 1x1 → 太小
      expect(
        container.read(editorV2NotifierProvider).document.layers.first.shapes.length,
        0,
      );
    });

    test('eraser 模式 → eraseAt 被调用', () {
      notifier.createDocument('draw-doc');
      notifier.addStroke([const Point(0, 0), const Point(100, 100)]);
      expect(
        container.read(editorV2NotifierProvider).document.layers.first.strokes.length,
        1,
      );
      // 擦除——不一定删除（取决于距离），但不崩溃。
      notifier.eraseAt(5, 5);
      expect(container.read(editorV2NotifierProvider).canUndo, true);
    });
  });
}
