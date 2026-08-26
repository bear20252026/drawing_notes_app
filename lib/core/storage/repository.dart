/// 画作文档仓库抽象接口（B4，借鉴 Memos REST API 的存储解耦）。
///
/// UI/引擎层只依赖此接口，不感知具体存储实现；
/// 未来接云同步时实现同一接口即可替换（本地 JSON → 远端 API），
/// 画布与笔记逻辑无需改动。
///
/// 注意：此文件现在仅作为向后兼容的 re-export。
/// 新代码应直接导入 `core/abstractions/storage/document_repository.dart`。
library;

export '../abstractions/storage/document_repository.dart';
export '../abstractions/storage/notebook_repository.dart';
