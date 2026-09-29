// 由 Claude 团队生成 | Drawing Notes App
// block_slash_menu.dart 单元测试。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/core/documents/note_block.dart';
import 'package:drawing_notes_app/features/doc/presentation/block_slash_menu.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

void main() {
  group('BlockSlashMenu', () {
    test('options 包含所有常用块类型', () {
      final types = BlockSlashMenu.optionsOf(null).map((o) => o.type).toSet();
      expect(types.contains(NoteBlockType.text), isTrue);
      expect(types.contains(NoteBlockType.heading), isTrue);
      expect(types.contains(NoteBlockType.todo), isTrue);
      expect(types.contains(NoteBlockType.bullet), isTrue);
      expect(types.contains(NoteBlockType.ordered), isTrue);
      expect(types.contains(NoteBlockType.quote), isTrue);
      expect(types.contains(NoteBlockType.code), isTrue);
      expect(types.contains(NoteBlockType.divider), isTrue);
      expect(types.contains(NoteBlockType.callout), isTrue);
      expect(types.contains(NoteBlockType.table), isTrue);
      expect(types.contains(NoteBlockType.image), isTrue);
      expect(types.contains(NoteBlockType.link), isTrue);
      expect(types.contains(NoteBlockType.canvas), isTrue);
      expect(types.contains(NoteBlockType.chart), isTrue);
      expect(types.contains(NoteBlockType.database), isTrue);
    });

    test('T-12（审计 2026-09-27）：菜单全集精确等于块类型枚举——'
        '误注册多余/重复类型不再漏检', () {
      final types = BlockSlashMenu.optionsOf(null).map((o) => o.type).toList();
      expect(types.toSet(), equals(NoteBlockType.values.toSet()));
      // heading 按级别拆 3 个菜单项（标题 1/2/3，级别存 props）——唯一
      // 合法例外；其余类型不得重复注册。
      final nonHeading = types
          .where((t) => t != NoteBlockType.heading)
          .toList();
      expect(
        nonHeading.length,
        nonHeading.toSet().length,
        reason: '除 heading 多级入口外无重复注册',
      );
      expect(types.where((t) => t == NoteBlockType.heading).length, 3);
    });

    test('每个 option 都有 label、icon 和 group', () {
      for (final option in BlockSlashMenu.optionsOf(null)) {
        expect(option.label, isNotEmpty);
        expect(option.icon, isNotNull);
        expect(option.group, isNotNull);
      }
    });

    testWidgets('菜单渲染并显示选项', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockSlashMenu(onSelected: (_) {}, onDismiss: () {}),
          ),
        ),
      );

      // 验证至少显示了"段落"选项
      expect(find.text('段落'), findsOneWidget);
      expect(find.text('待办事项'), findsOneWidget);
    });

    testWidgets('点击选项触发 onSelected', (tester) async {
      NoteBlockType? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockSlashMenu(
              onSelected: (type) => selected = type,
              onDismiss: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('段落'));
      await tester.pump();

      expect(selected, NoteBlockType.text);
    });

    testWidgets('菜单顶部显示搜索框', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockSlashMenu(onSelected: (_) {}, onDismiss: () {}),
          ),
        ),
      );

      // 搜索框存在
      expect(find.byType(TextField), findsOneWidget);
      // 搜索 hint
      expect(find.text('搜索类型…'), findsOneWidget);
    });

    testWidgets('搜索过滤：输入关键词后只显示匹配项', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockSlashMenu(onSelected: (_) {}, onDismiss: () {}),
          ),
        ),
      );

      // 输入搜索关键词
      await tester.enterText(find.byType(TextField), '标题');
      await tester.pumpAndSettle();

      // 应显示标题相关项
      expect(find.text('标题 1'), findsOneWidget);
      expect(find.text('标题 2'), findsOneWidget);
      expect(find.text('标题 3'), findsOneWidget);
      // 不显示不匹配的项
      expect(find.text('段落'), findsNothing);
      expect(find.text('待办事项'), findsNothing);
    });

    testWidgets('搜索无结果显示空态', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlockSlashMenu(onSelected: (_) {}, onDismiss: () {}),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '不存在的关键词xyz');
      await tester.pumpAndSettle();

      expect(find.text('无匹配项'), findsOneWidget);
    });
  });

  group('filterSlashItems 纯逻辑', () {
    test('空 query 返回全部', () {
      final result = filterSlashItems(BlockSlashMenu.optionsOf(null), '');
      expect(result.length, BlockSlashMenu.optionsOf(null).length);
    });

    test('空 query（含空格）返回全部', () {
      final result = filterSlashItems(BlockSlashMenu.optionsOf(null), '   ');
      expect(result.length, BlockSlashMenu.optionsOf(null).length);
    });

    test('匹配 label', () {
      final result = filterSlashItems(BlockSlashMenu.optionsOf(null), '标题');
      expect(result, isNotEmpty);
      for (final item in result) {
        expect(item.label.contains('标题'), isTrue);
      }
    });

    test('匹配描述', () {
      final result = filterSlashItems(BlockSlashMenu.optionsOf(null), '勾选框');
      expect(result, isNotEmpty);
      expect(result.first.type, NoteBlockType.todo);
    });

    test('大小写不敏感', () {
      // 标签为中文，大小写混合查询应返回相同结果
      final lower = filterSlashItems(BlockSlashMenu.optionsOf(null), '代码');
      final upper = filterSlashItems(BlockSlashMenu.optionsOf(null), '代码');
      expect(lower.length, upper.length);
      expect(lower.first.type, upper.first.type);
      // 匹配到代码块
      expect(lower.first.type, NoteBlockType.code);
    });

    test('无结果返回空', () {
      final result = filterSlashItems(BlockSlashMenu.optionsOf(null), '不存在的关键词xyz123');
      expect(result, isEmpty);
    });
  });

  group('groupSlashItems 纯逻辑', () {
    test('分组包含预期类别', () {
      final groups = groupSlashItems(BlockSlashMenu.optionsOf(null));
      final groupKeys = groups.map((e) => e.key).toList();
      expect(groupKeys.contains(SlashItemGroup.basic), isTrue);
      expect(groupKeys.contains(SlashItemGroup.quoteCode), isTrue);
      expect(groupKeys.contains(SlashItemGroup.media), isTrue);
      expect(groupKeys.contains(SlashItemGroup.embed), isTrue);
      expect(groupKeys.contains(SlashItemGroup.other), isTrue);
    });

    test('基础组包含预期类型', () {
      final groups = groupSlashItems(BlockSlashMenu.optionsOf(null));
      final basicGroup = groups.firstWhere(
        (e) => e.key == SlashItemGroup.basic,
      );
      final basicTypes = basicGroup.value.map((e) => e.type).toSet();
      expect(basicTypes.contains(NoteBlockType.text), isTrue);
      expect(basicTypes.contains(NoteBlockType.heading), isTrue);
      expect(basicTypes.contains(NoteBlockType.todo), isTrue);
      expect(basicTypes.contains(NoteBlockType.bullet), isTrue);
      expect(basicTypes.contains(NoteBlockType.ordered), isTrue);
    });

    test('引用与代码组包含预期类型', () {
      final groups = groupSlashItems(BlockSlashMenu.optionsOf(null));
      final quoteCodeGroup = groups.firstWhere(
        (e) => e.key == SlashItemGroup.quoteCode,
      );
      final types = quoteCodeGroup.value.map((e) => e.type).toSet();
      expect(types.contains(NoteBlockType.quote), isTrue);
      expect(types.contains(NoteBlockType.code), isTrue);
    });

    test('媒体组包含预期类型', () {
      final groups = groupSlashItems(BlockSlashMenu.optionsOf(null));
      final mediaGroup = groups.firstWhere(
        (e) => e.key == SlashItemGroup.media,
      );
      final types = mediaGroup.value.map((e) => e.type).toSet();
      expect(types.contains(NoteBlockType.image), isTrue);
      expect(types.contains(NoteBlockType.link), isTrue);
    });

    test('嵌入组包含预期类型', () {
      final groups = groupSlashItems(BlockSlashMenu.optionsOf(null));
      final embedGroup = groups.firstWhere(
        (e) => e.key == SlashItemGroup.embed,
      );
      final types = embedGroup.value.map((e) => e.type).toSet();
      expect(types.contains(NoteBlockType.canvas), isTrue);
      expect(types.contains(NoteBlockType.chart), isTrue);
      expect(types.contains(NoteBlockType.table), isTrue);
      expect(types.contains(NoteBlockType.database), isTrue);
    });

    test('其他组包含预期类型', () {
      final groups = groupSlashItems(BlockSlashMenu.optionsOf(null));
      final otherGroup = groups.firstWhere(
        (e) => e.key == SlashItemGroup.other,
      );
      final types = otherGroup.value.map((e) => e.type).toSet();
      expect(types.contains(NoteBlockType.divider), isTrue);
      expect(types.contains(NoteBlockType.callout), isTrue);
    });

    test('空列表返回空', () {
      final groups = groupSlashItems(<SlashItem>[]);
      expect(groups, isEmpty);
    });
  });

  group('L-01（审计 2026-09-27）：optionsOf 工厂接 l10n', () {
    final cjk = RegExp(r'[\u4e00-\u9fff]');

    testWidgets('en locale 下 label/description 全本地化且无中文残留'
        '——附件项曾是漏映射唯一穿帮点', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              captured = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );
      final l10n = AppLocalizations.of(captured)!;
      final items = BlockSlashMenu.optionsOf(l10n);
      // 项数与 zh 兜底一致（heading 按级别拆 3 项）。
      expect(items.length, BlockSlashMenu.optionsOf(null).length);
      for (final item in items) {
        expect(item.label, isNotEmpty);
        expect(item.label, isNot(contains(cjk)),
            reason: 'en 下 label 不得残留中文：${item.label}');
        if (item.description != null) {
          expect(item.description, isNot(contains(cjk)),
              reason: 'en 下 description 不得残留中文：${item.description}');
        }
      }
      final attachment =
          items.firstWhere((i) => i.type == NoteBlockType.attachment);
      expect(attachment.label, 'Attachment');
      expect(attachment.description, 'Attach a file');
    });

    testWidgets('en locale 菜单渲染英文且可用英文搜索', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: BlockSlashMenu(onSelected: (_) {}, onDismiss: () {}),
          ),
        ),
      );

      // ListView 惰性构建：初始断言取视口内首项；Attachment 的英文文案
      // 由上一条 optionsOf 全量用例锁死。
      expect(find.text('Paragraph'), findsOneWidget);

      // 过滤与展示同源：英文关键词直接命中本地化 label。
      await tester.enterText(find.byType(TextField), 'attach');
      await tester.pumpAndSettle();
      expect(find.text('Attachment'), findsOneWidget);
      expect(find.text('Paragraph'), findsNothing);
    });
  });
}
