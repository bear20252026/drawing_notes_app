// 由 Claude 团队生成 | Drawing Notes App
// 行内样式入口的唯一判据与文案（FDC-03，业主 2026-10-17 选「标灰 + 说明」档）。
//
// 为什么要单独一处：样式入口有**两个**（底部工具条 `doc_editor_toolbar.dart` 与浮动选区
// 工具条 `doc_editor_selection.dart`），而「该不该灰」是一句判据、「为什么灰」是一句文案。
// 本仓反复出事的形态就是「一份判据 N 份副本且各份不一致」——所以两处都从这里取。

part of 'doc_editor.dart';

/// 样式按钮是否可点：入口自己有焦点/选区 **且** 样式真的被渲染。
///
/// 后半句来自 [inlineStylesAreRendered]（domain 里那份唯一判据，见 `note_inline_span.dart`）。
bool styleEntryEnabled({required bool hasTarget}) =>
    hasTarget && inlineStylesAreRendered;

/// 样式按钮的 tooltip：可用时报功能名，禁用时**连原因一起报**。
///
/// 灰掉但不说原因，等于让用户以为功能坏了；读屏用户更是只听到「粗体」然后按下无反应。
String styleEntryTooltip(BuildContext context, String label) {
  if (inlineStylesAreRendered) return label;
  return AppLocalizations.of(
    context,
  )?.styleUnwiredTip(label) ??
      '$label（暂不参与渲染，导出也不会带上）';
}
