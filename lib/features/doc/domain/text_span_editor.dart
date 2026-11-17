// 由 Claude 团队生成 | Drawing Notes App
// 内联富文本编辑纯逻辑：围绕选区应用/移除样式。
// 纯 Dart，无 flutter/io/controller/存储依赖；不可变输入 → 确定性输出。

import 'package:drawing_notes_app/features/doc/domain/note_inline_span.dart';

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
    return _toggleStyle(
      spans,
      range,
      (span) => span.bold,
      (span, v) => span.copyWith(bold: v),
    );
  }

  /// 在选区上应用斜体。
  List<NoteInlineSpan> applyItalic(
    List<NoteInlineSpan> spans,
    SpanRange range,
  ) {
    return _toggleStyle(
      spans,
      range,
      (span) => span.italic,
      (span, v) => span.copyWith(italic: v),
    );
  }

  /// 在选区上应用下划线。
  List<NoteInlineSpan> applyUnderline(
    List<NoteInlineSpan> spans,
    SpanRange range,
  ) {
    return _toggleStyle(
      spans,
      range,
      (span) => span.underline,
      (span, v) => span.copyWith(underline: v),
    );
  }

  /// 在选区上应用链接。
  /// 若选区已有相同链接 → 移除链接。
  List<NoteInlineSpan> applyLink(
    List<NoteInlineSpan> spans,
    SpanRange range,
    String link,
  ) {
    // R4（审查 2026-11-16）：切分循环收敛进 _mapSelection——与
    // clearStyle/_toggleStyle 共用同一套 clamp/交集/前后段保留逻辑，
    // 差异只在交集段变换（此处 toggle 链接）。
    return _mapSelection(spans, range, (span, intersectText) {
      final hasSameLink = span.link == link;
      return NoteInlineSpan(
        text: intersectText,
        bold: span.bold,
        italic: span.italic,
        underline: span.underline,
        link: hasSameLink ? null : link,
      );
    });
  }

  /// 移除选区上的所有样式。
  List<NoteInlineSpan> clearStyle(List<NoteInlineSpan> spans, SpanRange range) {
    return _mapSelection(
      spans,
      range,
      (span, intersectText) => NoteInlineSpan.plain(intersectText),
    );
  }

  // ── 内部工具 ───────────────────────────────────────────────

  /// 选区切分核心（R4 收敛，2026-11-16）：clamp 选区 → 逐 span 三段切分
  /// （选区前/交集/选区后），前后段原样保留样式，交集段交给 [transform]。
  /// 此前 applyLink/clearStyle/_toggleStyle 各持一份同构循环（约 40 行 ×3），
  /// 收敛后切分语义只有一份——修边界 bug 不再需要三处同步。
  List<NoteInlineSpan> _mapSelection(
    List<NoteInlineSpan> spans,
    SpanRange range,
    NoteInlineSpan Function(NoteInlineSpan span, String intersectText) transform,
  ) {
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

      // 与选区无交集 → 原样保留。
      if (spanEnd <= clampedStart || spanStart >= clampedEnd) {
        result.add(span);
        continue;
      }

      final intersectStart = spanStart > clampedStart
          ? spanStart
          : clampedStart;
      final intersectEnd = spanEnd < clampedEnd ? spanEnd : clampedEnd;

      // 选区前部分（保留原样式）。
      if (spanStart < intersectStart) {
        result.add(
          span.copyWith(
            text: span.text.substring(0, intersectStart - spanStart),
          ),
        );
      }

      // 交集部分：交给调用方变换。
      final intersectText = span.text.substring(
        intersectStart - spanStart,
        intersectEnd - spanStart,
      );
      result.add(transform(span, intersectText));

      // 选区后部分（保留原样式）。
      if (intersectEnd < spanEnd) {
        result.add(
          span.copyWith(text: span.text.substring(intersectEnd - spanStart)),
        );
      }
    }

    return result.normalized();
  }

  List<NoteInlineSpan> _toggleStyle(
    List<NoteInlineSpan> spans,
    SpanRange range,
    bool Function(NoteInlineSpan) getter,
    NoteInlineSpan Function(NoteInlineSpan, bool) setter,
  ) {
    if (range.isEmpty) return spans;

    // 检查选区内是否全部已为该样式
    final allSet = _isAllStyleSet(spans, range, getter);

    return _mapSelection(
      spans,
      range,
      (span, intersectText) => setter(
        NoteInlineSpan(
          text: intersectText,
          bold: span.bold,
          italic: span.italic,
          underline: span.underline,
          link: span.link,
        ),
        !allSet,
      ),
    );
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

      final intersectStart = spanStart > clampedStart
          ? spanStart
          : clampedStart;
      final intersectEnd = spanEnd < clampedEnd ? spanEnd : clampedEnd;

      if (intersectStart < intersectEnd) {
        if (!getter(span)) return false;
      }
    }
    return true;
  }
}
