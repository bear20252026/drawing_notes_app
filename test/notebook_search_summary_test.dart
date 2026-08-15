import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/notes/domain/notebook.dart';

/// 搜索增强（2026-08-16）：Notebook.buildSearchSummary 脱敏摘要纯函数
/// 单测——标题 + 文本摘要，截断防敏感正文细节全量暴露。
void main() {
  test('脱敏摘要：标题入摘要', () {
    final notebook = Notebook(id: 'n1', title: '会议记录');
    final summary = Notebook.buildSearchSummary(notebook);
    expect(summary, contains('会议记录'));
  });

  test('脱敏摘要：超长标题截断（≤ 200 字符）', () {
    final longTitle = '长' * 300;
    final long = Notebook(id: 'n2', title: longTitle);
    final s = Notebook.buildSearchSummary(long);
    expect(s.length, lessThanOrEqualTo(Notebook.searchSummaryMaxChars));
    expect(s.length, 200);
  });
}
