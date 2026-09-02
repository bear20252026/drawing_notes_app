// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '绘图笔记';

  @override
  String get search => '搜索';

  @override
  String get trash => '回收站（30 天内可恢复）';

  @override
  String get close => '关闭';

  @override
  String get delete => '删除';

  @override
  String get homeTrashEmpty => '回收站为空';

  @override
  String homeDeletedAt(String time) {
    return '删除于 $time';
  }

  @override
  String get homeRecover => '恢复';

  @override
  String get homeDeleteForever => '永久删除';

  @override
  String get homeEmptyTrash => '清空回收站';

  @override
  String get homeCancel => '取消';

  @override
  String get editorUndo => '撤销';

  @override
  String get editorRedo => '重做';

  @override
  String get editorShortcutsHelp => '快捷键帮助';

  @override
  String get editorMenu => '主菜单';

  @override
  String get editorClearCanvas => '清空画布';

  @override
  String get editorCopyPng => '复制 PNG 到剪贴板';

  @override
  String get editorExportPng => '导出 PNG';

  @override
  String get editorExportSvg => '导出 SVG';

  @override
  String get editorShapeTool => '形状工具';

  @override
  String get noteActions => '分页画布操作';

  @override
  String get noteImportPage => '从其他分页画布引入页面';

  @override
  String get noteImportMarkdown => '导入 Markdown 或文本';

  @override
  String get noteImportPdf => '导入 PDF 并逐页批注';

  @override
  String get noteTidyPages => '批量整理页面';

  @override
  String get noteFilterHint => '筛选标签或关键词';

  @override
  String get searchTitle => '全文搜索';

  @override
  String get searchHint => '搜索文字块内容 / 标题…';

  @override
  String get searchEmptyHint => '输入关键词开始搜索';

  @override
  String get searchNoResults => '未找到匹配内容';

  @override
  String get editorStrokeColor => '笔触颜色';

  @override
  String get editorEraseStroke => '命中笔画即删除整条线';

  @override
  String get editorEraseTransparent => '以透明像素挖空当前图层';

  @override
  String get editorHighlightNormal => '作为普通高亮笔写入页面，可撤销、保存和导出';

  @override
  String get editorLaserTemporary => '仅短暂显示，约 4 秒后平滑淡出，不写入页面';

  @override
  String get editorTextColor => '文字颜色';

  @override
  String get editorBold => '加粗 (Ctrl+B)';

  @override
  String get editorItalic => '斜体 (Ctrl+I)';

  @override
  String get editorExportPdf => '导出 PDF';

  @override
  String get editorExportJson => '导出 JSON';

  @override
  String get editorExportPptx => '导出 PPTX';

  @override
  String get editorExportWord => '导出 Word 兼容文档';

  @override
  String get editorUnderline => '下划线 (Ctrl+U)';

  @override
  String get editorPasteValues => '粘贴数值，用逗号/空格/换行分隔，例如：10, 25, 18, 42, 30';

  @override
  String editorImageInsertFail(String error) {
    return '插入图片失败：$error';
  }

  @override
  String get alignLeft => '左对齐';

  @override
  String get alignCenter => '居中';

  @override
  String get alignRight => '右对齐';

  @override
  String editorAlignTooltip(String name) {
    return '对齐：$name (Ctrl+E)';
  }

  @override
  String editorPagePreviewTitle(String title) {
    return '分页预览 $title';
  }
}
