import 'package:drawing_notes_app/l10n/app_localizations.dart';

/// 持久化默认值与展示文案分离（E6 / E1 存量）。
///
/// **存储侧**：新建对象写空串 `''`；历史文件里已落盘的中文默认值
/// （`未命名` / `图层 1` 等）**原样保留**，不迁移、不覆盖。
/// **展示侧**：空串或历史默认串一律经 [AppLocalizations] 显示；
/// 导出文件名等无 BuildContext 路径用英文 `untitled`（文件系统安全）。
abstract final class DomainDisplayLabels {
  /// 历史写盘默认标题（DrawingDocument / 存储列表元数据）。
  static const legacyUntitledDoc = '未命名';

  /// 历史新建画布标题。
  static const legacyUntitledCanvas = '未命名画布';

  /// 历史分页画布 / 笔记本标题。
  static const legacyUntitledNotebook = '未命名分页画布';

  /// 历史笔记本页面标题。
  static const legacyUntitledPage = '未命名页面';

  /// 历史默认图层名前缀（`图层` / `图层 1`）。
  static const legacyLayerPrefix = '图层';

  /// 导出/文件名等无 locale 上下文时的英文回退。
  static const filesystemUntitled = 'untitled';

  static bool isUntitledDocTitle(String? title) {
    final t = title?.trim();
    return t == null || t.isEmpty || t == legacyUntitledDoc || t == legacyUntitledCanvas;
  }

  static bool isUntitledNotebookTitle(String? title) {
    final t = title?.trim();
    return t == null ||
        t.isEmpty ||
        t == legacyUntitledNotebook ||
        t == legacyUntitledDoc ||
        t == legacyUntitledCanvas;
  }

  static bool isUntitledPageTitle(String? title) {
    final t = title?.trim();
    return t == null ||
        t.isEmpty ||
        t == legacyUntitledPage ||
        t == legacyUntitledDoc;
  }

  static bool isLegacyOrEmptyLayerName(String? name) {
    final t = name?.trim();
    if (t == null || t.isEmpty) return true;
    return t == legacyLayerPrefix || t.startsWith('$legacyLayerPrefix ');
  }

  /// 画布/文档显示名。
  static String docTitle(AppLocalizations? l10n, String? title) {
    if (isUntitledDocTitle(title)) return l10n?.docUntitled ?? legacyUntitledDoc;
    return title!;
  }

  /// 分页画布/笔记本显示名。
  static String notebookTitle(AppLocalizations? l10n, String? title) {
    if (isUntitledNotebookTitle(title)) {
      return l10n?.docUntitled ?? legacyUntitledDoc;
    }
    return title!;
  }

  /// 笔记本页面显示名。
  static String pageTitle(AppLocalizations? l10n, String? title) {
    if (isUntitledPageTitle(title)) {
      return l10n?.nbUntitledPage ?? legacyUntitledPage;
    }
    return title!;
  }

  /// 图层面板显示名：历史 `图层 N` 或空 → `Layer N` / 本地化文案。
  static String layerName(AppLocalizations? l10n, String? name) {
    if (!isLegacyOrEmptyLayerName(name)) return name!;
    final n = _layerIndexFromLegacy(name);
    return l10n?.layerDefaultName(n) ?? '$legacyLayerPrefix $n';
  }

  /// 无 l10n 的导出/文件名安全回退。
  static String exportBaseName(String? title) {
    final t = title?.trim() ?? '';
    if (isUntitledDocTitle(t) || isUntitledNotebookTitle(t) || isUntitledPageTitle(t)) {
      return filesystemUntitled;
    }
    return t;
  }

  static int _layerIndexFromLegacy(String? name) {
    final t = name?.trim() ?? '';
    if (t == legacyLayerPrefix) return 1;
    final parts = t.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      final n = int.tryParse(parts.last);
      if (n != null && n > 0) return n;
    }
    return 1;
  }
}
