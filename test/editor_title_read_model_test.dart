// P-09（审计 2026-09-27）：顶栏标题区专用读模型的行为锁。
//
// 审计原文：「顶栏标题区挂整个 DrawingController，每次笔画提交/擦除样本都
// 重建标题子树。拆专用 title Listenable」。
//
// 标题子树对 controller 的真实依赖只有 **title** 与 **isDirty** 两项，其余
// 显示输入来自 `_EditorPageState` 字段或整页常量。`TitleReadModel` 把源通知
// 收敛成签名比对：签名未变就不转发，LayoutBuilder+Row+Chip 子树因此不再随
// 每次 notifyListeners 重建。
//
// 本测试用 `notifyChanged()`（DrawingController 的公开通知入口，等价于
// `notifyListeners()` 但不改任何状态）构造「纯通知」场景——这正是日常
// 画布交互里最频繁、又与标题无关的那类通知。

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P-09：TitleReadModel 只在 title / isDirty 变化时转发通知', () {
    final controller = DrawingController(
      DrawingDocument(id: 'doc', title: '画布 A'),
    );
    final model = TitleReadModel(controller);
    var notified = 0;
    model.addListener(() => notified++);

    // 构造时已与源同步，自身不产生通知。
    expect(notified, 0, reason: '构造不应触发通知');

    // 纯通知（标题与脏标记都没动）→ 不转发。这正是标题子树此前被反复
    // 重建的来源：笔画提交之外的每次 controller 通知都会波及它。
    controller.notifyChanged();
    expect(notified, 0, reason: '无关通知不应重建标题子树');

    // 脏标记 false→true → 必须转发（「未保存」芯片要亮）。
    controller.touchDocument();
    controller.notifyChanged();
    expect(notified, 1, reason: 'isDirty 变化必须转发');

    // 脏标记已是 true，再来纯通知 → 不转发。
    controller.notifyChanged();
    expect(notified, 1, reason: '签名未变时不应重复转发');

    // 标题变化 → 必须转发（重命名要立刻反映到标题）。
    controller.document.title = '画布 B';
    controller.notifyChanged();
    expect(notified, 2, reason: '标题变化必须转发');

    // 再来纯通知 → 仍不转发。
    controller.notifyChanged();
    expect(notified, 2);

    model.dispose();
    // dispose 后源再通知：监听已解绑，不得抛错、也不得再计数。
    controller.notifyChanged();
    expect(notified, 2, reason: 'dispose 后必须已解绑');
    controller.dispose();
  });
}
