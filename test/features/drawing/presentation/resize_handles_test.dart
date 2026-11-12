import 'package:drawing_notes_app/features/drawing/presentation/editor_selection_geometry.dart';
import 'package:drawing_notes_app/features/drawing/presentation/resize_handles.dart';
import 'package:drawing_notes_app/core/theme/apple_focus.dart';
import 'package:drawing_notes_app/shared/widgets/canvas_drag_handle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 取第 [index] 个手柄的 Focus 节点。
///
/// [CanvasDragHandle] 内部是两层 Focus：外层自己（可聚焦、收按键），
/// 内层是 AppleFocusRing 的观察节点（`canRequestFocus: false`）。
///
/// 取法是「从 AppleFocusRing 的元素往上找」：AppleFocusRing 的**元素自身**
/// 位于它内部那个 Focus 之上，所以 `Focus.maybeOf` 找到的第一个
/// `_FocusInheritedScope` 正是 CanvasDragHandle 的节点。比按
/// `find.ancestor` 的顺序取要稳——顺序是实现细节。
FocusNode _focusNodeAt(WidgetTester tester, int index) {
  final node = Focus.maybeOf(
    tester.element(find.byType(AppleFocusRing).at(index)),
  );
  expect(node, isNotNull, reason: '手柄必须挂在焦点树上');
  return node!;
}

void main() {
  testWidgets('八向手柄按展示顺序传递明确语义、画布增量和通知', (tester) async {
    final emitted = <(EditorShapeResizeHandle, Offset)>[];
    var notifications = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 160,
            child: ResizeHandles(
              width: 200,
              height: 160,
              screenToCanvasDelta: (delta) =>
                  Offset(delta.dx / 2, delta.dy / 2),
              onResize: (handle, canvasDelta) {
                emitted.add((handle, canvasDelta));
              },
              onChanged: () => notifications++,
            ),
          ),
        ),
      ),
    );

    final handleFinder = find.descendant(
      of: find.byType(ResizeHandles),
      matching: find.byType(GestureDetector),
    );
    expect(handleFinder, findsNWidgets(8));
    final gestures = tester.widgetList<GestureDetector>(handleFinder).toList();

    for (var index = 0; index < gestures.length; index++) {
      gestures[index].onPanUpdate!(
        DragUpdateDetails(
          globalPosition: Offset(index + 20.0, index + 40.0),
          delta: Offset(index + 2.0, index + 4.0),
        ),
      );
    }

    expect(
      emitted.map((entry) => entry.$1),
      orderedEquals(EditorShapeResizeHandle.values),
    );
    expect(
      emitted.first.$2,
      const Offset(1, 2),
      reason: '手柄只把宿主定义的屏幕到画布换算结果传出',
    );
    expect(notifications, 8, reason: '保持每次拖拽更新后的既有通知时序');
  });

  _keyboardEquivalenceGroup();
}

/// 键盘等价入口（AGENTS.md §3 三输入纪律）：手柄此前只有 `onPanUpdate`
/// 一条路径，触屏/鼠标可拖但键盘够不着。这些用例钉住「聚焦手柄 → 方向键」
/// 的离散拖拽语义，以及会话边界（端点手柄要取基准/结算）。
///
/// 步长是**屏幕**口径：`CanvasDragHandle.keyStep` 8px / `keyStepFast` 32px。
/// 测试里用 viewScale=2 的换算把它对回来，顺带钉住「屏幕口径」这件事——
/// 若哪天有人改成画布口径，放大时同一按键的位移会跟着变，这里会红。
void _keyboardEquivalenceGroup() {
  testWidgets('八向手柄：聚焦后方向键 = 一次离散缩放，Shift 加速', (tester) async {
    final emitted = <(EditorShapeResizeHandle, Offset)>[];
    var notifications = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 160,
            child: ResizeHandles(
              width: 200,
              height: 160,
              screenToCanvasDelta: (d) => Offset(d.dx / 2, d.dy / 2),
              onResize: (h, d) => emitted.add((h, d)),
              onChanged: () => notifications++,
            ),
          ),
        ),
      ),
    );

    _focusNodeAt(tester, 7).requestFocus(); // bottomRight
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(emitted, hasLength(1));
    expect(emitted.single.$1, EditorShapeResizeHandle.bottomRight);
    expect(emitted.single.$2, const Offset(4, 0), reason: '8 屏幕 px ÷ viewScale 2');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(emitted.last.$1, EditorShapeResizeHandle.bottomRight);
    expect(emitted.last.$2, const Offset(0, 16), reason: 'Shift 档 32 屏幕 px');
    expect(notifications, 2, reason: '每次按键都通知宿主，与拖拽同时序');

    // 非方向键不产生任何增量（交给上层/系统）。
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(emitted, hasLength(2));
  });

  testWidgets('八向手柄：聚焦时 Tab 走焦点遍历，不被页面级轮选截走',
      (tester) async {
    final next = FocusNode(debugLabel: 'next-focusable');
    addTearDown(next.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                width: 200,
                height: 160,
                child: ResizeHandles(
                  width: 200,
                  height: 160,
                  screenToCanvasDelta: (d) => d,
                  onResize: (_, _) {},
                  onChanged: () {},
                ),
              ),
              Focus(
                focusNode: next,
                child: const SizedBox(width: 10, height: 10),
              ),
            ],
          ),
        ),
      ),
    );

    _focusNodeAt(tester, 7).requestFocus();
    await tester.pump();
    expect(next.hasFocus, isFalse);

    // 页面级 _onShortcutKey 把 Tab 用作「轮选画布对象」；手柄必须自己吞掉
    // Tab 并转发给焦点遍历，否则键盘用户会困在手柄上。
    //
    // 8 个手柄各自都是可聚焦控件，所以 Tab 会先在手柄之间轮完一圈再离开
    // （实测：handle[7] → handle[0] … → 第 8 次才到 next）。这里钉住两件
    // 事：焦点确实离开了原手柄，且最终能走出手柄群。
    final handleNode = _focusNodeAt(tester, 7);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      handleNode.hasFocus,
      isFalse,
      reason: 'Tab 必须移动焦点，而不是被上层截去轮选对象',
    );

    // 轮完其余 7 个手柄后必须能到达手柄群之外的控件（否则就是陷阱）。
    var escaped = false;
    for (var i = 0; i < 8; i++) {
      if (next.hasFocus) {
        escaped = true;
        break;
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(
      escaped,
      isTrue,
      reason: '轮完手柄群后 Tab 必须能到达其他控件，不能困在手柄上',
    );
  });

  testWidgets('端点手柄：聚焦起会话、方向键走增量、失焦结算', (tester) async {
    var starts = 0;
    var ends = 0;
    final updates = <Offset>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              EndpointHandle(
                position: const Offset(50, 50),
                onPanStart: () => starts++,
                onPanUpdate: updates.add,
                onPanEnd: () => ends++,
              ),
            ],
          ),
        ),
      ),
    );

    _focusNodeAt(tester, 0).requestFocus();
    await tester.pump();
    expect(starts, 1, reason: '聚焦即起会话（宿主取拖拽基准）');
    expect(updates, isEmpty, reason: '只聚焦不按键不产生增量');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(updates, hasLength(1));
    expect(updates.single, const Offset(-8, 0), reason: '屏幕口径，不经 viewScale');

    _focusNodeAt(tester, 0).unfocus();
    await tester.pump();
    expect(ends, 1, reason: '失焦结算本次会话');
  });

  testWidgets('每个手柄都挂了键盘入口与可见焦点环', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 160,
            child: ResizeHandles(
              width: 200,
              height: 160,
              screenToCanvasDelta: (d) => d,
              onResize: (_, _) {},
              onChanged: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CanvasDragHandle), findsNWidgets(8));
    // 每个手柄都要有焦点环（2px Focus Blue 描边，DESIGN.md:300）。
    expect(
      find.descendant(
        of: find.byType(CanvasDragHandle),
        matching: find.byType(AppleFocusRing),
      ),
      findsNWidgets(8),
    );
    expect(_focusNodeAt(tester, 0), isNotNull);
  });
}
