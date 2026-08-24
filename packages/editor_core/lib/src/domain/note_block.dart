// editor_core——NoteBlock 块模型（AFFiNE BlockSuite 借鉴——2026-08-24）。
//
// AFFiNE "everything is a block" 理念——将 NoteParagraph 升级为统一块模型。
// 支持：段落/标题/列表/代码/引用/分隔线/图片/表格。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
//
// 版权：AFFiNE（BSL 1.1——BlockSuite MIT）——仅概念借鉴——NOTICE 已记录。
library;

import 'rich_text_block.dart';
import 'slash_command.dart';

/// 块类型（AFFiNE BlockSuite 借鉴——一切皆块）。
enum NoteBlockType {
  /// 普通段落。
  paragraph,

  /// 一级标题。
  heading1,

  /// 二级标题。
  heading2,

  /// 三级标题。
  heading3,

  /// 无序列表项。
  bulletList,

  /// 有序列表项。
  numberedList,

  /// 代码块。
  code,

  /// 引用块。
  quote,

  /// 分隔线。
  divider,

  /// 图片块。
  image,

  /// 表格块。
  table,
}

/// 块模型（AFFiNE BlockSuite 借鉴——一切皆块——不可变）。
///
/// 与 NoteParagraph 的区别：
/// - NoteParagraph：仅 paragraph/heading 两种类型
/// - NoteBlock：支持 10+ 种块类型 + 富文本 spans + 元数据
///
/// 设计原则（AFFiNE BlockSuite）：
/// - 每个块有唯一 id、类型、内容
/// - 块可独立渲染、拖拽、转换
/// - 支持 / 命令菜单插入
class NoteBlock {
  const NoteBlock({
    required this.id,
    required this.type,
    this.content = '',
    this.spans = const [],
    this.meta = const {},
    this.children = const [],
  });

  /// 块唯一标识。
  final String id;

  /// 块类型。
  final NoteBlockType type;

  /// 块文本内容（纯文本——spans 为空时使用）。
  final String content;

  /// 富文本 spans（带格式——加粗/斜体/列表）。
  final List<RichTextSpan> spans;

  /// 附加元数据（图片 url、代码语言等）。
  final Map<String, dynamic> meta;

  /// 子块列表（嵌套块——如列表项嵌套子列表）。
  final List<NoteBlock> children;

  /// 是否为空块。
  bool get isEmpty => content.isEmpty && spans.isEmpty;

  /// 是否为标题块。
  bool get isHeading =>
      type == NoteBlockType.heading1 ||
      type == NoteBlockType.heading2 ||
      type == NoteBlockType.heading3;

  /// 是否为列表块。
  bool get isList =>
      type == NoteBlockType.bulletList ||
      type == NoteBlockType.numberedList;

  /// 标题级别（1-3），非标题返回 0。
  int get headingLevel {
    switch (type) {
      case NoteBlockType.heading1:
        return 1;
      case NoteBlockType.heading2:
        return 2;
      case NoteBlockType.heading3:
        return 3;
      default:
        return 0;
    }
  }

  /// 从 SlashBlockType 转换。
  static NoteBlockType fromSlashType(SlashBlockType slashType) {
    switch (slashType) {
      case SlashBlockType.paragraph:
        return NoteBlockType.paragraph;
      case SlashBlockType.heading:
        return NoteBlockType.heading1;
      case SlashBlockType.list:
        return NoteBlockType.bulletList;
      case SlashBlockType.quote:
        return NoteBlockType.quote;
      case SlashBlockType.code:
        return NoteBlockType.code;
      case SlashBlockType.divider:
        return NoteBlockType.divider;
    }
  }

  /// 转换为对应图标。
  String get icon {
    switch (type) {
      case NoteBlockType.paragraph:
        return '📄';
      case NoteBlockType.heading1:
        return '🔠';
      case NoteBlockType.heading2:
        return '🔡';
      case NoteBlockType.heading3:
        return '🔤';
      case NoteBlockType.bulletList:
        return '•';
      case NoteBlockType.numberedList:
        return '1.';
      case NoteBlockType.code:
        return '💻';
      case NoteBlockType.quote:
        return '💬';
      case NoteBlockType.divider:
        return '➖';
      case NoteBlockType.image:
        return '🖼️';
      case NoteBlockType.table:
        return '📊';
    }
  }

  NoteBlock copyWith({
    NoteBlockType? type,
    String? content,
    List<RichTextSpan>? spans,
    Map<String, dynamic>? meta,
    List<NoteBlock>? children,
  }) {
    return NoteBlock(
      id: id,
      type: type ?? this.type,
      content: content ?? this.content,
      spans: spans ?? this.spans,
      meta: meta ?? this.meta,
      children: children ?? this.children,
    );
  }

  /// 转换为 NoteParagraph（向后兼容——#13 持久化）。
  ///
  /// 映射规则：
  /// - paragraph → NoteParagraphType.paragraph
  /// - heading1/2/3 → NoteParagraphType.heading
  /// - 其他 → NoteParagraphType.paragraph（content 保留）
  dynamic toParagraph() {
    // 返回 dynamic 避免循环导入——实际类型为 NoteParagraph
    return {
      'id': id,
      'content': content,
      'type': isHeading ? 'heading' : 'paragraph',
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteBlock &&
          id == other.id &&
          type == other.type &&
          content == other.content;

  @override
  int get hashCode => Object.hash(id, type, content);
}
