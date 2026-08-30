import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用户体验缺陷修复回归测试（对应"画笔延迟"与"记笔记不跳转"两处修复）。
///
/// 覆盖：
/// - 绘制通知机制：高频路径（startStroke/extendStroke）触发 frameTick 重绘，
///   而非低频 notifyListeners（保证画布实时跟手、不重建整棵 UI 树）；
/// - 页面创建：NotebookPage 必须持有非空 document，序列化不抛异常
///   （修复 _newDocument 返回 null 导致的空指针、无法跳转缺陷）。
void main() {
  DrawingDocument makeDoc() =>
      DrawingDocument(id: 'reg_doc', title: '回归', width: 200, height: 200);

  group('绘制通知机制（修复画笔延迟）', () {
    test('startStroke/extendStroke 触发 frameTick 而非 notifyListeners', () async {
      final c = DrawingController(makeDoc());
      var notifyCount = 0;
      c.addListener(() => notifyCount++);
      final tick0 = c.frameTick.value;

      // 高频绘制路径：应当只 tick frameTick，不触发低频 notifyListeners。
      c.startStroke(const Offset(10, 10));
      c.extendStroke(const Offset(20, 20));
      c.extendStroke(const Offset(30, 30));

      expect(c.frameTick.value, greaterThan(tick0), reason: '绘制应推进帧通知');
      expect(notifyCount, 0, reason: '高频路径不应重建低频 UI（避免卡顿）');

      // 结束笔画提交：此时才应通知（撤销状态等低频变更）。
      await c.endStroke();
      expect(notifyCount, greaterThan(0), reason: '提交笔画后应通知低频组件');
    });

    test('frameTick 是 ValueNotifier，可被画布监听重绘', () {
      final c = DrawingController(makeDoc());
      var repaints = 0;
      c.frameTick.addListener(() => repaints++);
      c.startStroke(const Offset(0, 0));
      c.extendStroke(const Offset(5, 5));
      expect(repaints, greaterThanOrEqualTo(2), reason: '每次绘制操作都应触发重绘');
    });

    test('视口变换（缩放/旋转）也通过 frameTick 通知', () {
      final c = DrawingController(makeDoc());
      final tick0 = c.frameTick.value;
      // 模拟双指缩放：直接改 viewScale 后手动 tick（编辑器手势路径）。
      c.viewScale = 2.0;
      c.tickFrame();
      expect(c.frameTick.value, greaterThan(tick0));
    });

    test('undo/redo 等低频操作仍走 notifyListeners', () async {
      final c = DrawingController(makeDoc());
      var notifyCount = 0;
      c.addListener(() => notifyCount++);

      c.startStroke(const Offset(0, 0));
      c.extendStroke(const Offset(5, 5));
      await c.endStroke();
      notifyCount = 0; // 清零，只看 undo
      c.undo();
      expect(notifyCount, greaterThan(0), reason: 'undo 应通知低频 UI 更新');
    });
  });

  group('页面创建 document 非空（修复记笔记不跳转）', () {
    test('NotebookPage 构造必须持有非空 document', () {
      final page = NotebookPage(
        id: 'pg_1',
        title: '测试页面',
        document: DrawingDocument(id: 'doc_1', title: '页面文档'),
      );
      expect(page.document, isNotNull);
      expect(page.document.id, 'doc_1');
      expect(page.document.layers.length, 1, reason: '文档自带默认图层');
    });

    test('页面序列化/反序列化往返：document 完整保留', () {
      final page = NotebookPage(
        id: 'pg_2',
        title: '往返测试',
        document: DrawingDocument(
          id: 'doc_2',
          title: '页面文档',
          width: 300,
          height: 400,
        ),
      );
      // 序列化不应抛异常（修复前 document 为 null 时会 NPE）。
      final json = page.toJson();
      final restored = NotebookPage.fromJson(json);
      expect(restored.document, isNotNull);
      expect(restored.document.width, 300);
      expect(restored.document.height, 400);
      expect(restored.document.layers.length, 1);
    });

    test('笔记本保存含新页面：不抛异常且可完整恢复', () async {
      final page = NotebookPage(
        id: 'pg_3',
        title: '笔记本页面',
        document: DrawingDocument(id: 'doc_3', title: '页面文档'),
      );
      final nb = Notebook(id: 'nb_3', title: '笔记本');
      nb.pages.add(page);

      // toJson 全链路（Notebook -> 页面 -> 文档）不应抛异常。
      final json = nb.toJson();
      final restored = Notebook.fromJson(json);
      expect(restored.pages.length, 1);
      expect(restored.pages.first.document, isNotNull);
      expect(restored.pages.first.document.layers.length, 1);
    });
  });
}
