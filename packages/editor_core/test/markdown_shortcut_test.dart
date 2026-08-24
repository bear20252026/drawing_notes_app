import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// AFFiNE 借鉴——MarkdownShortcutService 测试（纯逻辑——不搞崩）。
void main() {
  test('标题：# 开头 → heading（去前缀）', () {
    const service = MarkdownShortcutService();
    final r = service.parse('# 我的标题');
    expect(r.blockType, SlashBlockType.heading);
    expect(r.content, '我的标题');
    expect(MarkdownShortcutService.isHeading('# 标题'), true);
  });

  test('标题：多级（## / ###）', () {
    const service = MarkdownShortcutService();
    final r2 = service.parse('## 二级标题');
    expect(r2.blockType, SlashBlockType.heading);
    expect(r2.content, '二级标题');
    final r3 = service.parse('### 三级标题');
    expect(r3.blockType, SlashBlockType.heading);
    expect(r3.content, '三级标题');
  });

  test('列表：- / * 开头 → list', () {
    const service = MarkdownShortcutService();
    final r1 = service.parse('- 列表项');
    expect(r1.blockType, SlashBlockType.list);
    expect(r1.content, '列表项');
    final r2 = service.parse('* 星号列表');
    expect(r2.blockType, SlashBlockType.list);
    expect(MarkdownShortcutService.isList('- 项'), true);
    expect(MarkdownShortcutService.isList('* 项'), true);
  });

  test('待办：[] / [x] → list（todo）', () {
    const service = MarkdownShortcutService();
    final r1 = service.parse('[] 待办事项');
    expect(r1.blockType, SlashBlockType.list);
    expect(r1.content, '待办事项');
    final r2 = service.parse('[x] 已完成');
    expect(r2.blockType, SlashBlockType.list);
    expect(r2.content, '已完成');
    expect(MarkdownShortcutService.isTodo('[] 待办'), true);
    expect(MarkdownShortcutService.isTodo('[x] 完成'), true);
  });

  test('正文：无前缀 → paragraph', () {
    const service = MarkdownShortcutService();
    final r = service.parse('普通段落文字');
    expect(r.blockType, SlashBlockType.paragraph);
    expect(r.content, '普通段落文字');
  });

  test('MarkdownParseResult：相等性', () {
    const a = MarkdownParseResult(blockType: SlashBlockType.heading, content: '标题');
    const b = MarkdownParseResult(blockType: SlashBlockType.heading, content: '标题');
    expect(a, b);
  });
}
