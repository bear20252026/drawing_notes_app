import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// AFFiNE 借鉴——SlashCommandService 测试（纯逻辑——不搞崩）。
void main() {
  test('命令列表：6 种块（段落/标题/列表/引用/代码/分隔线）', () {
    expect(SlashCommandService.commands.length, 6);
    expect(
      SlashCommandService.commands.map((c) => c.type).toSet(),
      {
        SlashBlockType.paragraph, SlashBlockType.heading, SlashBlockType.list,
        SlashBlockType.quote, SlashBlockType.code, SlashBlockType.divider,
      },
    );
  });

  test('isSlash：/ 开头判断', () {
    expect(SlashCommandService.isSlash('/标题'), true);
    expect(SlashCommandService.isSlash('标题'), false);
    expect(SlashCommandService.isSlash(''), false);
  });

  test('match：/ 后关键词匹配命令（中文/英文）', () {
    const service = SlashCommandService();
    expect(service.match('/标题')?.type, SlashBlockType.heading);
    expect(service.match('/heading')?.type, SlashBlockType.heading);
    expect(service.match('/列表')?.type, SlashBlockType.list);
    expect(service.match('/code')?.type, SlashBlockType.code);
    expect(service.match('/引用')?.type, SlashBlockType.quote);
  });

  test('match：非命令/空输入返回 null', () {
    const service = SlashCommandService();
    expect(service.match('标题'), isNull);
    expect(service.match('/'), isNull);
    expect(service.match(''), isNull);
  });

  test('search：模糊搜索命令（AFFiNE 双栏菜单过滤）', () {
    const service = SlashCommandService();
    expect(service.search('/标').length, greaterThan(0));
    expect(service.search('/h').length, greaterThan(0));
    expect(service.search('/不存在的').length, 0);
  });

  test('SlashCommand：相等性（按 type）', () {
    const a = SlashCommand(type: SlashBlockType.heading, name: '标题', keyword: 'h');
    const b = SlashCommand(type: SlashBlockType.heading, name: '标题2', keyword: 'h2');
    expect(a, b); // 按 type 相等。
  });
}
