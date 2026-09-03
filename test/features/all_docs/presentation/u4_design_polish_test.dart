// U4a 设计精修测试：触控目标 ≥44px + 右键/长按上下文菜单。

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/all_docs/domain/all_doc.dart';
import 'package:drawing_notes_app/features/all_docs/application/all_doc_query.dart';
import 'package:drawing_notes_app/features/all_docs/presentation/all_docs_page.dart';

AllDoc _doc(String id, String title) => AllDoc(
      id: id,
      title: title,
      kind: AllDocKind.blockdoc,
      folder: '',
      createdAt: DateTime(2026, 8, 1, 10),
      updatedAt: DateTime(2026, 8, 2, 10),
    );

Future<void> _pumpDesktop(
  WidgetTester tester, {
  void Function(AllDoc doc)? onOpenDoc,
  void Function(AllDoc doc)? onToggleFavorite,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: AllDocsPage(
        loadDocs: () async => buildAllDocs(
          docs: const [],
          notebooks: const [],
          blockDocs: [_doc('a', '设计稿')]
              .map(
                (d) => BlockDocMeta(
                  id: d.id,
                  title: d.title,
                  folder: '',
                  createdAt: d.createdAt,
                  updatedAt: d.updatedAt,
                ),
              )
              .toList(),
          now: DateTime(2026, 8, 2, 12),
        ),
        onOpenDoc: onOpenDoc ?? (_) {},
        onToggleFavorite: onToggleFavorite,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('桌面文档行星标触控目标 ≥44px', (tester) async {
    await _pumpDesktop(tester);
    final boxes = find.ancestor(
      of: find.byIcon(Icons.star_border_rounded),
      matching: find.byType(SizedBox),
    );
    expect(boxes, findsWidgets);
    final size = tester.getSize(boxes.first);
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('R6 星标/更多操作读屏语义（状态化 label + button 标志）', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpDesktop(tester);

    final star = tester.getSemantics(find.byIcon(Icons.star_border_rounded));
    expect(star.label, '添加收藏');
    expect(star.flagsCollection.isButton, isTrue);

    final menu = tester.getSemantics(find.byIcon(Icons.more_horiz_rounded));
    expect(menu.label, '更多操作');
    expect(menu.flagsCollection.isButton, isTrue);

    // SemanticsHandle 未 dispos 的校验发生在 tearDown 之前，须体内显式释放。
    handle.dispose();
  });

  testWidgets('桌面右键弹出上下文菜单：点「打开」回调 onOpenDoc', (tester) async {
    AllDoc? opened;
    await _pumpDesktop(tester, onOpenDoc: (d) => opened = d);

    final rowCenter = tester.getCenter(find.text('设计稿').first);
    final gesture = await tester.startGesture(
      rowCenter,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('打开'), findsOneWidget);
    expect(find.text('添加收藏'), findsOneWidget);

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(opened?.id, 'a');
  });

  testWidgets('右键菜单「添加收藏」回调 onToggleFavorite（乐观更新后为取消收藏）',
      (tester) async {
    AllDoc? toggled;
    await _pumpDesktop(tester, onToggleFavorite: (d) => toggled = d);

    final rowCenter = tester.getCenter(find.text('设计稿').first);
    final gesture = await tester.startGesture(
      rowCenter,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加收藏'));
    await tester.pumpAndSettle();
    expect(toggled?.id, 'a');
  });

  testWidgets('触屏长按同样弹出上下文菜单（移动端入口）', (tester) async {
    await _pumpDesktop(tester);

    final rowCenter = tester.getCenter(find.text('设计稿').first);
    final gesture = await tester.startGesture(rowCenter);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('打开'), findsOneWidget);
  });
}
