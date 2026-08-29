import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/notes/domain/edgeless_group.dart';

void main() {
  group('EdgelessGroup model', () {
    const g = EdgelessGroup(
      id: 'group_1',
      frameIds: ['f1', 'f2'],
      name: '设计',
      color: '#4CAF50',
    );

    test('contains 判定成员', () {
      expect(g.contains('f1'), isTrue);
      expect(g.contains('f2'), isTrue);
      expect(g.contains('f3'), isFalse);
    });

    test('toJson/fromJson 往返保留字段', () {
      final back = EdgelessGroup.fromJson(g.toJson());
      expect(back, g);
      expect(back.name, '设计');
    });

    test('fromJson 缺省 name/color', () {
      final back = EdgelessGroup.fromJson({
        'id': 'g2',
        'frameIds': ['f1', 'f2'],
      });
      expect(back.name, isNull);
      expect(back.color, kDefaultGroupColor);
    });

    test('copyWith 改名/改色/清名', () {
      expect(g.copyWith(name: '新名').name, '新名');
      expect(g.copyWith(color: '#FF0000').color, '#FF0000');
      expect(g.copyWith(clearName: true).name, isNull);
      expect(g.copyWith(frameIds: ['f1']).frameIds, ['f1']);
    });

    test('operator== 依据语义字段', () {
      const same = EdgelessGroup(
        id: 'group_1',
        frameIds: ['f1', 'f2'],
        name: '设计',
        color: '#4CAF50',
      );
      expect(same, g);
      expect(g.copyWith(name: 'x'), isNot(g));
    });
  });

  group('groupBoundsOf', () {
    test('求并集外接矩形', () {
      const a = Rect.fromLTWH(0, 0, 100, 100);
      const b = Rect.fromLTWH(200, 100, 100, 100);
      final r = groupBoundsOf([a, b]);
      expect(r, const Rect.fromLTWH(0, 0, 300, 200));
    });

    test('空输入返回 null', () {
      expect(groupBoundsOf(const []), isNull);
    });

    test('单成员即其矩形', () {
      expect(groupBoundsOf([const Rect.fromLTWH(10, 20, 30, 40)]),
          const Rect.fromLTWH(10, 20, 30, 40));
    });
  });
}
