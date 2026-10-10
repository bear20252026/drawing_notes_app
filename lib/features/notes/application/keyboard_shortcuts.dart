// KeyboardShortcuts —— 全库快捷键速查目录（批次 N，2026-09-27）。
//
// 数据来源：逐处核对代码注册点（editor_page_shortcuts / doc_editor /
// doc_editor_blocks / block_slash_menu / apple_design Esc 通道 / app.dart
// 全局热键），不是拍脑袋清单。标签经 AppLocalizations 解析（i18n 纪律：
// 用户可见文案不走硬编码）；键位组合为通用符号不本地化。
//
// E-03（审计 2026-09-27）：原实现每条 label 是 `x?.getter ?? '中文'`
// 闭包——33 条 ×2 分支把 catalog 圈复杂度推到 67（超阈值 60 的唯一
// 超标点）。改为 label 在 catalog 调用时**直接求值**（唯一消费方
// settings_page 同帧传同一 l10n，延迟闭包无意义）：null 走 const 中文
// 兜底表、非空走直接 getter，两条路径均零分支。
library;

import 'package:drawing_notes_app/l10n/app_localizations.dart';

/// 单条快捷键：[keys] 为通用键位符号（如 Ctrl+Z），[label] 为已解析文案。
class ShortcutEntry {
  const ShortcutEntry(this.keys, this.label);

  final String keys;
  final String label;
}

/// 分组标题 + 条目列表。
class ShortcutGroup {
  const ShortcutGroup(this.title, this.entries);

  final String title;
  final List<ShortcutEntry> entries;
}

/// 全库快捷键目录（按交互域分组）。
abstract final class KeyboardShortcuts {
  /// 目录：[l] 缺失（测试装配/未接 delegate）走 const 中文兜底表。
  static List<ShortcutGroup> catalog(AppLocalizations? l) =>
      l == null ? _catalogZh : _catalogOf(l);

  static const _catalogZh = [
    ShortcutGroup('画布工具', [
      ShortcutEntry('1', '画笔'),
      ShortcutEntry('2', '橡皮擦'),
      ShortcutEntry('3', '矩形选区'),
      ShortcutEntry('4', '套索选区'),
      ShortcutEntry('5', '文字工具'),
      ShortcutEntry('6', '矩形形状'),
      ShortcutEntry('7', '椭圆形状'),
      ShortcutEntry('8', '箭头形状'),
      ShortcutEntry('9', '直线形状'),
    ]),
    ShortcutGroup('编辑（画布与文字）', [
      ShortcutEntry('Ctrl+Z', '撤销'),
      ShortcutEntry('Ctrl+Y / Ctrl+Shift+Z', '重做'),
      ShortcutEntry('Ctrl+B', '加粗'),
      ShortcutEntry('Ctrl+I', '斜体'),
      ShortcutEntry('Ctrl+U', '下划线'),
      ShortcutEntry('Ctrl+E', '对齐文字'),
      ShortcutEntry('Ctrl+C / Ctrl+V', '复制 / 粘贴'),
      ShortcutEntry('Ctrl+Shift+C / V', '复制 / 粘贴样式'),
      ShortcutEntry('Ctrl+D', '创建副本'),
      ShortcutEntry('Delete / Backspace', '删除选中对象'),
      ShortcutEntry('方向键', '微调选中对象'),
      // V-01（审计 2026-09-27）：键盘轮选入口——此前 Delete/微调等
      // 键盘链路的前提「先用指针选中」对用户无从发现。
      ShortcutEntry('Tab / Shift+Tab', '轮选下一个对象'),
      ShortcutEntry('Esc', '清除选中'),
    ]),
    ShortcutGroup('块文档与面板', [
      ShortcutEntry('Ctrl+S', '保存文档'),
      ShortcutEntry('Ctrl+K / Ctrl+Shift+P', '命令面板'),
      ShortcutEntry('/', '插入块（斜杠菜单）'),
      ShortcutEntry('↑ ↓ / Enter / Esc', '菜单选择 / 确认 / 关闭'),
      ShortcutEntry('Esc', '关闭对话框 / 取消当前操作'),
      ShortcutEntry('Tab', '焦点遍历（键盘导航）'),
    ]),
    ShortcutGroup('全局', [
      ShortcutEntry('Ctrl+Alt+N', '快速记录（新建画布）'),
    ]),
  ];

  static List<ShortcutGroup> _catalogOf(AppLocalizations l) => [
    ShortcutGroup(l.scGroupCanvas, [
      ShortcutEntry('1', l.scToolBrush),
      ShortcutEntry('2', l.scToolEraser),
      ShortcutEntry('3', l.scToolRectSelect),
      ShortcutEntry('4', l.scToolLasso),
      ShortcutEntry('5', l.scToolText),
      ShortcutEntry('6', l.scShapeRect),
      ShortcutEntry('7', l.scShapeEllipse),
      ShortcutEntry('8', l.scShapeArrow),
      ShortcutEntry('9', l.scShapeLine),
    ]),
    ShortcutGroup(l.scGroupEditing, [
      ShortcutEntry('Ctrl+Z', l.scUndo),
      ShortcutEntry('Ctrl+Y / Ctrl+Shift+Z', l.scRedo),
      ShortcutEntry('Ctrl+B', l.scBold),
      ShortcutEntry('Ctrl+I', l.scItalic),
      ShortcutEntry('Ctrl+U', l.scUnderline),
      ShortcutEntry('Ctrl+E', l.scAlignText),
      ShortcutEntry('Ctrl+C / Ctrl+V', l.scCopyPaste),
      ShortcutEntry('Ctrl+Shift+C / V', l.scCopyPasteStyle),
      ShortcutEntry('Ctrl+D', l.scDuplicate),
      ShortcutEntry('Delete / Backspace', l.scDeleteSelected),
      ShortcutEntry('方向键', l.scNudge),
      ShortcutEntry('Tab / Shift+Tab', l.scSelectNextObject),
      ShortcutEntry('Esc', l.scClearSelection),
    ]),
    ShortcutGroup(l.scGroupDoc, [
      ShortcutEntry('Ctrl+S', l.scSaveDoc),
      ShortcutEntry('Ctrl+K / Ctrl+Shift+P', l.scCommandPalette),
      ShortcutEntry('/', l.scSlashMenu),
      ShortcutEntry('↑ ↓ / Enter / Esc', l.scSlashNavigate),
      ShortcutEntry('Esc', l.scCloseDialog),
      ShortcutEntry('Tab', l.scFocusNav),
    ]),
    ShortcutGroup(l.scGroupGlobal, [
      ShortcutEntry('Ctrl+Alt+N', l.scQuickRecord),
    ]),
  ];
}
