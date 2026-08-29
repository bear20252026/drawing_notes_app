// M9-3 time_ago 纯函数单测。

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/time_ago.dart';

void main() {
  final base = DateTime(2026, 8, 28, 12, 0, 0);

  String ago(DateTime t) => timeAgo(t, now: base);

  test('刚刚', () {
    expect(ago(base), '刚刚');
    expect(ago(base.subtract(const Duration(seconds: 30))), '刚刚');
  });

  test('N 分钟前', () {
    expect(ago(base.subtract(const Duration(minutes: 5))), '5 分钟前');
    expect(ago(base.subtract(const Duration(minutes: 45))), '45 分钟前');
  });

  test('N 小时前', () {
    expect(ago(base.subtract(const Duration(hours: 3))), '3 小时前');
    expect(ago(base.subtract(const Duration(hours: 16))), '16 小时前');
  });

  test('昨天', () {
    expect(ago(base.subtract(const Duration(hours: 25))), '昨天');
    expect(ago(base.subtract(const Duration(days: 1))), '昨天');
  });

  test('N 天前', () {
    expect(ago(base.subtract(const Duration(days: 3))), '3 天前');
    expect(ago(base.subtract(const Duration(days: 6))), '6 天前');
  });

  test('上周', () {
    expect(ago(base.subtract(const Duration(days: 8))), '上周');
    expect(ago(base.subtract(const Duration(days: 10))), '上周');
  });

  test('N 周前', () {
    expect(ago(base.subtract(const Duration(days: 15))), '2 周前');
    expect(ago(base.subtract(const Duration(days: 25))), '3 周前');
  });

  test('N 月前', () {
    expect(ago(base.subtract(const Duration(days: 45))), '1 月前');
    expect(ago(base.subtract(const Duration(days: 200))), '6 月前');
  });

  test('N 年前', () {
    expect(ago(base.subtract(const Duration(days: 400))), '1 年前');
    expect(ago(base.subtract(const Duration(days: 1000))), '2 年前');
  });
}
