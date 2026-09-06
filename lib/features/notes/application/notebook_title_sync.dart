import 'package:drawing_notes_app/features/notes/domain/notebook.dart';

/// 命名同源收敛（2026-09-07 用户需求：同一文件在所有展示区必须同名，
/// 改名要同步）。
///
/// 三组「同一逻辑文件、多展示区」的标题映射：
/// - 分页画布页 ↔ 块文档副本：同 id（迁移以页 id 建副本），分别显示在
///   分页画布页卡与首页笔记区/全部文档/搜索；
/// - 克隆引用页 ↔ 源页：克隆存的是创建时的标题快照；
/// - 页面标题同时进入 AllDocs「note」条目与搜索路径。
///
/// 双向收敛规则（以「打开时页标题快照」防回跳）：
/// - 本会话改过名的页 → 页面标题优先（调用方保存后把页标题回写块文档副本）；
/// - 未改过名但块文档标题不同 → 块文档标题优先（外部在 DocPage 改的名，
///   页卡跟随）；
/// - 克隆引用页 → 恒跟随源页当前标题。
///
/// 所有函数只改内存对象、不碰磁盘，由调用方决定落盘方式（加密本走
/// encryptAndSave 时同样适用）。
class NotebookTitleSync {
  const NotebookTitleSync._();

  /// 克隆引用页的展示标题（'↪ ' 前缀 + 源页当前标题）。
  static String cloneTitleFor(String sourceTitle) => '↪ $sourceTitle';

  /// 保存前收敛（就地改 [notebook] 内存对象）：
  /// - 依 [blockDocTitleById]（块文档 id → 当前标题）回写「未改名页」；
  /// - 克隆页跟随源页当前标题：同本源页自动派生，跨本源经
  ///   [externalSourceTitles]（源页 id → 当前标题）补充；
  /// 返回「本会话改过名」的页 id 集合——调用方落盘后须把这些页标题回写
  /// 块文档副本（副本在块文档存储里，本函数不触碰磁盘）。
  static Set<String> convergeBeforeSave({
    required Notebook notebook,
    required Map<String, String> blockDocTitleById,
    required Map<String, String> pageTitlesAtOpen,
    Map<String, String> externalSourceTitles = const {},
  }) {
    final renamed = <String>{};
    final sourceTitles = <String, String>{
      ...externalSourceTitles,
      for (final page in notebook.pages)
        if (page.cloneOf == null) page.id: page.title,
    };
    for (final page in notebook.pages) {
      final ref = page.cloneOf;
      if (ref != null) {
        _followClone(page, sourceTitles[ref.pageId]);
        continue;
      }
      final docTitle = blockDocTitleById[page.id];
      if (docTitle == null) continue;
      final atOpen = pageTitlesAtOpen[page.id];
      if (atOpen != null && atOpen != page.title) {
        // 本会话改过名：页面优先，副本由调用方在落盘后回写。
        renamed.add(page.id);
      } else if (docTitle != page.title) {
        page
          ..title = docTitle
          ..updatedAt = DateTime.now();
      }
    }
    return renamed;
  }

  /// 让 [notebook] 中所有克隆引用页的标题跟随 [sourceTitlesByPageId]。
  /// 返回是否有变更（调用方据此决定是否落盘该本）。
  static bool followCloneSnapshots({
    required Notebook notebook,
    required Map<String, String> sourceTitlesByPageId,
  }) {
    var changed = false;
    for (final page in notebook.pages) {
      final ref = page.cloneOf;
      if (ref == null) continue;
      changed = _followClone(page, sourceTitlesByPageId[ref.pageId]) || changed;
    }
    return changed;
  }

  static bool _followClone(NotebookPage page, String? sourceTitle) {
    if (sourceTitle == null) return false;
    final expected = cloneTitleFor(sourceTitle);
    if (page.title == expected) return false;
    page
      ..title = expected
      ..updatedAt = DateTime.now();
    return true;
  }
}
