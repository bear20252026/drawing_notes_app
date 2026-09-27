// KeyboardShortcuts —— 全库快捷键速查目录（批次 N，2026-09-27）。
//
// 数据来源：逐处核对代码注册点（editor_page_shortcuts / doc_editor /
// doc_editor_blocks / block_slash_menu / apple_design Esc 通道 / app.dart
// 全局热键），不是拍脑袋清单。标签经 AppLocalizations 解析（i18n 纪律：
// 用户可见文案不走硬编码，null 实例走中文兜底——与全库双轨口径一致）；
// 键位组合为通用符号不本地化。
library;

import 'package:drawing_notes_app/l10n/app_localizations.dart';

/// 单条快捷键：[keys] 为通用键位符号（如 Ctrl+Z），[label] 经 l10n 解析。
class ShortcutEntry {
  const ShortcutEntry(this.keys, this.label);

  final String keys;
  final String Function(AppLocalizations? l) label;
}

/// 分组标题 + 条目列表。
class ShortcutGroup {
  const ShortcutGroup(this.title, this.entries);

  final String Function(AppLocalizations? l) title;
  final List<ShortcutEntry> entries;
}

/// 全库快捷键目录（按交互域分组）。
abstract final class KeyboardShortcuts {
  static List<ShortcutGroup> catalog(AppLocalizations? l) => [
    ShortcutGroup(
      (x) => x?.scGroupCanvas ?? '画布工具',
      [
        ShortcutEntry('1', (x) => x?.scToolBrush ?? '画笔'),
        ShortcutEntry('2', (x) => x?.scToolEraser ?? '橡皮擦'),
        ShortcutEntry('3', (x) => x?.scToolRectSelect ?? '矩形选区'),
        ShortcutEntry('4', (x) => x?.scToolLasso ?? '套索选区'),
        ShortcutEntry('5', (x) => x?.scToolText ?? '文字工具'),
        ShortcutEntry('6', (x) => x?.scShapeRect ?? '矩形形状'),
        ShortcutEntry('7', (x) => x?.scShapeEllipse ?? '椭圆形状'),
        ShortcutEntry('8', (x) => x?.scShapeArrow ?? '箭头形状'),
        ShortcutEntry('9', (x) => x?.scShapeLine ?? '直线形状'),
      ],
    ),
    ShortcutGroup(
      (x) => x?.scGroupEditing ?? '编辑（画布与文字）',
      [
        ShortcutEntry('Ctrl+Z', (x) => x?.scUndo ?? '撤销'),
        ShortcutEntry('Ctrl+Y / Ctrl+Shift+Z', (x) => x?.scRedo ?? '重做'),
        ShortcutEntry('Ctrl+B', (x) => x?.scBold ?? '加粗'),
        ShortcutEntry('Ctrl+I', (x) => x?.scItalic ?? '斜体'),
        ShortcutEntry('Ctrl+U', (x) => x?.scUnderline ?? '下划线'),
        ShortcutEntry('Ctrl+E', (x) => x?.scAlignText ?? '对齐文字'),
        ShortcutEntry('Ctrl+C / Ctrl+V', (x) => x?.scCopyPaste ?? '复制 / 粘贴'),
        ShortcutEntry(
          'Ctrl+Shift+C / V',
          (x) => x?.scCopyPasteStyle ?? '复制 / 粘贴样式',
        ),
        ShortcutEntry('Ctrl+D', (x) => x?.scDuplicate ?? '创建副本'),
        ShortcutEntry(
          'Delete / Backspace',
          (x) => x?.scDeleteSelected ?? '删除选中对象',
        ),
        ShortcutEntry('方向键', (x) => x?.scNudge ?? '微调选中对象'),
      ],
    ),
    ShortcutGroup(
      (x) => x?.scGroupDoc ?? '块文档与面板',
      [
        ShortcutEntry('Ctrl+S', (x) => x?.scSaveDoc ?? '保存文档'),
        ShortcutEntry(
          'Ctrl+K / Ctrl+Shift+P',
          (x) => x?.scCommandPalette ?? '命令面板',
        ),
        ShortcutEntry('/', (x) => x?.scSlashMenu ?? '插入块（斜杠菜单）'),
        ShortcutEntry(
          '↑ ↓ / Enter / Esc',
          (x) => x?.scSlashNavigate ?? '菜单选择 / 确认 / 关闭',
        ),
        ShortcutEntry(
          'Esc',
          (x) => x?.scCloseDialog ?? '关闭对话框 / 取消当前操作',
        ),
        ShortcutEntry('Tab', (x) => x?.scFocusNav ?? '焦点遍历（键盘导航）'),
      ],
    ),
    ShortcutGroup(
      (x) => x?.scGroupGlobal ?? '全局',
      [
        ShortcutEntry(
          'Ctrl+Alt+N',
          (x) => x?.scQuickRecord ?? '快速记录（新建画布）',
        ),
      ],
    ),
  ];
}
