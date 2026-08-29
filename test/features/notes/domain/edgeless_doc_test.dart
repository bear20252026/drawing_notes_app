import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/edgeless_doc.dart';

NoteBlockDoc _doc(String id, {String title = 'Doc'}) => NoteBlockDoc(
      id: id,
      title: title,
      body: [NoteBlock.textBlock('b1', text: 'hello')],
      createdAt: DateTime(2026, 8, 28),
      updatedAt: DateTime(2026, 8, 28),
    );

void main() {
  const viewport = Size(800, 600);

  group('EdgelessCamera', () {
    test('initial: zoom=1, pan=0,0', () {
      const c = EdgelessCamera.initial;
      expect(c.zoom, 1.0);
      expect(c.panX, 0.0);
      expect(c.panY, 0.0);
    });

    test('world↔screen 往返（zoom=1, pan=0）', () {
      const c = EdgelessCamera();
      const world = Offset(123, 456);
      final screen = c.worldToScreen(world, viewport);
      final back = c.screenToWorld(screen, viewport);
      expect(back.dx, closeTo(world.dx, 1e-9));
      expect(back.dy, closeTo(world.dy, 1e-9));
    });

    test('world↔screen 往返（zoom=2, pan=100,50）', () {
      const c = EdgelessCamera(zoom: 2.0, panX: 100, panY: 50);
      for (final w in const [Offset(0, 0), Offset(500, 400), Offset(-30, 20)]) {
        final back = c.screenToWorld(c.worldToScreen(w, viewport), viewport);
        expect(back.dx, closeTo(w.dx, 1e-9));
        expect(back.dy, closeTo(w.dy, 1e-9));
      }
    });

    test('zoom=2 时屏幕坐标放大', () {
      const c = EdgelessCamera(zoom: 2.0);
      // 视口中心 (400,300) 对应 pan (0,0)；世界 (100,0) 应在中心右侧 200px
      final screen = c.worldToScreen(const Offset(100, 0), viewport);
      expect(screen.dx, closeTo(600, 1e-9));
      expect(screen.dy, closeTo(300, 1e-9));
    });

    test('translated 增量平移 pan', () {
      const c = EdgelessCamera();
      final c2 = c.translated(10, -20);
      expect(c2.panX, 10);
      expect(c2.panY, -20);
      expect(c2.zoom, 1.0);
    });

    test('zoomedBy 以 focusWorld 为锚点 —— 锚点屏幕位置不变', () {
      const c = EdgelessCamera(zoom: 1.0, panX: 0, panY: 0);
      const focus = Offset(200, 100);
      final anchorScreen = c.worldToScreen(focus, viewport);
      final c2 = c.zoomedBy(2.0, focusWorld: focus);
      final anchorScreen2 = c2.worldToScreen(focus, viewport);
      expect(anchorScreen2.dx, closeTo(anchorScreen.dx, 1e-9));
      expect(anchorScreen2.dy, closeTo(anchorScreen.dy, 1e-9));
      expect(c2.zoom, 2.0);
    });

    test('zoomedBy 无焦点时 pan 不变', () {
      const c = EdgelessCamera(zoom: 1.0, panX: 5, panY: 7);
      final c2 = c.zoomedBy(3.0);
      expect(c2.zoom, 3.0);
      expect(c2.panX, 5);
      expect(c2.panY, 7);
    });

    test('fittedTo 使 worldRect 完整可见并居中', () {
      const c = EdgelessCamera();
      final worldRect = Rect.fromLTWH(0, 0, 400, 300);
      final c2 = c.fittedTo(worldRect, viewport, padding: 40);
      // 可用视口 720x520；zoom = min(720/400, 520/300) = min(1.8, 1.733) = 1.733
      expect(c2.zoom, closeTo(520 / 300, 1e-9));
      // rect 中心 (200,150) 应映射到视口中心 (400,300)
      final centerScreen = c2.worldToScreen(worldRect.center, viewport);
      expect(centerScreen.dx, closeTo(400, 1e-9));
      expect(centerScreen.dy, closeTo(300, 1e-9));
      // 四个角都在视口内（含 padding）
      for (final corner in [
        worldRect.topLeft,
        worldRect.topRight,
        worldRect.bottomLeft,
        worldRect.bottomRight,
      ]) {
        final s = c2.worldToScreen(corner, viewport);
        expect(s.dx, greaterThanOrEqualTo(40 - 1e-6));
        expect(s.dx, lessThanOrEqualTo(800 - 40 + 1e-6));
        expect(s.dy, greaterThanOrEqualTo(40 - 1e-6));
        expect(s.dy, lessThanOrEqualTo(600 - 40 + 1e-6));
      }
    });

    test('fittedTo zoom 被 clamp 到 [0.1, 10]', () {
      const c = EdgelessCamera();
      // 极小 rect → zoom 会很大，应被 clamp 到 10
      final tiny = c.fittedTo(Rect.fromLTWH(0, 0, 1, 1), viewport);
      expect(tiny.zoom, lessThanOrEqualTo(10.0));
      // 极大 rect → zoom 会很小，应被 clamp 到 0.1
      final huge = c.fittedTo(Rect.fromLTWH(0, 0, 100000, 100000), viewport);
      expect(huge.zoom, greaterThanOrEqualTo(0.1));
    });

    test('== 与 hashCode', () {
      const a = EdgelessCamera(zoom: 2.0, panX: 3, panY: 4);
      const b = EdgelessCamera(zoom: 2.0, panX: 3, panY: 4);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('NoteFrame', () {
    test('rect / center / contains', () {
      final f = NoteFrame(
        id: 'f1',
        x: 10,
        y: 20,
        w: 100,
        h: 50,
        doc: _doc('d1'),
        zIndex: 3,
      );
      expect(f.rect, Rect.fromLTWH(10, 20, 100, 50));
      expect(f.center, const Offset(60, 45));
      expect(f.contains(const Offset(50, 40)), isTrue);
      expect(f.contains(const Offset(200, 200)), isFalse);
    });

    test('toJson/fromJson 往返', () {
      final f = NoteFrame(
        id: 'f1',
        x: 1.5,
        y: 2.5,
        w: 3.5,
        h: 4.5,
        doc: _doc('d1'),
        zIndex: 7,
        background: '#AABBCC',
      );
      final f2 = NoteFrame.fromJson(f.toJson());
      expect(f2, f);
    });

    test('copyWith', () {
      final f = NoteFrame(
        id: 'f1', x: 0, y: 0, w: 10, h: 10, doc: _doc('d1'), zIndex: 1,
      );
      final f2 = f.copyWith(x: 99, zIndex: 5);
      expect(f2.x, 99);
      expect(f2.zIndex, 5);
      expect(f2.y, 0); // 未变
      expect(f, isNot(f2));
    });
  });

  group('EdgelessDoc', () {
    test('empty 无 initialDoc → 空帧', () {
      final doc = EdgelessDoc.empty('e1');
      expect(doc.frames, isEmpty);
      expect(doc.camera, EdgelessCamera.initial);
      expect(doc.nextZIndex, 1);
    });

    test('empty 有 initialDoc → 自动 addFrame 一个', () {
      final doc = EdgelessDoc.empty('e1', initialDoc: _doc('d1'));
      expect(doc.frames, hasLength(1));
      expect(doc.frames.first.doc.id, 'd1');
      expect(doc.nextZIndex, 2);
    });

    test('addFrame 默认级联偏移防重叠', () {
      var doc = EdgelessDoc.empty('e1');
      doc = doc.addFrame(_doc('d1'));
      doc = doc.addFrame(_doc('d2'));
      doc = doc.addFrame(_doc('d3'));
      expect(doc.frames, hasLength(3));
      // 第 n 帧起点 (80+n*32, 80+n*32)
      expect(doc.frames[0].x, closeTo(80 + 0 * 32, 1e-9));
      expect(doc.frames[1].x, closeTo(80 + 1 * 32, 1e-9));
      expect(doc.frames[2].x, closeTo(80 + 2 * 32, 1e-9));
      // zIndex 递增
      expect(doc.frames[0].zIndex, 1);
      expect(doc.frames[1].zIndex, 2);
      expect(doc.frames[2].zIndex, 3);
      expect(doc.nextZIndex, 4);
    });

    test('addFrame 指定 at', () {
      var doc = EdgelessDoc.empty('e1');
      doc = doc.addFrame(_doc('d1'), at: const Offset(500, 600));
      expect(doc.frames.first.x, 500);
      expect(doc.frames.first.y, 600);
      expect(doc.frames.first.w, kDefaultFrameWidth);
      expect(doc.frames.first.h, kDefaultFrameHeight);
    });

    test('removeFrame 移除并清除选择', () {
      var doc = EdgelessDoc.empty('e1')
          .addFrame(_doc('d1'))
          .addFrame(_doc('d2'));
      final id1 = doc.frames[0].id;
      final id2 = doc.frames[1].id;
      doc = doc.select(id1);
      doc = doc.removeFrame(id1);
      expect(doc.frames, hasLength(1));
      expect(doc.frameById(id1), isNull);
      expect(doc.selectedFrameId, isNull); // 选择已清除
      expect(doc.frameById(id2), isNotNull);
    });

    test('removeFrame 不存在则返回同一实例', () {
      final doc = EdgelessDoc.empty('e1').addFrame(_doc('d1'));
      final doc2 = doc.removeFrame('nope');
      expect(identical(doc, doc2), isTrue);
    });

    test('moveFrame', () {
      var doc = EdgelessDoc.empty('e1').addFrame(_doc('d1'));
      final id = doc.frames.first.id;
      doc = doc.moveFrame(id, const Offset(111, 222));
      expect(doc.frames.first.x, 111);
      expect(doc.frames.first.y, 222);
    });

    test('resizeFrame 最小值约束', () {
      var doc = EdgelessDoc.empty('e1').addFrame(_doc('d1'));
      final id = doc.frames.first.id;
      doc = doc.resizeFrame(id, w: 10, h: 10); // 远小于最小值
      expect(doc.frames.first.w, kMinFrameWidth);
      expect(doc.frames.first.h, kMinFrameHeight);
      // 正常值保留
      doc = doc.resizeFrame(id, w: 500, h: 400);
      expect(doc.frames.first.w, 500);
      expect(doc.frames.first.h, 400);
    });

    test('updateFrameDoc', () {
      var doc = EdgelessDoc.empty('e1').addFrame(_doc('d1'));
      final id = doc.frames.first.id;
      final newDoc = _doc('d_new', title: 'Updated');
      doc = doc.updateFrameDoc(id, newDoc);
      expect(doc.frameById(id)!.doc.title, 'Updated');
    });

    test('bringToFront 置于顶层', () {
      var doc = EdgelessDoc.empty('e1')
          .addFrame(_doc('d1')) // z=1
          .addFrame(_doc('d2')) // z=2
          .addFrame(_doc('d3')); // z=3
      final id1 = doc.frames[0].id;
      doc = doc.bringToFront(id1); // → z=4
      expect(doc.frameById(id1)!.zIndex, 4);
    });

    test('sendToBack 置于底层', () {
      var doc = EdgelessDoc.empty('e1')
          .addFrame(_doc('d1')) // z=1
          .addFrame(_doc('d2')) // z=2
          .addFrame(_doc('d3')); // z=3
      final id3 = doc.frames[2].id;
      doc = doc.sendToBack(id3); // → z=0
      expect(doc.frameById(id3)!.zIndex, 0);
    });

    test('select / 取消选择', () {
      var doc = EdgelessDoc.empty('e1').addFrame(_doc('d1'));
      final id = doc.frames.first.id;
      doc = doc.select(id);
      expect(doc.selectedFrameId, id);
      doc = doc.select(null);
      expect(doc.selectedFrameId, isNull);
    });

    test('hitTest 重叠取最上层', () {
      var doc = EdgelessDoc.empty('e1');
      // 两个重叠帧：f1 在下 (z=1)，f2 在上 (z=2)
      doc = doc.addFrame(_doc('d1'), at: const Offset(0, 0)); // f1 z=1
      doc = doc.addFrame(_doc('d2'), at: const Offset(0, 0)); // f2 z=2
      final hit = doc.hitTest(const Offset(10, 10));
      expect(hit, isNotNull);
      expect(hit!.doc.id, 'd2'); // 上层
    });

    test('hitTest 未命中返回 null', () {
      final doc = EdgelessDoc.empty('e1')
          .addFrame(_doc('d1'), at: const Offset(0, 0));
      expect(doc.hitTest(const Offset(9999, 9999)), isNull);
    });

    test('framesSortedByZ 升序', () {
      var doc = EdgelessDoc.empty('e1')
          .addFrame(_doc('d1')) // z=1
          .addFrame(_doc('d2')) // z=2
          .addFrame(_doc('d3')); // z=3
      // 把 z=1 的帧提到最前
      final id1 = doc.frames[0].id;
      doc = doc.bringToFront(id1); // z=4
      final sorted = doc.framesSortedByZ;
      for (var i = 1; i < sorted.length; i++) {
        expect(sorted[i].zIndex, greaterThan(sorted[i - 1].zIndex));
      }
    });

    test('操作不修改原实例（不可变）', () {
      final doc = EdgelessDoc.empty('e1').addFrame(_doc('d1'));
      final id = doc.frames.first.id;
      final originalFrames = doc.frames;
      final originalX = doc.frames.first.x;

      doc.moveFrame(id, const Offset(999, 999));
      doc.removeFrame(id);
      doc.bringToFront(id);

      // 原实例不变
      expect(doc.frames, originalFrames);
      expect(doc.frames.first.x, originalX);
      expect(identical(doc.frames, originalFrames), isTrue);
    });

    test('toJson/fromJson 往返', () {
      final doc = EdgelessDoc.empty('e1')
          .addFrame(_doc('d1'))
          .addFrame(_doc('d2'))
          .select('frame_1');
      final json = doc.toJson();
      final doc2 = EdgelessDoc.fromJson(json);
      expect(doc2.id, doc.id);
      expect(doc2.frames.length, doc.frames.length);
      expect(doc2.frames[0].doc.id, doc.frames[0].doc.id);
      expect(doc2.frames[1].zIndex, doc.frames[1].zIndex);
      expect(doc2.selectedFrameId, 'frame_1');
      expect(doc2.nextZIndex, doc.nextZIndex);
      expect(doc2.camera, doc.camera);
    });
  });
}
