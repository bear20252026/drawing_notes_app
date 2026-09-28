// V-04（审计 2026-09-27）图表/图片 overlay 右键+长按上下文菜单测试。
//
// 此前画布上下文菜单（文字/形状已有）对图表与图片两类 overlay 漏配
// onSecondaryTapDown/onLongPressStart，行为不一致。本测试以行为断言
// 锁定接线：长按图表、右键图片均应弹出对象上下文菜单（首项「复制样式」）。
//
// 测试环境 AppLocalizations 为 null，菜单项走 zh 兜底文案。
// 坐标不硬编码：经 Semantics 包装定位 overlay 渲染矩形取中心。
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart';
import 'package:drawing_notes_app/core/canvas_model/page_connector.dart';
import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/core/navigation/editor_page_session.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 最小会话桩：只表达 overlay 渲染所需的混排集合。
class _FakeSession implements EditorPageSession {
  _FakeSession() {
    charts.add(
      PageChartItem(
        id: 'chart1',
        chartType: ChartType.bar,
        data: const [1, 2, 3],
      ),
    );
    imageItems.add(
      PageImageItem(id: 'img1', x: 100, y: 380, filePath: ''),
    );
  }

  final DrawingDocument doc = DrawingDocument(id: 'ovl_doc', title: '覆盖层');

  @override
  final List<PageTextItem> textItems = <PageTextItem>[];
  @override
  final List<PageImageItem> imageItems = <PageImageItem>[];
  @override
  final List<PageConnector> connectors = <PageConnector>[];
  @override
  final List<PageShapeItem> shapes = <PageShapeItem>[];
  @override
  final List<PageChartItem> charts = <PageChartItem>[];

  @override
  String get id => doc.id;

  @override
  String get title => doc.title;

  @override
  set title(String value) => doc.title = value;

  @override
  DrawingDocument get document => doc;

  @override
  DateTime get updatedAt => doc.updatedAt;

  @override
  set updatedAt(DateTime value) {}
}

void main() {
  Future<void> pumpEditor(WidgetTester tester, _FakeSession session) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: EditorPage(session: session)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder overlay(String semanticsLabel) => find.byWidgetPredicate(
    (w) => w is Semantics && (w.properties.label?.contains(semanticsLabel) ?? false),
    skipOffstage: false,
  );

  Future<void> pumpMenuOpen(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('图表 overlay 长按弹出上下文菜单（V-04）', (tester) async {
    final session = _FakeSession();
    await pumpEditor(tester, session);

    final center = tester.getCenter(overlay('画布对象：图表'));
    // 触屏长按 = 右键等价入口：按住超过 kLongPressTimeout 再抬起。
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await pumpMenuOpen(tester);

    expect(find.text('复制样式'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });

  testWidgets('图片 overlay 右键弹出上下文菜单（V-04）', (tester) async {
    final session = _FakeSession();
    await pumpEditor(tester, session);

    final center = tester.getCenter(overlay('画布对象：图片'));
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await gesture.up();
    await pumpMenuOpen(tester);

    expect(find.text('复制样式'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });
}
