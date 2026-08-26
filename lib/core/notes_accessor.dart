/// 跨功能笔记访问接口（S4b：drawing→notes 横向依赖接口化）。
///
/// 背景（docs/IMPROVEMENT_PLAN_2026-08-15.md）：
/// drawing 模块的 editor_exporter/search_service 需要笔记能力（导出
/// 混合 PDF、跨笔记搜索）。直接 import notes 具体类破坏"完全隔离"。
///
/// 本接口作为**跨功能契约**：
/// - 定义 drawing 侧所需的笔记能力（访问页面/存储）；
/// - notes 侧实现本接口并注入（构造注入，官方推荐）；
/// - drawing 侧只依赖本接口（core 允许依赖 domain 实体，依赖向内）。
///
/// 已接口化：editor_exporter 的 pageProvider（函数注入）、
/// search_service 的 notebookAccessor（本接口注入）。
///
/// 注意：此文件现在仅作为向后兼容的 re-export。
/// 新代码应直接导入 `core/abstractions/storage/notebook_accessor.dart`。
library;

export '../abstractions/storage/notebook_accessor.dart';
