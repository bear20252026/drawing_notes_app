import 'package:flutter/material.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';
import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/selection.dart';

/// 纸张模板类型对应的图标。
IconData paperTypeIcon(PaperType type) => switch (type) {
  PaperType.blank => Icons.crop_portrait,
  PaperType.grid => Icons.grid_on,
  PaperType.lined => Icons.subject,
  PaperType.dot => Icons.more_horiz,
};

/// 纸张模板本地化名称（国际化收尾 2026-08-16；l10n 为空回落中文）。
String paperTypeName(PaperType type, AppLocalizations? l10n) => switch (type) {
  PaperType.blank => l10n?.paperBlank ?? '空白',
  PaperType.grid => l10n?.paperGrid ?? '网格',
  PaperType.lined => l10n?.paperLined ?? '横线',
  PaperType.dot => l10n?.paperDot ?? '点阵',
};

/// 文字对齐方式对应的图标。
IconData alignIcon(TextAlignType align) => switch (align) {
  TextAlignType.left => Icons.format_align_left,
  TextAlignType.center => Icons.format_align_center,
  TextAlignType.right => Icons.format_align_right,
};

/// 对齐工具提示（本地化——国际化收尾 2026-08-16）。
String alignTooltip(BuildContext context, TextAlignType align) {
  final l10n = AppLocalizations.of(context);
  final name = switch (align) {
    TextAlignType.left => l10n?.alignLeft ?? '左对齐',
    TextAlignType.center => l10n?.alignCenter ?? '居中',
    TextAlignType.right => l10n?.alignRight ?? '右对齐',
  };
  return l10n?.editorAlignTooltip(name) ?? '对齐：$name (Ctrl+E)';
}

/// 形状类型对应的图标（借鉴 Excalidraw 图形工具）。
IconData shapeTypeIcon(ShapeType type) => switch (type) {
  ShapeType.rect => Icons.crop_square,
  ShapeType.ellipse => Icons.circle_outlined,
  ShapeType.diamond => Icons.diamond_outlined,
  ShapeType.arrow => Icons.arrow_forward,
  ShapeType.line => Icons.remove,
};

/// 形状类型的中文名。
String shapeTypeName(ShapeType type) => switch (type) {
  ShapeType.rect => '矩形',
  ShapeType.ellipse => '椭圆',
  ShapeType.diamond => '菱形',
  ShapeType.arrow => '箭头',
  ShapeType.line => '直线',
};
