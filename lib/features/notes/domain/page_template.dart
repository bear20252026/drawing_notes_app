import 'package:drawing_notes_app/features/drawing/domain/document.dart';

/// 页面创建模板。模板描述用户的真实记录任务，并映射为纸张与画布行为，
/// 使“新建”不再只是先创建空白页、再手动调整多项设置。
enum PageTemplate {
  blank,
  lined,
  grid,
  dot,
  meeting,
  cornell,
  planner,
  whiteboard,
}

extension PageTemplatePresentation on PageTemplate {
  String get label => switch (this) {
    PageTemplate.blank => '空白笔记',
    PageTemplate.lined => '横线笔记',
    PageTemplate.grid => '方格纸',
    PageTemplate.dot => '点阵笔记',
    PageTemplate.meeting => '会议记录',
    PageTemplate.cornell => '康奈尔笔记',
    PageTemplate.planner => '计划页',
    PageTemplate.whiteboard => '宽阔白板',
  };

  PaperType get paperType => switch (this) {
    PageTemplate.blank || PageTemplate.whiteboard => PaperType.blank,
    PageTemplate.lined || PageTemplate.meeting => PaperType.lined,
    PageTemplate.grid => PaperType.grid,
    PageTemplate.dot ||
    PageTemplate.cornell ||
    PageTemplate.planner => PaperType.dot,
  };

  bool get isInfinite => this == PageTemplate.whiteboard;
}
