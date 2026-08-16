import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// 专家 I-006（2026-08-16——批次 A）：editor_core 纯 Dart 引导——
/// DocumentV2 不可变状态（copyWith 语义 + 原实例不变）。
void main() {
  test('DocumentV2：不可变——copyWith 返回新实例原实例不变', () {
    const doc = DocumentV2(id: 'n1', pageCount: 1);
    final updated = doc.copyWith(pageCount: 2, revision: 1);
    // 原实例不变（不可变约定）。
    expect(doc.pageCount, 1);
    expect(doc.revision, 0);
    // 新实例反映变更。
    expect(updated.pageCount, 2);
    expect(updated.revision, 1);
    expect(updated.id, 'n1');
  });

  test('DocumentV2：相等性基于字段（不可变快照比较）', () {
    const a = DocumentV2(id: 'n1', pageCount: 2, revision: 1);
    const b = DocumentV2(id: 'n1', pageCount: 2, revision: 1);
    const c = DocumentV2(id: 'n1', pageCount: 3, revision: 1);
    expect(a, b);
    expect(a == c, isFalse);
  });
}
