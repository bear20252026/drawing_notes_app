// 由 Claude 团队生成 | Drawing Notes App
// 内联富文本编辑纯逻辑：围绕选区应用/移除样式。
// 纯 Dart，无 flutter/io/controller/存储依赖；不可变输入 → 确定性输出。

import 'package:drawing_notes_app/features/notes/domain/note_inline_span.dart';

/// 选区范围（左闭右开）。
class SpanRange {
  const SpanRange(this.start, this.end);

  final int start;
  final int end;

  bool get isEmpty => start >= end;
  int get length => (end - start).clamp(0, 1 << 30);

  bool contains(int offset) => offset >= start && offset < end;
}

/// 纯逻辑内联 span 编辑器。
///
/// 所有方法均为纯函数：输入旧 span 列表 → 输出新 span 列表，不修改输入。
/// 由 lead 在展示层调用，将编辑结果写回 NoteBlock props。
class TextSpanEditor {
  const TextSpanEditor();

  /// 在选区上应用粗体。
  /// 若选区内全部 span 已为粗体 → 移除粗体（toggle 语义）。
  List<NoteInlineSpan> applyBold(List<NoteInlineSpan> spans, SpanRange range) {
    return _toggleStyle(spans, range, (span) => span.bold, (span, v) => span.copyWith(bold: v));
  }

  /// 在选区上应用斜体。
  List<NoteInlineSpan> applyItalic(List<NoteInlineSpan> spans, SpanRange range) {
    return _toggleStyle(spans, range, (span) => span.italic, (span, v) => span.copyWith(italic: v));
  }

  /// 在选区上应用下划线。
  List<NoteInlineSpan> applyUnderline(List<NoteInlineSpan> spans, SpanRange range) {
    return _toggleStyle(spans, range, (span) => span.underline, (span, v) => span.copyWith(underline: v));
  }

  /// 在选区上应用链接。
  /// 若选区已有相同链接 → 移除链接。
  List<NoteInlineSpan> applyLink(List<NoteInlineSpan> spans, SpanRange range, String link) {
    if (range.isEmpty) return spans;
    final plainText = spans.plainText;
    final clampedStart = range.start.clamp(0, plainText.length);
    final clampedEnd = range.end.clamp(clampedStart, plainText.length);

    final result = <NoteInlineSpan>[];
    var offset = 0;

    for (final span in spans) {
      final spanStart = offset;
      final spanEnd = offset + span.text.length;
      offset = spanEnd;

      // 选区前的 span → 原样保留
      if (spanEnd <= clampedStart) {
        result.add(span);
        continue;
      }
      // 选区后的 span → 原样保留
      if (spanStart >= clampedEnd) {
        result.add(span);
        continue;
      }

      // 计算交集
      final intersectStart = spanStart > clampedStart ? spanStart : clampedStart;
      final intersectEnd = spanEnd < clampedEnd ? spanEnd : clampedEnd;

      // 选区前部分
      if (spanStart < intersectStart) {
        result.add(span.copyWith(text: span.text.substring(0, intersectStart - spanStart)));
      }

      // 交集部分：toggle 链接
      final intersectText = span.text.substring(intersectStart - spanStart, intersectEnd - spanStart);
      final hasSameLink = span.link == link;
      result.add(NoteInlineSpan(
        text: intersectText,
        bold: span.bold,
        italic: span.italic,
        underline: span.underline,
        link: hasSameLink ? null : link,
      ));

      // 选区后部分
      if (intersectEnd < spanEnd) {
        result.add(span.copyWith(text: span.text.substring(intersectEnd - spanStart)));
      }
    }

    return result.normalized();
  }

  /// 移除选区上的所有样式。
  List<NoteInlineSpan> clearStyle(List<NoteInlineSpan> spans, SpanRange range) {
    if (range.isEmpty) return spans;
    final plainText = spans.plainText;
    final clampedStart = range.start.clamp(0, plainText.length);
    final clampedEnd = range.end.clamp(clampedStart, plainText.length);

    final result = <NoteInlineSpan>[];
    var offset = 0;

    for (final span in spans) {
      final spanStart = offset;
      final spanEnd = offset + span.text.length;
      offset = spanEnd;

      if (spanEnd <= clampedStart || spanStart >= clampedEnd) {
        result.add(span);
        continue;
      }

      final intersectStart = spanStart > clampedStart ? spanStart : clampedStart;
      final intersectEnd = spanEnd < clampedEnd ? spanEnd : clampedEnd;

      if (spanStart < intersectStart) {
        result.add(span.copyWith(text: span.text.substring(0, intersectStart - spanStart)));
      }

      final intersectText = span.text.substring(intersectStart - spanStart, intersectEnd - spanStart);
      result.add(NoteInlineSpan.plain(intersectText));

      if (intersectEnd < spanEnd) {
        result.add(span.copyWith(text: span.text.substring(intersectEnd - spanStart)));
      }
    }

    return result.normalized();
  }

  // ── 内部工具 ───────────────────────────────────────────────

  List<NoteInlineSpan> _toggleStyle(
    List<NoteInlineSpan> spans,
    SpanRange range,
    bool Function(NoteInlineSpan) getter,
    NoteInlineSpan Function(NoteInlineSpan, bool) setter,
  ) {
    if (range.isEmpty) return spans;

    // 检查选区内是否全部已为该样式
    final allSet = _isAllStyleSet(spans, range, getter);

    final plainText = spans.plainText;
    final clampedStart = range.start.clamp(0, plainText.length);
    final clampedEnd = range.end.clamp(clampedStart, plainText.length);

    final result = <NoteInlineSpan>[];
    var offset = 0;

    for (final span in spans) {
      final spanStart = offset;
      final spanEnd = offset + span.text.length;
      offset = spanEnd;

      if (spanEnd <= clampedStart || spanStart >= clampedEnd) {
        result.add(span);
        continue;
      }

      final intersectStart = spanStart > clampedStart ? spanStart : clampedStart;
      final intersectEnd = spanEnd < clampedEnd ? spanEnd : clampedEnd;

      if (spanStart < intersectStart) {
        result.add(span.copyWith(text: span.text.substring(0, intersectStart - spanStart)));
      }

      final intersectText = span.text.substring(intersectStart - spanStart, intersectEnd - spanStart);
      result.add(setter(NoteInlineSpan(
        text: intersectText,
        bold: span.bold,
        italic: span.italic,
        underline: span.underline,
        link: span.link,
      ), !allSet));

      if (intersectEnd < spanEnd) {
        result.add(span.copyWith(text: span.text.substring(intersectEnd - spanStart)));
      }
    }

    return result.normalized();
  }

  bool _isAllStyleSet(
    List<NoteInlineSpan> spans,
    SpanRange range,
    bool Function(NoteInlineSpan) getter,
  ) {
    final plainText = spans.plainText;
    final clampedStart = range.start.clamp(0, plainText.length);
    final clampedEnd = range.end.clamp(clampedStart, plainText.length);
    var offset = 0;

    for (final span in spans) {
      final spanStart = offset;
      final spanEnd = offset + span.text.length;
      offset = spanEnd;

      final intersectStart = spanStart > clampedStart ? spanStart : clampedStart;
      final intersectEnd = spanEnd < clampedEnd ? spanEnd : clampedEnd;

      if (intersectStart < intersectEnd) {
        if (!getter(span)) return false;
      }
    }
    return true;
  }
}
