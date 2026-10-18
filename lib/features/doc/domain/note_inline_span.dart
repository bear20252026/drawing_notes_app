// 由 Claude 团队生成 | Drawing Notes App
// 内联富文本 span 模型：承载块内文本的样式片段。
// 纯 Dart，无 flutter/io/controller/存储依赖。

/// 行内样式（粗体/斜体/下划线/链接）**今天没有任何读者**（第四轮审计 FDC-03，逐条回读）：
///
///  - 编辑渲染：`doc_editor_blocks.dart:494-517` 每个块是一个 `TextField`，`style:` 只有
///    一个整块样式（`_textStyleForBlockType`）⇒ 结构上呈现不了块内多段样式；
///  - Markdown 导出：`note_block_doc_markdown.dart` 只在注释里提过 `props['spans']`，不读；
///  - HTML / PDF 导出：`doc_html_export.dart` 只有 `.embed` 一条 CSS 斜体；
///    `doc_pdf_adapter.dart` 的 bold/italic 是标题与 CJK 字体，不是行内样式；
///    `rtf_exporter.dart:36-47` 那两个 `item.bold/item.italic` 属于**画布域** `TextItem`。
///
/// ⇒ 用户点粗体的真实后果：改动落盘、重开仍在，但界面与一切导出都看不见。
/// 处置（R46，业主 2026-10-17「全部推进推荐档」授权下按**推荐档**选的，不是逐条点名）：
/// 「**标灰 + 说明**」——两个样式入口在接上渲染之前禁用，tooltip 里说清原因；
/// 数据与入口代码都保留。**接上渲染那天把本值改成 true，入口自动恢复**，
/// 不必回头翻调用点。
///
/// 可写而不是 `const`，是为了让 FDC-01 那两条**必须走样式入口**才能造出形状的用例
/// 继续跑（`doc_editor_spans_text_authority_test.dart` 里置 true、tearDown 还原）。
/// 同一条纪律由 `test/architecture/inline_style_flag_write_gate_test.dart` 守着：
/// **`lib/` 里除本文件声明那行以外，任何位置给它赋值都算红**——生产只读，改它只有两条路：
/// 接上渲染（改这里的初值）或测试临时开一扇门。
bool inlineStylesAreRendered = false;

/// 内联富文本片段：携带文本 + 样式标记。
///
/// 用于在 NoteBlock 的文本块中表达粗体/斜体/下划线/链接等内联样式。
/// 多个 [NoteInlineSpan] 组成一个完整块文本；未标注区间视为纯文本。
class NoteInlineSpan {
  const NoteInlineSpan({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.link,
  });

  /// 文本内容。
  final String text;

  /// 是否粗体。
  final bool bold;

  /// 是否斜体。
  final bool italic;

  /// 是否下划线。
  final bool underline;

  /// 链接地址（非空时表示可点击链接）。
  final String? link;

  /// 是否为纯文本（无任何样式）。
  bool get isPlain => !bold && !italic && !underline && link == null;

  /// 是否为空文本。
  bool get isEmpty => text.isEmpty;

  /// 不可变 copyWith。
  NoteInlineSpan copyWith({
    String? text,
    bool? bold,
    bool? italic,
    bool? underline,
    String? link,
    bool clearLink = false,
  }) => NoteInlineSpan(
    text: text ?? this.text,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    link: clearLink ? null : (link ?? this.link),
  );

  /// 从纯文本创建（向后兼容）。
  factory NoteInlineSpan.plain(String text) => NoteInlineSpan(text: text);

  /// 合并相邻同样式 span（规范化）。
  bool canMergeWith(NoteInlineSpan other) =>
      bold == other.bold &&
      italic == other.italic &&
      underline == other.underline &&
      link == other.link;

  /// 与同样式 span 合并。
  NoteInlineSpan merge(NoteInlineSpan other) =>
      copyWith(text: text + other.text);

  /// 在指定位置切分 span，返回 (前半, 后半)。
  (NoteInlineSpan, NoteInlineSpan) splitAt(int offset) {
    final clamped = offset.clamp(0, text.length);
    return (
      copyWith(text: text.substring(0, clamped)),
      copyWith(text: text.substring(clamped)),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteInlineSpan &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          bold == other.bold &&
          italic == other.italic &&
          underline == other.underline &&
          link == other.link;

  @override
  int get hashCode => Object.hash(text, bold, italic, underline, link);

  @override
  String toString() =>
      'NoteInlineSpan(text: "$text", bold: $bold, italic: $italic, underline: $underline, link: $link)';
}

/// 内联 span 列表的工具扩展。
extension NoteInlineSpanList on List<NoteInlineSpan> {
  /// 拼接所有 span 的文本。
  String get plainText => fold('', (acc, span) => acc + span.text);

  /// 规范化：合并相邻同样式 span。
  List<NoteInlineSpan> normalized() {
    if (isEmpty) return [];
    final result = <NoteInlineSpan>[first];
    for (var i = 1; i < length; i++) {
      final last = result.last;
      final current = this[i];
      if (last.canMergeWith(current)) {
        result[result.length - 1] = last.merge(current);
      } else {
        result.add(current);
      }
    }
    return result;
  }

  /// 从纯文本创建单 span 列表（向后兼容）。
  static List<NoteInlineSpan> fromPlainText(String text) =>
      text.isEmpty ? [] : [NoteInlineSpan.plain(text)];
}
