import 'package:drawing_notes_app/engine/fractional_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generateKeyBetween', () {
    test('起点键为 a0，且排序序言一致', () {
      expect(generateKeyBetween(null, null), 'a0');
      expect(generateKeyBetween(null, 'a1'), 'a0');
    });

    test('生成的键位于 a 与 b 之间（字典序）', () {
      final key = generateKeyBetween('a0', 'a2');
      expect(key.compareTo('a0'), greaterThan(0));
      expect(key.compareTo('a2'), lessThan(0));

      final key2 = generateKeyBetween('a0', 'a1');
      expect(key2.compareTo('a0'), greaterThan(0));
      expect(key2.compareTo('a1'), lessThan(0));
    });

    test('连续插入（置顶方向）始终生成更大键', () {
      String? last;
      final keys = <String>[];
      for (var i = 0; i < 10; i++) {
        last = generateKeyBetween(last, null);
        keys.add(last);
      }
      // 严格升序且互异。
      for (var i = 1; i < keys.length; i++) {
        expect(keys[i].compareTo(keys[i - 1]), greaterThan(0));
      }
    });

    test('连续插入（置底方向）始终生成更小键', () {
      String? first;
      final keys = <String>[];
      for (var i = 0; i < 10; i++) {
        first = generateKeyBetween(null, first);
        keys.add(first);
      }
      for (var i = 1; i < keys.length; i++) {
        expect(keys[i].compareTo(keys[i - 1]), lessThan(0));
      }
    });

    test('a >= b 时抛出 ArgumentError', () {
      expect(() => generateKeyBetween('a2', 'a1'), throwsArgumentError);
      expect(() => generateKeyBetween('a1', 'a1'), throwsArgumentError);
    });
  });

  group('generateNKeysBetween', () {
    test('n=0 返回空，n=1 返回单个键', () {
      expect(generateNKeysBetween(null, null, 0), isEmpty);
      expect(generateNKeysBetween(null, null, 1), hasLength(1));
    });

    test('生成 n 个互异且升序的键，且位于 a 与 b 之间', () {
      final keys = generateNKeysBetween('a0', 'a9', 5);
      expect(keys, hasLength(5));
      for (var i = 1; i < keys.length; i++) {
        expect(keys[i].compareTo(keys[i - 1]), greaterThan(0));
      }
      expect(keys.first.compareTo('a0'), greaterThan(0));
      expect(keys.last.compareTo('a9'), lessThan(0));
    });
  });

  group('validateOrderKey', () {
    test('合法键通过，非法键抛出', () {
      expect(() => validateOrderKey('a0'), returnsNormally);
      expect(() => validateOrderKey('a1'), returnsNormally);
      expect(() => validateOrderKey('a1b'), returnsNormally);
      // 非法字符、尾随零、整数部分长度不足（z 头需要 27 位整数部分）。
      expect(() => validateOrderKey('a-0'), throwsArgumentError);
      expect(() => validateOrderKey('a00'), throwsArgumentError);
      expect(() => validateOrderKey('z99'), throwsArgumentError);
    });
  });

  test('层级重排场景：上移/下移只用相邻键，无需重排全表', () {
    // 模拟一个层级列表：b 在 a 与 c 之间插入新元素。
    final a = generateKeyBetween(null, null); // a0
    final c = generateKeyBetween(a, null); // 更大的键
    final b = generateKeyBetween(a, c); // 插在中间

    expect(b.compareTo(a), greaterThan(0));
    expect(b.compareTo(c), lessThan(0));
    // 原 a、c 键保持不变（这正是 fractionalIndex 相对整数 zOrder 的优势）。
    expect(a, 'a0');
  });
}
