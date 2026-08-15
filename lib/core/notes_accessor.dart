import 'package:drawing_notes_app/features/notes/domain/notebook.dart';

/// 跨功能笔记访问接口（S4b：drawing→notes 横向依赖接口化）。
///
/// 背景（docs/ARCHITECTURE_ANALYSIS_2026-08-15.md 观察项 B）：
/// drawing 模块的 editor_exporter/search_service/editor_page 等需要
/// 笔记页面/存储（业务真实需求：导出混合 PDF、跨笔记搜索、编辑器集成
/// 笔记）。直接 import notes 实现破坏"完全隔离"理想。
///
/// 本接口作为**契约骨架**：
/// - 定义 drawing 侧所需的笔记能力（访问页面/存储）；
/// - notes 侧实现本接口并注入；
/// - drawing 侧只依赖本接口（core 允许依赖 domain 实体，依赖向内）。
/// 完整迁移按 S4b 专项渐进推进（editor_exporter→注入、search_service→
/// 注入、editor_page→注入），不一次大规模替换（政府项目审慎原则）。
abstract interface class INotebookAccessor {
  /// 读取指定笔记本页面（导出混合 PDF 时使用）。
  NotebookPage? pageById(String notebookId, String pageId);

  /// 当前笔记存储是否可用（搜索/编辑器集成时使用）。
  bool get isStorageAvailable;
}
