// 由 Claude 团队生成 | Drawing Notes App
// AFFiNE 风格块编辑纯逻辑：对 NoteBlock 树执行不可变编辑操作。
// 无 flutter/io/controller/存储依赖；不可变输入 → 确定性输出。

import 'package:drawing_notes_app/features/doc/domain/note_block.dart';

/// 纯逻辑块编辑器。
///
/// 所有方法均为纯函数：输入旧块树 → 输出新块树，不修改输入对象。
/// 由 lead 在页面层调用，将编辑结果写回状态。
class NoteBlockEditor {
  const NoteBlockEditor();

  // ── 查询 ───────────────────────────────────────────────────

  /// 在块树中按 id 查找块（深度优先）。
  /// 返回 null 表示未找到。
  NoteBlock? findBlock(NoteBlock root, String id) {
    if (root.id == id) return root;
    for (final child in root.children) {
      final found = findBlock(child, id);
      if (found != null) return found;
    }
    return null;
  }

  /// 在块树中按 id 查找块（多根版本）。
  NoteBlock? findBlockInTree(List<NoteBlock> tree, String id) {
    for (final root in tree) {
      final found = findBlock(root, id);
      if (found != null) return found;
    }
    return null;
  }

  /// 收集树中所有块的 id（深度优先）。
  List<String> collectIds(NoteBlock root) {
    final ids = <String>[root.id];
    for (final child in root.children) {
      ids.addAll(collectIds(child));
    }
    return ids;
  }

  // ── 插入 ───────────────────────────────────────────────────

  /// 在 [parentId] 的子块列表中 [index] 位置插入 [block]。
  /// 若 parent 不存在或 index 越界，返回原树不变。
  NoteBlock insertChild(
    NoteBlock root,
    String parentId,
    NoteBlock block, {
    int? index,
  }) {
    return _mapNode(root, (node) {
      if (node.id != parentId) return node;
      final newChildren = List<NoteBlock>.from(node.children);
      final insertIndex = index ?? newChildren.length;
      if (insertIndex < 0 || insertIndex > newChildren.length) return node;
      newChildren.insert(insertIndex, block);
      return node.copyWith(children: newChildren);
    });
  }

  /// 在 [parentId] 的子块列表中 [index] 位置插入 [block]（多根版本）。
  List<NoteBlock> insertChildInTree(
    List<NoteBlock> tree,
    String parentId,
    NoteBlock block, {
    int? index,
  }) {
    return tree.map((root) {
      return insertChild(root, parentId, block, index: index);
    }).toList();
  }

  /// 在 [targetId] 之后插入 [block]（作为同级兄弟）。
  /// 若 target 不存在，返回原树不变。
  NoteBlock insertAfter(NoteBlock root, String targetId, NoteBlock block) {
    return _insertSibling(root, targetId, block, after: true);
  }

  /// 在 [targetId] 之前插入 [block]（作为同级兄弟）。
  NoteBlock insertBefore(NoteBlock root, String targetId, NoteBlock block) {
    return _insertSibling(root, targetId, block, after: false);
  }

  // ── 删除 ───────────────────────────────────────────────────

  /// 从树中删除 [blockId] 对应的块及其子树。
  /// 若不存在，返回原树不变。
  NoteBlock deleteBlock(NoteBlock root, String blockId) {
    if (root.id == blockId) {
      // 不能删除根节点自身 → 返回不变
      return root;
    }
    return _mapNode(root, (node) {
      final hasChild = node.children.any((c) => c.id == blockId);
      if (!hasChild) return node;
      final newChildren = node.children.where((c) => c.id != blockId).toList();
      return node.copyWith(children: newChildren);
    });
  }

  /// 从多根树中删除 [blockId]。
  List<NoteBlock> deleteBlockInTree(List<NoteBlock> tree, String blockId) {
    return tree.where((root) => root.id != blockId).map((root) {
      return deleteBlock(root, blockId);
    }).toList();
  }

  // ── 更新 ───────────────────────────────────────────────────

  /// 更新 [blockId] 的文本内容。
  /// 若不存在，返回原树不变。
  NoteBlock updateText(NoteBlock root, String blockId, String text) {
    return _mapNode(root, (node) {
      if (node.id != blockId) return node;
      return node.copyWith(text: text);
    });
  }

  /// 更新 [blockId] 的类型。
  NoteBlock updateType(NoteBlock root, String blockId, NoteBlockType type) {
    return _mapNode(root, (node) {
      if (node.id != blockId) return node;
      return node.copyWith(type: type);
    });
  }

  /// 更新 [blockId] 的 props（合并方式）。
  NoteBlock updateProps(NoteBlock root, String blockId, NoteBlockProps props) {
    return _mapNode(root, (node) {
      if (node.id != blockId) return node;
      final merged = NoteBlockProps.from(node.props)..addAll(props);
      return node.copyWith(props: merged);
    });
  }

  /// 切换 todo 块的 checked 状态。
  /// 若非 todo 块或不存在，返回原树不变。
  NoteBlock toggleTodo(NoteBlock root, String blockId) {
    return _mapNode(root, (node) {
      if (node.id != blockId || node.type != NoteBlockType.todo) return node;
      final current = node.props['checked'] as bool? ?? false;
      final newProps = NoteBlockProps.from(node.props);
      newProps['checked'] = !current;
      return node.copyWith(props: newProps);
    });
  }

  // ── 移动 ───────────────────────────────────────────────────

  /// 将 [blockId] 移动到 [newParentId] 的 [index] 位置。
  /// 若 block 或 newParent 不存在，或移动会导致循环依赖，返回原树不变。
  NoteBlock moveBlock(
    NoteBlock root,
    String blockId,
    String newParentId, {
    int? index,
  }) {
    // 不能移动根节点
    if (root.id == blockId) return root;

    // 查找目标块
    final target = findBlock(root, blockId);
    if (target == null) return root;

    // 查找新父块
    final newParent = findBlock(root, newParentId);
    if (newParent == null) return root;

    // 防止循环依赖：不能将父块移动到其子块下
    if (findBlock(target, newParentId) != null) return root;

    // 先删除再插入
    var result = deleteBlock(root, blockId);
    result = insertChild(result, newParentId, target, index: index);
    return result;
  }

  // ── 高级编辑（M1 编辑器 UI 依赖） ─────────────────────────

  /// Enter 拆分：将 [blockId] 对应块的文本从 [textOffset] 处切开。
  ///
  /// 前半留在原块，后半生成新块插入原块之后（继承 type/props）。
  /// 若块不存在、非文本块、或 offset 越界（< 0 或 > text.length）→ 返回原树不变。
  ///
  /// 新块 id 由 [idGenerator] 提供（默认使用 `'${blockId}_split_$offset'`）。
  NoteBlock splitAtCursor(
    NoteBlock root,
    String blockId,
    int textOffset, {
    String Function(String blockId, int offset)? idGenerator,
  }) {
    final target = findBlock(root, blockId);
    if (target == null || !target.isTextual) return root;
    if (textOffset < 0 || textOffset > target.text.length) return root;

    final newId =
        idGenerator?.call(blockId, textOffset) ??
        '${blockId}_split_$textOffset';
    final firstText = target.text.substring(0, textOffset);
    final secondText = target.text.substring(textOffset);

    final newBlock = target.copyWith(id: newId, text: secondText);

    // 更新原块文本，然后在其后插入新块
    var result = updateText(root, blockId, firstText);
    result = insertAfter(result, blockId, newBlock);
    return result;
  }

  /// Backspace 合并：将 [blockId] 对应块并入其前一同级块。
  ///
  /// 合并后当前块被删除，文本拼接到前块末尾。
  /// 若块不存在、无前一同级块 → 返回原树不变。
  NoteBlock mergeWithPrev(NoteBlock root, String blockId) {
    if (root.id == blockId) return root; // 根节点无前块

    // 查找目标块及其父块、在兄弟中的位置
    final location = _findParentAndIndex(root, blockId);
    if (location == null) return root;

    final parent = location.$1;
    final index = location.$2;

    if (index <= 0) return root; // 无前一同级块

    final prevSibling = parent.children[index - 1];
    final current = parent.children[index];

    // 合并文本到前块
    final mergedText = prevSibling.text + current.text;
    final merged = prevSibling.copyWith(text: mergedText);

    // 替换前块为合并后的，删除当前块
    var result = _replaceChild(root, parent.id, index - 1, merged);
    result = deleteChildAt(result, parent.id, index);
    return result;
  }

  /// 归一化：清理块树，保证结构合法。
  ///
  /// 规则：
  /// - 清除空文本块（text 为空 且 非唯一块 且 非特殊块如 divider/image）
  /// - 合并连续同类型文本块（后一个文本拼接到前一个）
  /// - 剔除非法子块
  /// - 保证至少存在一个块
  NoteBlock normalize(NoteBlock root) {
    if (!root.hasChildren) {
      // 无子块：确保根自身合法
      if (root.text.isEmpty &&
          root.type != NoteBlockType.divider &&
          root.type != NoteBlockType.image) {
        // 根为空文本块，转为默认文本块
        return root.copyWith(type: NoteBlockType.text);
      }
      return root;
    }

    // 递归归一化子块
    final normalizedChildren = _normalizeChildren(root.children);

    var result = root.copyWith(children: normalizedChildren);

    // 如果归一化后无子块且根文本为空，给一个默认块
    if (!result.hasChildren && result.text.isEmpty) {
      return result.copyWith(
        children: [NoteBlock.textBlock('${result.id}_default')],
      );
    }

    return result;
  }

  // ── 内部工具 ───────────────────────────────────────────────

  /// 归一化子块列表：去空、合并同类、递归处理。
  List<NoteBlock> _normalizeChildren(List<NoteBlock> children) {
    final result = <NoteBlock>[];

    for (final child in children) {
      // 递归归一化子块的子块
      final normalizedChild = child.hasChildren
          ? child.copyWith(children: _normalizeChildren(child.children))
          : child;

      // 跳过空文本块（非特殊类型、无文本、无子块）
      if (normalizedChild.text.isEmpty &&
          !normalizedChild.hasChildren &&
          normalizedChild.type != NoteBlockType.divider &&
          normalizedChild.type != NoteBlockType.image) {
        continue;
      }

      // 尝试与前一块合并（同类型文本块）
      if (result.isNotEmpty) {
        final prev = result.last;
        if (prev.type == normalizedChild.type &&
            prev.isTextual &&
            normalizedChild.isTextual &&
            _propsEqualProps(prev.props, normalizedChild.props)) {
          result[result.length - 1] = prev.copyWith(
            text: prev.text + normalizedChild.text,
          );
          continue;
        }
      }

      result.add(normalizedChild);
    }

    return result;
  }

  /// 查找目标块及其父块和 index。
  /// 返回 (parent, index) 或 null。
  (NoteBlock parent, int index)? _findParentAndIndex(
    NoteBlock root,
    String blockId,
  ) {
    for (var i = 0; i < root.children.length; i++) {
      if (root.children[i].id == blockId) {
        return (root, i);
      }
      final nested = _findParentAndIndex(root.children[i], blockId);
      if (nested != null) return nested;
    }
    return null;
  }

  /// 替换指定父块的某个子块。
  NoteBlock _replaceChild(
    NoteBlock root,
    String parentId,
    int index,
    NoteBlock newChild,
  ) {
    return _mapNode(root, (node) {
      if (node.id != parentId) return node;
      if (index < 0 || index >= node.children.length) return node;
      final newChildren = List<NoteBlock>.from(node.children);
      newChildren[index] = newChild;
      return node.copyWith(children: newChildren);
    });
  }

  /// 删除指定父块的某个子块（按 index）。
  NoteBlock deleteChildAt(NoteBlock root, String parentId, int index) {
    return _mapNode(root, (node) {
      if (node.id != parentId) return node;
      if (index < 0 || index >= node.children.length) return node;
      final newChildren = List<NoteBlock>.from(node.children);
      newChildren.removeAt(index);
      return node.copyWith(children: newChildren);
    });
  }

  bool _propsEqualProps(NoteBlockProps a, NoteBlockProps b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }

  // ── 工具方法 ───────────────────────────────────────────────

  /// 对树中每个节点应用 [transform]，返回新树。
  /// 若节点未被修改（transform 返回同一实例），则复用原引用。
  NoteBlock _mapNode(NoteBlock node, NoteBlock Function(NoteBlock) transform) {
    final transformed = transform(node);
    if (identical(transformed, node)) {
      // 节点本身未被修改，递归处理子节点
      if (node.children.isEmpty) return node;
      var childrenChanged = false;
      final newChildren = <NoteBlock>[];
      for (final child in node.children) {
        final newChild = _mapNode(child, transform);
        if (!identical(newChild, child)) childrenChanged = true;
        newChildren.add(newChild);
      }
      if (!childrenChanged) return node;
      return node.copyWith(children: newChildren);
    }
    // 节点本身被修改，子节点保持不变
    return transformed;
  }

  NoteBlock _insertSibling(
    NoteBlock root,
    String targetId,
    NoteBlock block, {
    required bool after,
  }) {
    if (root.id == targetId) return root; // 不能在根节点前后插入
    return _mapNode(root, (node) {
      final idx = node.children.indexWhere((c) => c.id == targetId);
      if (idx < 0) return node;
      final newChildren = List<NoteBlock>.from(node.children);
      final insertIndex = after ? idx + 1 : idx;
      newChildren.insert(insertIndex, block);
      return node.copyWith(children: newChildren);
    });
  }
}
