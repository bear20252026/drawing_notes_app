// 本地 ID 生成器（local_id_generator.dart）单测：
// 唯一性（1000 连续无碰撞）/ 文件名安全字符集 / prefix_timestamp_seq_entropy 格式。

import 'package:drawing_notes_app/core/storage/local_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('连续生成 1000 个 ID 无碰撞（同前缀）', () {
    final ids = List.generate(1000, (_) => LocalIdGenerator.next('doc'));

    expect(ids.toSet().length, 1000, reason: '时间戳+序号+安全随机段应保证唯一');
  });

  test('不同前缀的 ID 也不相互碰撞', () {
    final docs = List.generate(200, (_) => LocalIdGenerator.next('doc'));
    final notebooks = List.generate(200, (_) => LocalIdGenerator.next('nb'));

    expect(docs.toSet().length, 200);
    expect(notebooks.toSet().length, 200);
    expect(docs.toSet().intersection(notebooks.toSet()), isEmpty);
  });

  test('格式：prefix_timestamp_sequence_entropy 四段、下划线分隔', () {
    final id = LocalIdGenerator.next('doc');
    final parts = id.split('_');

    expect(parts, hasLength(4));
    expect(parts.first, 'doc');
    // 时间戳（µs epoch 的 36 进制，10 位左右）。
    expect(parts[1], matches(RegExp(r'^[0-9a-z]{8,12}$')));
    // 进程序号（0xFFFFFF 的 36 进制，padLeft(4)）。
    expect(parts[2], matches(RegExp(r'^[0-9a-z]{4,5}$')));
    // 安全随机段（32-bit 的 36 进制，padLeft(7)——恒 7 位）。
    expect(parts[3], matches(RegExp(r'^[0-9a-z]{7}$')));
  });

  test('字符集只含字母数字与下划线（文件名安全，无路径歧义）', () {
    final ids = List.generate(500, (_) => LocalIdGenerator.next('nb'));
    final pattern = RegExp(r'^[A-Za-z0-9_]+$');

    for (final id in ids) {
      expect(id, matches(pattern), reason: 'ID 将直接拼入文件路径');
    }
  });

  test('前缀原样保留在 ID 首段', () {
    expect(LocalIdGenerator.next('thumb').startsWith('thumb_'), isTrue);
    expect(LocalIdGenerator.next('write').startsWith('write_'), isTrue);
  });

  test('高速连续生成：微秒级相邻调用也不重复（进程内序号兜底）', () {
    final ids = <String>{
      for (var i = 0; i < 50; i++) LocalIdGenerator.next('burst'),
    };

    expect(ids.length, 50, reason: '同一微秒内的连续创建由序号段区分');
  });
}
