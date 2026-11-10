// notes 侧的模板库门面（2026-10-10 解耦批次）。
//
// 背景：模板库原在 `features/doc/application/doc_templates.dart`，但全仓
// 唯一消费方是 notes 的「新建笔记」选择器——doc feature 内零引用。留在 doc
// 会让 notes 必须反向 import doc 的 application 层。
//
// 现模板本体已迁到 `core/documents/note_templates.dart`（模板是纯数据
// 构建器，与 `NoteBlock` 模型同层）；本文件只做**再导出**，让 notes 内的
// 既有 import 点（home_page.dart / home_page_create.dart）保持稳定，同时
// 保证 notes 不再出现任何 `features/doc/...` 路径。
//
// 若后续 notes 需要扩展模板（如按笔记类别分组），扩展点在本文件，
// 而不是回退到 doc。
export 'package:drawing_notes_app/core/documents/note_templates.dart';
