import 'package:flutter/material.dart';

/// 文字展示布局的不可变结果。
final class EditorTextLayout {
  const EditorTextLayout({required this.constraints, required this.softWrap});

  final BoxConstraints constraints;
  final bool softWrap;
}

/// [EditorTextPresentationStyle.plainTextStyle] 的入参聚合（避免超长参数列表）。
typedef PlainTextStyleArgs = ({
  double fontSize,
  double viewScale,
  int color,
  String? fontFamily,
  bool isTodo,
  bool todoChecked,
  bool isSticky,
  bool bold,
  bool italic,
  bool underline,
  bool strikethrough,
});

/// 编辑器文字 overlay 的纯展示样式和布局映射。
///
/// 该协作者不读取 [BuildContext]、页面状态、控制器或领域对象，也不产生
/// 任何通知、写回或持久化副作用。
abstract final class EditorTextPresentationStyle {
  static EditorTextLayout layout({
    required double? width,
    required double viewScale,
  }) {
    return EditorTextLayout(
      constraints: width == null
          ? const BoxConstraints()
          : BoxConstraints(maxWidth: width * viewScale),
      softWrap: width != null,
    );
  }

  static TextStyle plainTextStyle(PlainTextStyleArgs args) {
    return TextStyle(
      fontSize: args.fontSize * args.viewScale,
      fontFamily: fontFamilyFor(args.fontFamily),
      color: plainTextColor(
        color: args.color,
        isTodo: args.isTodo,
        todoChecked: args.todoChecked,
        isSticky: args.isSticky,
      ),
      fontWeight: fontWeightFor(args.bold),
      fontStyle: fontStyleFor(args.italic),
      decoration: decorationFor(
        underline: args.underline,
        strikethrough: args.strikethrough,
      ),
    );
  }

  static TextStyle richBaseStyle({
    required double fontSize,
    required double viewScale,
    required String? fontFamily,
  }) {
    return TextStyle(
      fontSize: fontSize * viewScale,
      fontFamily: fontFamilyFor(fontFamily),
    );
  }

  static TextStyle richRunStyle({
    required int fallbackColor,
    required int? color,
    required bool bold,
    required bool italic,
    required bool underline,
    required bool strikethrough,
  }) {
    return TextStyle(
      color: Color(color ?? fallbackColor),
      fontWeight: fontWeightFor(bold),
      fontStyle: fontStyleFor(italic),
      decoration: decorationFor(
        underline: underline,
        strikethrough: strikethrough,
      ),
    );
  }

  static String? fontFamilyFor(String? fontFamily) {
    return switch (fontFamily) {
      'serif' => 'serif',
      'monospace' => 'monospace',
      'handwriting' => 'cursive',
      _ => null,
    };
  }

  static Color plainTextColor({
    required int color,
    required bool isTodo,
    required bool todoChecked,
    required bool isSticky,
  }) {
    return isTodo && todoChecked
        ? Color(color).withValues(alpha: 0.45)
        : (isSticky && color == 0xFFFFF59D
              ? const Color(0xFF3E2723)
              : Color(color));
  }

  static FontWeight fontWeightFor(bool bold) {
    return bold ? FontWeight.bold : FontWeight.normal;
  }

  static FontStyle fontStyleFor(bool italic) {
    return italic ? FontStyle.italic : FontStyle.normal;
  }

  static TextDecoration decorationFor({
    required bool underline,
    required bool strikethrough,
  }) {
    if (underline && strikethrough) {
      return TextDecoration.combine([
        TextDecoration.underline,
        TextDecoration.lineThrough,
      ]);
    }
    if (underline) return TextDecoration.underline;
    if (strikethrough) return TextDecoration.lineThrough;
    return TextDecoration.none;
  }

  static TextAlign textAlignFor(String alignment) {
    return switch (alignment) {
      'left' => TextAlign.left,
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      _ => TextAlign.left,
    };
  }
}
