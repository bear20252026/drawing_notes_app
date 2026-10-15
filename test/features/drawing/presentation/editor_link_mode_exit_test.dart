// EUI-03（审计 2026-10-15）：连线模式残留——14 格工具条里只有 3 个入口清了
// `linkMode`，其余 9 个（画笔/铅笔/高亮/激光/橡皮/吸管/矩形/框选/文字/手型系）
// 都没清。后果有两半，都在这条用例里各钉一个可观测信号：
//   ①显示：`writingActive` 里 `!linkMode`（2026-10-15 补的互斥判据）会让
//     「先点连线再点画笔」之后**一格都不亮**；
//   ②行为：`_onItemTap` 的 `if (_linkMode)` 分支仍在接管元素点击，
//     点谁都当连线端点——用户已经「切回画笔」了却选不中元素。
// ①单独钉没有意义（它只是颜色），所以每条用例都真的去点两个元素，
// 用 `session.connectors` 是否为空来判「点击到底走了哪个分支」。
//
// 测试环境 AppLocalizations 为 null，工具 tip 与提示文案走 zh 兜底。
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/page_chart_item.dart';
import 'package:drawing_notes_app/core/canvas_model/page_connector.dart';
import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/core/navigation/editor_page_session.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 最小会话桩：只有两张图片元素，够连线两端各取一个。
class _FakeSession implements EditorPageSession {
  _FakeSession() {
    imageItems.add(PageImageItem(id: 'img1', x: 80, y: 300, filePath: ''));
    imageItems.add(PageImageItem(id: 'img2', x: 340, y: 300, filePath: ''));
  }

  final DrawingDocument doc = DrawingDocument(id: 'link_exit_doc', title: '连线残留');

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
  /// 工具岛约 14 格，默认 800×600 视口里靠下的格子会滚出可见区——
  /// 把画布拉大，用例只关心「点了哪格、产生了什么」，不关心布局。
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1300, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<_FakeSession> openEditor(WidgetTester tester) async {
    final session = _FakeSession();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: EditorPage(session: session)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return session;
  }

  Finder cellByTip(String tip) => find.byTooltip(tip);

  /// 工具格外层 Semantics 的 selected——两路编码里的「语义」那一路。
  bool cellSelected(WidgetTester tester, String tip) {
    final semantics = tester.widgetList<Semantics>(
      find.ancestor(of: cellByTip(tip), matching: find.byType(Semantics)),
    );
    return semantics.any((s) => s.properties.selected == true);
  }

  Finder imageOverlay(int index) => find.byWidgetPredicate(
    (w) =>
        w is Semantics &&
        (w.properties.label?.contains('画布对象：图片') ?? false),
    skipOffstage: false,
  ).at(index);

  Future<void> tapBothElements(WidgetTester tester) async {
    await tester.tap(imageOverlay(0));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(imageOverlay(1));
    await tester.pump(const Duration(milliseconds: 120));
  }

  const linkTip = '节点连线';

  testWidgets('对照：留在连线模式时点两个元素确实生成连接（证明这条分支可达）', (tester) async {
    useTallSurface(tester);
    final session = await openEditor(tester);

    await tester.tap(cellByTip(linkTip));
    await tester.pumpAndSettle();
    expect(cellSelected(tester, linkTip), isTrue, reason: '点一次连线格应进入连线模式');

    await tapBothElements(tester);
    await tester.pumpAndSettle();

    expect(
      session.connectors.map((c) => '${c.fromItemId}→${c.toItemId}'),
      ['img1→img2'],
      reason: '这条用例是后面所有用例的非空对照：端点链路本身必须是通的',
    );
    // SnackBar 的自动关闭计时器要放掉，否则测试收尾报 pending timer。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  // 九个「非连线」入口逐个走一遍：进入连线模式 → 点这一格 → 再点两个元素。
  // 期望连线模式已退出（格子不再亮 + 元素点击不产生连接）。
  const entriesToCheck = <String>[
    '画笔 (P)',
    '铅笔 (N)',
    '高亮笔 (M)',
    '激光指示器（临时尾迹）',
    '橡皮擦 (E)',
    '吸管工具',
    '矩形选区 (R)',
    '框选多个元素',
    '文字 (T)',
    '平移画布 (H)',
  ];

  for (final tip in entriesToCheck) {
    testWidgets('进入连线模式后点「$tip」必须退出连线模式（EUI-03）', (tester) async {
      useTallSurface(tester);
      final session = await openEditor(tester);

      await tester.tap(cellByTip(linkTip));
      await tester.pumpAndSettle();
      await tester.tap(cellByTip(tip));
      await tester.pumpAndSettle();

      expect(
        cellSelected(tester, linkTip),
        isFalse,
        reason: 'linkMode 没清就会一直亮着连线格；而画笔系那格因 !linkMode 判据一格不亮',
      );

      await tapBothElements(tester);
      await tester.pumpAndSettle();

      expect(
        session.connectors,
        isEmpty,
        reason: '点了别的工具还在接元素点击 = 用户切不出连线模式',
      );

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('连线模式退出后仍可从工具条重新进入（不得把入口修死）', (tester) async {
    useTallSurface(tester);
    await openEditor(tester);

    await tester.tap(cellByTip(linkTip));
    await tester.pumpAndSettle();
    expect(cellSelected(tester, linkTip), isTrue);

    await tester.tap(cellByTip('画笔 (P)'));
    await tester.pumpAndSettle();
    expect(cellSelected(tester, '画笔 (P)'), isTrue, reason: '退出连线后画笔格必须亮起来');

    await tester.tap(cellByTip(linkTip));
    await tester.pumpAndSettle();
    expect(cellSelected(tester, linkTip), isTrue, reason: '连线入口本身还得能用');
  });
}
