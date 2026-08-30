/// Notes 领域模型的兼容性入口。
///
/// 保留此文件路径以兼容既有调用方；具体模型按职责拆分为独立的纯领域文件。
library;

export 'clone_ref.dart';
export 'notebook_entity.dart';
export 'notebook_page.dart';
export 'notebook_page_content.dart';
export 'notebook_page_template_strategy.dart';
export 'page_template.dart';
export 'page_version.dart';
export 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart';
export 'package:drawing_notes_app/core/canvas_model/page_connector.dart';
export 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
export 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
export 'package:drawing_notes_app/core/canvas_model/text_item.dart';
