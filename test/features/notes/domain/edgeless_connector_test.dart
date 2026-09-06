import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/notes/domain/edgeless_connector.dart';

void main() {
  group('connectorAnchorPoint', () {
    // 帧矩形：左上(100,200)，宽300 高100 → 中心(250,250)
    const rect = Rect.fromLTWH(100, 200, 300, 100);

    test('top 锚点为上边中点', () {
      expect(
        connectorAnchorPoint(rect, ConnectorAnchor.top),
        const Offset(250, 200),
      );
    });

    test('bottom 锚点为下边中点', () {
      expect(
        connectorAnchorPoint(rect, ConnectorAnchor.bottom),
        const Offset(250, 300),
      );
    });

    test('left 锚点为左边中点', () {
      expect(
        connectorAnchorPoint(rect, ConnectorAnchor.left),
        const Offset(100, 250),
      );
    });

    test('right 锚点为右边中点', () {
      expect(
        connectorAnchorPoint(rect, ConnectorAnchor.right),
        const Offset(400, 250),
      );
    });
  });

  group('autoConnectorAnchors', () {
    const source = Rect.fromLTWH(0, 0, 100, 100);
    const target = Rect.fromLTWH(400, 0, 100, 100);

    test('来源在左、目标在右（水平占优）→ (right, left)', () {
      final a = autoConnectorAnchors(source, target);
      expect(a.from, ConnectorAnchor.right);
      expect(a.to, ConnectorAnchor.left);
    });

    test('来源在右、目标在左（水平占优）→ (left, right)', () {
      final a = autoConnectorAnchors(target, source);
      expect(a.from, ConnectorAnchor.left);
      expect(a.to, ConnectorAnchor.right);
    });

    test('来源在上、目标在下（垂直占优）→ (bottom, top)', () {
      const s = Rect.fromLTWH(0, 0, 100, 100);
      const t = Rect.fromLTWH(20, 400, 100, 100);
      final a = autoConnectorAnchors(s, t);
      expect(a.from, ConnectorAnchor.bottom);
      expect(a.to, ConnectorAnchor.top);
    });

    test('来源在下、目标在上（垂直占优）→ (top, bottom)', () {
      const s = Rect.fromLTWH(20, 400, 100, 100);
      const t = Rect.fromLTWH(0, 0, 100, 100);
      final a = autoConnectorAnchors(s, t);
      expect(a.from, ConnectorAnchor.top);
      expect(a.to, ConnectorAnchor.bottom);
    });
  });

  group('NoteConnector model', () {
    const c = NoteConnector(
      id: 'c1',
      fromFrameId: 'f1',
      toFrameId: 'f2',
      fromAnchor: ConnectorAnchor.right,
      toAnchor: ConnectorAnchor.left,
      label: '引用',
    );

    test('toJson/fromJson 往返保留全部字段', () {
      final back = NoteConnector.fromJson(c.toJson());
      expect(back, c);
      expect(back.label, '引用');
    });

    test('fromJson 缺省样式用默认值', () {
      final back = NoteConnector.fromJson({
        'id': 'c2',
        'fromFrameId': 'f1',
        'toFrameId': 'f3',
        'fromAnchor': 'bottom',
        'toAnchor': 'top',
      });
      expect(back.color, kDefaultConnectorColor);
      expect(back.width, kDefaultConnectorWidth);
      expect(back.label, isNull);
    });

    test('isSelfLoop 判定自环', () {
      const selfLoop = NoteConnector(
        id: 'c3',
        fromFrameId: 'f1',
        toFrameId: 'f1',
        fromAnchor: ConnectorAnchor.right,
        toAnchor: ConnectorAnchor.left,
      );
      expect(selfLoop.isSelfLoop, isTrue);
      expect(c.isSelfLoop, isFalse);
    });

    test('copyWith 可改字段、clearLabel 可清空标签', () {
      final renamed = c.copyWith(label: '新标签');
      expect(renamed.label, '新标签');
      expect(renamed.fromFrameId, 'f1');
      final cleared = c.copyWith(clearLabel: true);
      expect(cleared.label, isNull);
    });

    test('operator== 依据语义字段，不同实例等值相等', () {
      const same = NoteConnector(
        id: 'c1',
        fromFrameId: 'f1',
        toFrameId: 'f2',
        fromAnchor: ConnectorAnchor.right,
        toAnchor: ConnectorAnchor.left,
        label: '引用',
      );
      expect(same, c);
      expect(c.copyWith(width: 4), isNot(c));
    });
  });
}
