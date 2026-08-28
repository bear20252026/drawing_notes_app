// 由 Claude 团队生成 | Drawing Notes App
// AFFiNE 风格块模型：不可变领域实体 + 纯逻辑编辑操作。
// 无 flutter/io/controller/存储依赖；不可变输入 → 确定性输出。

/// 块类型枚举（借鉴 AFFiNE block suite，含内嵌块供后续 M2 使用）。
enum NoteBlockType {
  /// 正文段落。
  text,

  /// 标题（level 1-6 存储在 props['level']）。
  heading,

  /// 无序列表项。
  bullet,

  /// 有序列表项。
  ordered,

  /// 待办清单项（checked 存储在 props['checked']）。
  todo,

  /// 代码块（language 存储在 props['language']）。
  code,

  /// 引用块。
  quote,

  /// 分割线。
  divider,

  /// 图片块（src 存储在 props['src']）。
  image,

  /// 标注块。
  callout,

  /// 内嵌画板（我们的画布能力，payload 存 props['document']）。
  canvas,

  /// 内嵌图表（payload 存 props['chart']）。
  chart,

  /// 链接块（href 存 props['href']）。
  link,

  /// 表格块。
  table,

  /// 数据库/数据视图块（预留）。
  database,
}

/// 块属性映射（类型相关的轻量元数据）。
///
/// heading → {'level': 1|2|3|4|5|6}
/// todo → {'checked': true|false}
/// code → {'language': 'dart'|'javascript'|...}
/// image → {'src': '...', 'alt': '...'}
/// link → {'href': '...', 'title': '...'}
/// canvas → {'document': `<DrawingDocument json>`}
typedef NoteBlockProps = Map<String, dynamic>;

/// AFFiNE 风格的不可变内容块。
///
/// 每个块有唯一 [id]、[type]、[text] 内容、可选 [props] 和有序 [children]。
/// 编辑操作由 [NoteBlockEditor] 完成，本类只承载数据。
class NoteBlock {
  const NoteBlock({
    required this.id,
    required this.type,
    this.text = '',
    NoteBlockProps? props,
    List<NoteBlock>? children,
  }) : props = props ?? const {},
       children = children ?? const [];

  /// 块唯一标识（文档内唯一）。
  final String id;

  /// 块类型。
  final NoteBlockType type;

  /// 块文本内容（纯文本；富文本场景可改用 delta）。
  final String text;

  /// 类型相关属性（heading level / todo checked / code language 等）。
  final NoteBlockProps props;

  /// 有序子块（嵌套结构，如列表项的嵌套子项）。
  final List<NoteBlock> children;

  // ── 便捷工厂 ──────────────────────────────────────────────

  factory NoteBlock.textBlock(String id, {String text = ''}) =>
      NoteBlock(id: id, type: NoteBlockType.text, text: text);

  factory NoteBlock.headingBlock(String id, {required int level, String text = ''}) =>
      NoteBlock(
        id: id,
        type: NoteBlockType.heading,
        text: text,
        props: {'level': level.clamp(1, 6)},
      );

  factory NoteBlock.todoBlock(String id, {String text = '', bool checked = false}) =>
      NoteBlock(
        id: id,
        type: NoteBlockType.todo,
        text: text,
        props: {'checked': checked},
      );

  factory NoteBlock.bulletBlock(String id, {String text = ''}) =>
      NoteBlock(id: id, type: NoteBlockType.bullet, text: text);

  factory NoteBlock.orderedBlock(String id, {String text = ''}) =>
      NoteBlock(id: id, type: NoteBlockType.ordered, text: text);

  factory NoteBlock.codeBlock(String id, {String text = '', String? language}) =>
      NoteBlock(
        id: id,
        type: NoteBlockType.code,
        text: text,
        props: language != null ? {'language': language} : const {},
      );

  factory NoteBlock.quoteBlock(String id, {String text = ''}) =>
      NoteBlock(id: id, type: NoteBlockType.quote, text: text);

  factory NoteBlock.dividerBlock(String id) =>
      NoteBlock(id: id, type: NoteBlockType.divider);

  factory NoteBlock.imageBlock(String id, {required String src, String? alt}) =>
      NoteBlock(
        id: id,
        type: NoteBlockType.image,
        props: alt != null ? {'src': src, 'alt': alt} : {'src': src},
      );

  // ── 不可变更新 ─────────────────────────────────────────────

  /// 返回一个修改了指定字段的新块（不可变 copyWith）。
  NoteBlock copyWith({
    String? id,
    NoteBlockType? type,
    String? text,
    NoteBlockProps? props,
    List<NoteBlock>? children,
  }) =>
      NoteBlock(
        id: id ?? this.id,
        type: type ?? this.type,
        text: text ?? this.text,
        props: props ?? this.props,
        children: children ?? this.children,
      );

  /// 是否包含子块。
  bool get hasChildren => children.isNotEmpty;

  /// 是否为纯文本类块（text / heading / bullet / ordered / todo / code / quote / callout）。
  bool get isTextual =>
      type == NoteBlockType.text ||
      type == NoteBlockType.heading ||
      type == NoteBlockType.bullet ||
      type == NoteBlockType.ordered ||
      type == NoteBlockType.todo ||
      type == NoteBlockType.code ||
      type == NoteBlockType.quote ||
      type == NoteBlockType.callout;

  // ── 序列化 ─────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'text': text,
    if (props.isNotEmpty) 'props': props,
    if (children.isNotEmpty)
      'children': children.map((c) => c.toJson()).toList(),
  };

  factory NoteBlock.fromJson(Map<String, dynamic> json) => NoteBlock(
    id: json['id'] as String,
    type: NoteBlockType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => NoteBlockType.text,
    ),
    text: json['text'] as String? ?? '',
    props: (json['props'] as Map<String, dynamic>?) ?? const {},
    children: (json['children'] as List? ?? const [])
        .map((e) => NoteBlock.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteBlock &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          text == other.text &&
          _propsEqual(props, other.props) &&
          _childrenEqual(children, other.children);

  @override
  int get hashCode => Object.hash(id, type, text, Object.hashAll(props.entries), Object.hashAll(children));

  @override
  String toString() => 'NoteBlock(id: $id, type: ${type.name}, text: "$text")';
}

bool _propsEqual(NoteBlockProps a, NoteBlockProps b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key) || a[key] != b[key]) return false;
  }
  return true;
}

bool _childrenEqual(List<NoteBlock> a, List<NoteBlock> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
