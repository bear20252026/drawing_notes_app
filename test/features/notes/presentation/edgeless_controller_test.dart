// 由 Claude 团队生成 | Drawing Notes App
// EdgelessController 测试：手势（平移/缩放/拖帧）+ 选中 + 帧操作。

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/notes/domain/edgeless_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/presentation/edgeless_controller.dart';

const _viewport = Size(800, 600);

EdgelessDoc _docWithOneFrame() {
  final fdoc = NoteBlockDoc.empty('f1doc', title: '帧1');
  final frame = NoteFrame(
    id: 'f1',
    x: 100,
    y: 100,
    w: 200,
    h: 200,
    doc: fdoc,
    zIndex: 1,
  );
  return EdgelessDoc(id: 'e', frames: [frame], camera: EdgelessCamera.initial);
}

// 初始相机（zoom=1, pan=0,0）下：world = screen - viewportCenter。
// 帧 f1 世界区间 (100,100)-(300,300) => 屏幕区间 (500,400)-(700,600)。屏幕中心
// (600,500) 命中帧；(400,300)（世界 0,0）不在帧上。

void main() {
  group('平移（拖空白）', () {
    test('单指拖空白：相机 pan 跟随焦点移动', () {
      final c = EdgelessController(doc: _docWithOneFrame());
      c.beginGesture(const Offset(400, 300), 1, _viewport); // 世界 0,0，非帧
      c.updateGesture(const Offset(500, 350), 1.0, 1, _viewport);
      expect(c.camera.zoom, 1.0);
      expect(c.camera.panX, closeTo(-100, 1e-6));
      expect(c.camera.panY, closeTo(-50, 1e-6));
    });
  });

  group('缩放（双指）', () {
    test('双指捏合：以焦点为锚缩放，锚点世界点不漂移', () {
      final c = EdgelessController(doc: _docWithOneFrame());
      c.beginGesture(const Offset(400, 300), 1, _viewport);
      c.updateGesture(const Offset(400, 300), 2.0, 2, _viewport);
      expect(c.camera.zoom, closeTo(2, 1e-6));
      // 焦点 (400,300) 是世界 0,0；放大后其屏幕位置不变（pan 0,0）
      expect(c.camera.panX, closeTo(0, 1e-6));
      expect(c.camera.panY, closeTo(0, 1e-6));
    });

    test('缩放在 min/maxZoom 之间被限制', () {
      final c = EdgelessController(doc: _docWithOneFrame(), maxZoom: 3);
      c.beginGesture(const Offset(400, 300), 1, _viewport);
      c.updateGesture(const Offset(400, 300), 10.0, 2, _viewport);
      expect(c.camera.zoom, closeTo(3, 1e-6));
    });
  });

  group('拖帧', () {
    test('单指按在帧上拖动：移动该帧（按世界增量）', () {
      final c = EdgelessController(doc: _docWithOneFrame());
      // 屏幕 (600,500) → 世界 (200,200) 命中 f1
      c.beginGesture(const Offset(600, 500), 1, _viewport);
      c.updateGesture(const Offset(650, 520), 1.0, 1, _viewport); // 屏幕增量 (50,20)
      final frame = c.doc.frameById('f1')!;
      expect(frame.x, closeTo(150, 1e-6));
      expect(frame.y, closeTo(120, 1e-6));
    });

    test('拖帧时第二指加入 → 取消拖帧改为缩放，帧不移动', () {
      final c = EdgelessController(doc: _docWithOneFrame());
      c.beginGesture(const Offset(600, 500), 1, _viewport);
      c.updateGesture(const Offset(650, 520), 1.0, 1, _viewport); // 先在拖帧
      expect(c.doc.frameById('f1')!.x, closeTo(150, 1e-6));
      // 第二指加入
      c.updateGesture(const Offset(650, 520), 2.0, 2, _viewport);
      final frame = c.doc.frameById('f1')!;
      expect(frame.x, closeTo(150, 1e-6)); // 不再移动
      expect(c.camera.zoom, closeTo(2, 1e-6));
    });
  });

  group('点按选中', () {
    test('点中帧 → 选中并置顶', () {
      final c = EdgelessController(doc: _docWithOneFrame());
      c.tapAt(const Offset(600, 500), _viewport); // 命中 f1
      expect(c.selectedFrameId, 'f1');
      expect(c.doc.frameById('f1')!.zIndex, 2); // bringToFront 后
    });

    test('点空白 → 取消选中', () {
      final c = EdgelessController(doc: _docWithOneFrame());
      c.tapAt(const Offset(600, 500), _viewport);
      expect(c.selectedFrameId, 'f1');
      c.tapAt(const Offset(400, 300), _viewport); // 世界 0,0 空白
      expect(c.selectedFrameId, isNull);
    });
  });

  group('帧操作', () {
    test('addFrame 增加一帧并更新 onChanged', () {
      EdgelessDoc? latest;
      final c = EdgelessController(doc: _docWithOneFrame(), onChanged: (d) => latest = d);
      c.addFrame(NoteBlockDoc.empty('new'));
      expect(c.doc.frames.length, 2);
      expect(latest!.frames.length, 2); // onChanged 收到新 doc
    });

    test('removeFrame 移除', () {
      final c = EdgelessController(doc: _docWithOneFrame());
      c.removeFrame('f1');
      expect(c.doc.frames, isEmpty);
    });

    test('resizeFrame 调整尺寸并触发 onChanged（含 topLeft 移动）', () {
      EdgelessDoc? latest;
      final c = EdgelessController(doc: _docWithOneFrame(), onChanged: (d) => latest = d);
      c.resizeFrame('f1', topLeft: const Offset(120, 140), w: 300, h: 220);
      final f = c.doc.frameById('f1')!;
      expect(f.x, 120);
      expect(f.y, 140);
      expect(f.w, 300);
      expect(f.h, 220);
      expect(latest!.frameById('f1')!.w, 300);
    });

    test('setFrameBackground 设置背景色并触发 onChanged', () {
      EdgelessDoc? latest;
      final c = EdgelessController(doc: _docWithOneFrame(), onChanged: (d) => latest = d);
      c.setFrameBackground('f1', '#E3F2FD');
      expect(c.doc.frameById('f1')!.background, '#E3F2FD');
      expect(latest!.frameById('f1')!.background, '#E3F2FD');
    });
  });

  group('连接线', () {
    EdgelessDoc twoFrames() {
      final f2 = NoteFrame(
        id: 'f2',
        x: 400,
        y: 100,
        w: 200,
        h: 200,
        doc: NoteBlockDoc.empty('f2doc'),
        zIndex: 1,
      );
      return EdgelessDoc(
        id: 'e',
        frames: [..._docWithOneFrame().frames, f2],
        camera: EdgelessCamera.initial,
      );
    }

    test('beginConnect 进入连线模式并选中起点帧', () {
      final c = EdgelessController(doc: twoFrames());
      c.beginConnect('f1');
      expect(c.connectMode, isTrue);
      expect(c.connectSourceFrameId, 'f1');
      expect(c.selectedFrameId, 'f1');
    });

    test('点按目标帧 → 自动建线并退出连线模式', () {
      final c = EdgelessController(doc: twoFrames());
      c.beginConnect('f1');
      // f2 世界 (400,100)-(600,300) → 屏幕 (800,400)-(1000,600)；中心 (900,500)
      c.tapAt(const Offset(900, 500), _viewport);
      expect(c.connectMode, isFalse);
      final conn = c.connectors.single;
      expect(conn.fromFrameId, 'f1');
      expect(conn.toFrameId, 'f2');
      expect(c.doc.hasConnectorBetween('f1', 'f2'), isTrue);
    });

    test('连线模式下点空白 → 取消且不建线', () {
      final c = EdgelessController(doc: twoFrames());
      c.beginConnect('f1');
      c.tapAt(const Offset(400, 300), _viewport); // 世界 0,0 空白
      expect(c.connectMode, isFalse);
      expect(c.connectors, isEmpty);
    });

    test('连线模式下点击起点自身 → 不建自环并退出', () {
      final c = EdgelessController(doc: twoFrames());
      c.beginConnect('f1');
      c.tapAt(const Offset(600, 500), _viewport); // 命中 f1 自身
      expect(c.connectMode, isFalse);
      expect(c.connectors, isEmpty);
    });

    test('addConnector / removeConnector 透传并能被 onChanged 捕获', () {
      EdgelessDoc? latest;
      final c = EdgelessController(doc: twoFrames(), onChanged: (d) => latest = d);
      c.addConnector(fromFrameId: 'f1', toFrameId: 'f2');
      expect(c.connectors, hasLength(1));
      expect(latest!.connectors, hasLength(1));
      final id = c.connectors.single.id;
      c.removeConnector(id);
      expect(c.connectors, isEmpty);
      expect(latest!.connectors, isEmpty);
    });

    test('cancelConnect 退出连线模式', () {
      final c = EdgelessController(doc: twoFrames());
      c.beginConnect('f1');
      c.cancelConnect();
      expect(c.connectMode, isFalse);
      expect(c.connectors, isEmpty);
    });
  });

  group('群组框', () {
    EdgelessDoc twoFrames() {
      final f2 = NoteFrame(
        id: 'f2',
        x: 400,
        y: 100,
        w: 200,
        h: 200,
        doc: NoteBlockDoc.empty('f2doc'),
        zIndex: 1,
      );
      return EdgelessDoc(
        id: 'e',
        frames: [..._docWithOneFrame().frames, f2],
        camera: EdgelessCamera.initial,
      );
    }

    test('addGroup 创建群组并被 onChanged 捕获', () {
      EdgelessDoc? latest;
      final c = EdgelessController(doc: twoFrames(), onChanged: (d) => latest = d);
      c.addGroup(['f1', 'f2'], name: '设计');
      expect(c.groups, hasLength(1));
      expect(c.groups.single.name, '设计');
      expect(latest!.groups.single.contains('f1'), isTrue);
    });

    test('removeGroup / renameGroup / setGroupColor 透传', () {
      final c = EdgelessController(doc: twoFrames());
      c.addGroup(['f1', 'f2']);
      final id = c.groups.single.id;
      c.renameGroup(id, '新名');
      expect(c.groups.single.name, '新名');
      c.setGroupColor(id, '#FF0000');
      expect(c.groups.single.color, '#FF0000');
      c.removeGroup(id);
      expect(c.groups, isEmpty);
    });
  });
}
