import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/utils/wire_enum.dart';

/// 页面创建模板。模板描述用户的真实记录任务，并映射为纸张与画布行为，
/// 使“新建”不再只是先创建空白页、再手动调整多项设置。
enum PageTemplate implements WireEnum {
  blank,
  lined,
  grid,
  dot,
  meeting,
  cornell,
  planner,
  whiteboard;

  /// 落盘 wire 名（`template` 键，CTL-03 ②）：显式字面量，不读 `.name`。
  /// 与 [PageTemplatePresentation] 的展示口径分开——那个是给人看的，
  /// 这个是给磁盘看的。
  @override
  String get wireName => switch (this) {
    PageTemplate.blank => 'blank',
    PageTemplate.lined => 'lined',
    PageTemplate.grid => 'grid',
    PageTemplate.dot => 'dot',
    PageTemplate.meeting => 'meeting',
    PageTemplate.cornell => 'cornell',
    PageTemplate.planner => 'planner',
    PageTemplate.whiteboard => 'whiteboard',
  };

  /// 按 wire 名解码；未知/缺失返回 null，由调用点按既有口径回落。
  ///
  /// 收在本枚举里而不是让每个调用点去 import `core/utils/wire_enum.dart`：
  /// 那会把「解码某个枚举」变成一条新的跨层依赖（`notebook_page.dart` 的
  /// Martin 棘轮就因此红过一次），而 wire 名的知识本来就属于本枚举。
  static PageTemplate? fromWire(String? raw) => wireEnumOf(values, raw);
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
