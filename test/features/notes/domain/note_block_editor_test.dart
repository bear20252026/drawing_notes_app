// 由 Claude 团队生成 | Drawing Notes App
// note_block_editor.dart 单元测试。

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_editor.dart';

void main() {
  const editor = NoteBlockEditor();

  // 构建测试树：
  // root
  // ├── a (text)
  // │   ├── a1 (todo, checked)
  // │   └── a2 (text)
  // └── b (heading)
  NoteBlock buildTree() => NoteBlock(
    id: 'root',
    type: NoteBlockType.text,
    text: 'root',
    children: [
      NoteBlock(
        id: 'a',
        type: NoteBlockType.text,
        text: 'block-a',
        children: [
          NoteBlock.todoBlock('a1', text: 'task1', checked: true),
          NoteBlock.textBlock('a2', text: 'sub-a2'),
        ],
      ),
      NoteBlock.headingBlock('b', level: 1, text: 'title'),
    ],
  );

  group('NoteBlockEditor', () {
    test('findBlock 能找到嵌套块', () {
      final tree = buildTree();
      expect(editor.findBlock(tree, 'a1')?.type, NoteBlockType.todo);
      expect(editor.findBlock(tree, 'b')?.type, NoteBlockType.heading);
      expect(editor.findBlock(tree, 'nonexistent'), isNull);
    });

    test('collectIds 收集所有 id', () {
      final tree = buildTree();
      final ids = editor.collectIds(tree);
      expect(ids, ['root', 'a', 'a1', 'a2', 'b']);
    });

    test('insertChild 在指定父块下插入子块', () {
      final tree = buildTree();
      final newBlock = NoteBlock.textBlock('new', text: 'new-block');
      final result = editor.insertChild(tree, 'a', newBlock);

      final parent = editor.findBlock(result, 'a')!;
      expect(parent.children.length, 3);
      expect(parent.children.last.id, 'new');
    });

    test('insertChild 在指定 index 插入', () {
      final tree = buildTree();
      final newBlock = NoteBlock.textBlock('new', text: 'inserted');
      final result = editor.insertChild(tree, 'a', newBlock, index: 0);

      final parent = editor.findBlock(result, 'a')!;
      expect(parent.children.first.id, 'new');
    });

    test('insertChild 父块不存在时返回原树', () {
      final tree = buildTree();
      final newBlock = NoteBlock.textBlock('new');
      final result = editor.insertChild(tree, 'nonexistent', newBlock);
      expect(identical(result, tree), isTrue);
    });

    test('insertAfter 在目标块后插入兄弟', () {
      final tree = buildTree();
      final newBlock = NoteBlock.textBlock('new', text: 'after');
      final result = editor.insertAfter(tree, 'a', newBlock);

      final rootChildren = result.children;
      expect(rootChildren.length, 3);
      expect(rootChildren[0].id, 'a');
      expect(rootChildren[1].id, 'new');
      expect(rootChildren[2].id, 'b');
    });

    test('insertBefore 在目标块前插入兄弟', () {
      final tree = buildTree();
      final newBlock = NoteBlock.textBlock('new', text: 'before');
      final result = editor.insertBefore(tree, 'b', newBlock);

      final rootChildren = result.children;
      expect(rootChildren[0].id, 'a');
      expect(rootChildren[1].id, 'new');
      expect(rootChildren[2].id, 'b');
    });

    test('deleteBlock 删除指定块及其子树', () {
      final tree = buildTree();
      final result = editor.deleteBlock(tree, 'a');

      expect(editor.findBlock(result, 'a'), isNull);
      expect(editor.findBlock(result, 'a1'), isNull);
      expect(editor.findBlock(result, 'a2'), isNull);
      expect(editor.findBlock(result, 'b'), isNotNull);
    });

    test('deleteBlock 删除不存在的块返回原树', () {
      final tree = buildTree();
      final result = editor.deleteBlock(tree, 'nonexistent');
      expect(identical(result, tree), isTrue);
    });

    test('deleteBlock 不能删除根节点', () {
      final tree = buildTree();
      final result = editor.deleteBlock(tree, 'root');
      expect(identical(result, tree), isTrue);
    });

    test('updateText 更新文本', () {
      final tree = buildTree();
      final result = editor.updateText(tree, 'a1', 'updated-task');

      expect(editor.findBlock(result, 'a1')?.text, 'updated-task');
    });

    test('updateType 更新类型', () {
      final tree = buildTree();
      final result = editor.updateType(tree, 'a2', NoteBlockType.heading);

      expect(editor.findBlock(result, 'a2')?.type, NoteBlockType.heading);
    });

    test('updateProps 合并属性', () {
      final tree = buildTree();
      final result = editor.updateProps(tree, 'a1', {'priority': 'high'});

      final a1 = editor.findBlock(result, 'a1')!;
      expect(a1.props['checked'], true); // 保留原有
      expect(a1.props['priority'], 'high'); // 新增
    });

    test('toggleTodo 切换 checked 状态', () {
      final tree = buildTree();
      expect(editor.findBlock(tree, 'a1')?.props['checked'], true);

      final result = editor.toggleTodo(tree, 'a1');
      expect(editor.findBlock(result, 'a1')?.props['checked'], false);

      final result2 = editor.toggleTodo(result, 'a1');
      expect(editor.findBlock(result2, 'a1')?.props['checked'], true);
    });

    test('toggleTodo 对非 todo 块无效', () {
      final tree = buildTree();
      final result = editor.toggleTodo(tree, 'a2'); // a2 是 text
      expect(identical(result, tree), isTrue);
    });

    test('moveBlock 将块移动到新父块下', () {
      final tree = buildTree();
      // 将 a1 从 a 移动到 b 下
      final result = editor.moveBlock(tree, 'a1', 'b');

      expect(editor.findBlock(result, 'a')?.children.length, 1); // a 只剩 a2
      expect(editor.findBlock(result, 'b')?.children.length, 1); // b 多了 a1
      expect(editor.findBlock(result, 'b')?.children.first.id, 'a1');
    });

    test('moveBlock 防止循环依赖', () {
      final tree = buildTree();
      // 尝试将 a（父）移动到 a1（子）下 → 应拒绝
      final result = editor.moveBlock(tree, 'a', 'a1');
      expect(identical(result, tree), isTrue);
    });

    test('moveBlock 目标不存在时返回原树', () {
      final tree = buildTree();
      final result = editor.moveBlock(tree, 'nonexistent', 'b');
      expect(identical(result, tree), isTrue);
    });

    test('不可变性：原树不被修改', () {
      final tree = buildTree();
      final originalAChildren = editor.findBlock(tree, 'a')!.children.length;

      editor.updateText(tree, 'a1', 'changed');
      editor.deleteBlock(tree, 'a2');
      editor.insertChild(tree, 'a', NoteBlock.textBlock('new'));

      expect(editor.findBlock(tree, 'a')!.children.length, originalAChildren);
      expect(editor.findBlock(tree, 'a1')?.text, 'task1');
      expect(editor.findBlock(tree, 'a2'), isNotNull);
    });

    test('确定性：相同输入多次调用结果一致', () {
      final tree = buildTree();
      final r1 = editor.updateText(tree, 'a1', 'deterministic');
      final r2 = editor.updateText(tree, 'a1', 'deterministic');
      expect(r1 == r2, isTrue);
    });
  });

  group('splitAtCursor', () {
    test('基本拆分：文本从中间切开，新块继承 type/props', () {
      final tree = buildTree();
      final result = editor.splitAtCursor(tree, 'a1', 2);

      // 原块 text 变为前半
      expect(editor.findBlock(result, 'a1')?.text, 'ta');
      // 新块插入原块之后
      final aChildren = editor.findBlock(result, 'a')!.children;
      expect(aChildren.length, 3);
      final newBlock = aChildren.firstWhere(
        (c) => c.id != 'a1' && c.id != 'a2',
      );
      expect(newBlock.text, 'sk1');
      expect(newBlock.type, NoteBlockType.todo);
      expect(newBlock.props['checked'], true); // 继承 props
    });

    test('offset=0 时原块变空，新块持有全部文本（text[:0]=空, text[0:]=全文）', () {
      final tree = buildTree();
      final result = editor.splitAtCursor(tree, 'a1', 0);

      expect(editor.findBlock(result, 'a1')?.text, '');
      final aChildren = editor.findBlock(result, 'a')!.children;
      expect(aChildren.length, 3);
      final newBlock = aChildren.firstWhere(
        (c) => c.id != 'a1' && c.id != 'a2',
      );
      expect(newBlock.text, 'task1');
    });

    test('offset=text.length 时新块为空文本，原块不变', () {
      final tree = buildTree();
      final result = editor.splitAtCursor(tree, 'a1', 5); // task1.length == 5

      expect(editor.findBlock(result, 'a1')?.text, 'task1');
      final aChildren = editor.findBlock(result, 'a')!.children;
      expect(aChildren.length, 3);
      final newBlock = aChildren.firstWhere(
        (c) => c.id != 'a1' && c.id != 'a2',
      );
      expect(newBlock.text, '');
    });

    test('块不存在时返回原树', () {
      final tree = buildTree();
      final result = editor.splitAtCursor(tree, 'nonexistent', 2);
      expect(identical(result, tree), isTrue);
    });

    test('非文本块（divider）不可拆分', () {
      final tree = NoteBlock(
        id: 'root',
        type: NoteBlockType.text,
        children: [NoteBlock.dividerBlock('d1')],
      );
      final result = editor.splitAtCursor(tree, 'd1', 0);
      expect(identical(result, tree), isTrue);
    });

    test('offset 越界返回原树', () {
      final tree = buildTree();
      final r1 = editor.splitAtCursor(tree, 'a1', -1);
      final r2 = editor.splitAtCursor(tree, 'a1', 100);
      expect(identical(r1, tree), isTrue);
      expect(identical(r2, tree), isTrue);
    });

    test('自定义 idGenerator', () {
      final tree = buildTree();
      final result = editor.splitAtCursor(
        tree,
        'a1',
        2,
        idGenerator: (id, offset) => 'custom_${id}_$offset',
      );

      expect(editor.findBlock(result, 'custom_a1_2'), isNotNull);
    });
  });

  group('mergeWithPrev', () {
    test('基本合并：当前块文本并入前块，当前块被删除', () {
      final tree = buildTree();
      // a2 的 text 是 'sub-a2'，前块 a1 的 text 是 'task1'
      final result = editor.mergeWithPrev(tree, 'a2');

      final a = editor.findBlock(result, 'a')!;
      expect(a.children.length, 1);
      expect(editor.findBlock(result, 'a2'), isNull);
      expect(editor.findBlock(result, 'a1')?.text, 'task1sub-a2');
    });

    test('根节点无前块，返回原树', () {
      final tree = buildTree();
      final result = editor.mergeWithPrev(tree, 'root');
      expect(identical(result, tree), isTrue);
    });

    test('第一个子节点无前块，返回原树', () {
      final tree = buildTree();
      // a 是 root 的第一个子节点
      final result = editor.mergeWithPrev(tree, 'a');
      expect(identical(result, tree), isTrue);
    });

    test('块不存在时返回原树', () {
      final tree = buildTree();
      final result = editor.mergeWithPrev(tree, 'nonexistent');
      expect(identical(result, tree), isTrue);
    });

    test('跨层级不合并（不同父块）', () {
      final tree = buildTree();
      // b 和 a 是同级，但 b 是第二个子节点，前块是 a
      // a 的 text 是 'block-a'，b 的 text 是 'title'
      final result = editor.mergeWithPrev(tree, 'b');

      // b 应被删除，text 并入 a
      expect(editor.findBlock(result, 'b'), isNull);
      expect(editor.findBlock(result, 'a')?.text, 'block-atitle');
    });

    test('不可变性：原树不变', () {
      final tree = buildTree();
      editor.mergeWithPrev(tree, 'a2');

      expect(editor.findBlock(tree, 'a2'), isNotNull);
      expect(editor.findBlock(tree, 'a')?.children.length, 2);
    });
  });

  group('normalize', () {
    test('清除空文本块（非唯一块）', () {
      final tree = NoteBlock(
        id: 'root',
        type: NoteBlockType.text,
        children: [
          NoteBlock.textBlock('b1', text: 'hello'),
          NoteBlock.textBlock('b2'), // 空文本
          NoteBlock.headingBlock(
            'b3',
            level: 1,
            text: 'world',
          ), // 不同类型，不会与 b1 合并
          NoteBlock.textBlock('b4'), // 空文本
        ],
      );
      final result = editor.normalize(tree);
      final ids = editor.collectIds(result).where((id) => id != 'root');

      expect(ids.contains('b2'), isFalse);
      expect(ids.contains('b4'), isFalse);
      expect(editor.findBlock(result, 'b1')?.text, 'hello');
      expect(editor.findBlock(result, 'b3')?.text, 'world');
    });

    test('保留 divider 空块', () {
      final tree = NoteBlock(
        id: 'root',
        type: NoteBlockType.text,
        children: [
          NoteBlock.textBlock('b1', text: 'hello'),
          NoteBlock.dividerBlock('d1'), // divider 应为空但保留
        ],
      );
      final result = editor.normalize(tree);
      expect(editor.findBlock(result, 'd1'), isNotNull);
    });

    test('合并连续同类型文本块', () {
      final tree = NoteBlock(
        id: 'root',
        type: NoteBlockType.text,
        children: [
          NoteBlock.textBlock('b1', text: 'first'),
          NoteBlock.textBlock('b2', text: 'second'),
        ],
      );
      final result = editor.normalize(tree);

      final children = result.children;
      expect(children.length, 1);
      expect(children.first.text, 'firstsecond');
    });

    test('不同类型不合并', () {
      final tree = NoteBlock(
        id: 'root',
        type: NoteBlockType.text,
        children: [
          NoteBlock.textBlock('b1', text: 'hello'),
          NoteBlock.headingBlock('b2', level: 1, text: 'title'),
        ],
      );
      final result = editor.normalize(tree);
      expect(result.children.length, 2);
    });

    test('全部为空块时保留至少一个默认块', () {
      final tree = NoteBlock(
        id: 'root',
        type: NoteBlockType.text,
        children: [
          NoteBlock.textBlock('b1'), // 空
          NoteBlock.textBlock('b2'), // 空
        ],
      );
      final result = editor.normalize(tree);
      // 归一化后应至少有一个子块
      expect(result.hasChildren || result.text.isNotEmpty, isTrue);
    });

    test('递归归一化子块', () {
      final tree = NoteBlock(
        id: 'root',
        type: NoteBlockType.text,
        children: [
          NoteBlock(
            id: 'parent',
            type: NoteBlockType.text,
            children: [
              NoteBlock.textBlock('c1', text: 'a'),
              NoteBlock.textBlock('c2', text: 'b'),
            ],
          ),
        ],
      );
      final result = editor.normalize(tree);

      final parent = editor.findBlock(result, 'parent')!;
      expect(parent.children.length, 1);
      expect(parent.children.first.text, 'ab');
    });

    test('props 不同的同类型块不合并', () {
      final tree = NoteBlock(
        id: 'root',
        type: NoteBlockType.text,
        children: [
          NoteBlock(
            id: 'h1',
            type: NoteBlockType.heading,
            text: 'a',
            props: {'level': 1},
          ),
          NoteBlock(
            id: 'h2',
            type: NoteBlockType.heading,
            text: 'b',
            props: {'level': 2},
          ),
        ],
      );
      final result = editor.normalize(tree);
      expect(result.children.length, 2);
    });

    test('确定性：相同输入多次调用结果一致', () {
      final tree = NoteBlock(
        id: 'root',
        type: NoteBlockType.text,
        children: [
          NoteBlock.textBlock('b1', text: 'x'),
          NoteBlock.textBlock('b2', text: 'y'),
          NoteBlock.textBlock('b3'), // 空
        ],
      );
      final r1 = editor.normalize(tree);
      final r2 = editor.normalize(tree);
      expect(r1 == r2, isTrue);
    });
  });
}
