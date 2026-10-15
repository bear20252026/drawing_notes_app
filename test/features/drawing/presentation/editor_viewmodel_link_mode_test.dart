// EUI-03 的第二条腿（2026-10-15）。
//
// 页面那十个入口的互斥由 `editor_link_mode_exit_test.dart` 逐格驱动；这里钉的是
// `EditorViewModel` 自己那套「工具切换（UI 只调用这些方法）」的意图 API
// （selectBrush / selectEraser / selectEyedropper / selectText / selectRect /
// selectLasso）。这套 API 目前由 `EditorToolbarActionFactory` 与页面各自委托，
// 两条路此前**都没清 linkMode**——只在页面那侧补，等于把同一个判据留成两份，
// 下一份拷贝又会先红一边。
//
// 对照用例同样重要：`toggleLinkMode()` 打开连线后不能被自己的清理逻辑顺手关掉。
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/saving/save_scheduler.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  EditorViewModel buildViewModel() => EditorViewModel(
    controller: DrawingController(
      DrawingDocument(id: 'vm_link', title: '连线互斥'),
    ),
    saveScheduler: SaveScheduler(save: () async {}),
  );

  group('EditorViewModel 的工具切换一律退出连线模式', () {
    final intents = <String, void Function(EditorViewModel)>{
      'selectBrush': (vm) => vm.selectBrush(),
      'selectEraser': (vm) => vm.selectEraser(),
      'selectEyedropper': (vm) => vm.selectEyedropper(),
      'selectText': (vm) => vm.selectText(),
      'selectRect': (vm) => vm.selectRect(),
      'selectLasso': (vm) => vm.selectLasso(),
    };

    for (final entry in intents.entries) {
      test('${entry.key} 从连线模式切过去 ⇒ linkMode 与端点一起清', () {
        final vm = buildViewModel();
        vm.toggleLinkMode();
        vm.setLinkSourceId('item1');
        expect(vm.linkMode, isTrue, reason: '前置条件：确实处在连线模式');

        entry.value(vm);

        expect(
          vm.linkMode,
          isFalse,
          reason: '${entry.key} 必须让元素点击回到普通选中分支',
        );
        expect(
          vm.linkSourceId,
          isNull,
          reason: '端点草稿不能留在模式之外（高亮与下一次点击会拿它当起点）',
        );
      });
    }
  });

  test('toggleLinkMode 开→关→开 仍然可用（补齐互斥不能把入口本身修死）', () {
    final vm = buildViewModel();
    expect(vm.linkMode, isFalse);

    vm.toggleLinkMode();
    expect(vm.linkMode, isTrue, reason: '开关自身不能把自己清掉');
    vm.setLinkSourceId('item1');

    vm.toggleLinkMode();
    expect(vm.linkMode, isFalse);
    expect(vm.linkSourceId, isNull, reason: '关掉模式时端点草稿一并作废');

    vm.toggleLinkMode();
    expect(vm.linkMode, isTrue);
  });

  test('leaveLinkMode 幂等：真的在清时才发一次通知', () {
    final vm = buildViewModel();
    var notifications = 0;
    vm.addListener(() => notifications++);

    vm.leaveLinkMode();
    expect(
      notifications,
      0,
      reason: '本来就不在连线模式 ⇒ 空操作，不该让工具条白重建一次',
    );

    vm.toggleLinkMode();
    vm.setLinkSourceId('item1');
    notifications = 0;

    vm.leaveLinkMode();
    expect(vm.linkMode, isFalse);
    expect(vm.linkSourceId, isNull);
    expect(notifications, 1, reason: '成对清两个字段只发一次通知');

    vm.leaveLinkMode();
    expect(notifications, 1, reason: '第二次调用不再通知');
  });
}
