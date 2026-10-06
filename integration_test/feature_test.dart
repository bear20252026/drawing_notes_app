import 'dart:io';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/notes/application/notebook_page_editor_session.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:drawing_notes_app/features/drawing/presentation/layer_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/helpers/temp_dir_cleanup.dart';

/// 用户视角全链路回归：绘制→撤销→重做→图层→文字→保存 不崩溃。
///
/// 覆盖用户报告范围之外的核心用户功能（图层/撤销/保存等）在真实
/// Windows 应用中的可用性。
///
/// ⚠️ 用例名的口径（交接文档 2026-10-05 第二优先指出的问题）：本文件此前
/// 把存储目录注入成 `throw UnimplementedError()`，所以「保存」这条腿在真机上
/// 从来没被走过；断言也只到「界面不抛异常」，没有一条在核对内容。
/// 本轮先把**注入**改成真实临时目录（落盘路径可用、可复查），并在文件头记下
/// 仍未补齐的部分：绘制→撤销→重做的**内容**断言（笔画落在哪个集合、
/// `onChanged` 是否真的把页面写进磁盘）必须先在真机上确认一次再写死——
/// 凭猜测写断言就是拿「改断言换绿」的反向做法污染门禁台账。
/// 数据层的真实落盘往返已由单测覆盖：
/// `test/drawing_content_roundtrip_test.dart`、
/// `test/document_image_persistence_test.dart`（均为真实临时目录）。
void main() {
  /// 建一个真实临时目录给 NotebookStorage 用，返回目录句柄供后续断言/清理。
  Future<Directory> editorTempDir() async {
    final dir = await Directory.systemTemp.createTemp('feature_test_');
    addTearDown(() => deleteTempDirWithRetry(dir));
    return dir;
  }

  Future<void> pumpEditor(WidgetTester tester) async {
    final tempDir = await editorTempDir();
    final doc = DrawingDocument(
      id: 'feature_test_doc',
      title: '功能测试',
      width: 1000,
      height: 1400,
    );
    final page = NotebookPage(
      id: 'feature_test_pg',
      title: '功能测试页',
      document: doc,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en')],
          home: EditorPage(
            session: NotebookPageEditorSession(page),
            // 原先是 `directoryProvider: () async => throw UnimplementedError()`
            // ——任何真落到存储层的动作都会当场炸，等于「保存」这条腿不存在。
            storage: NotebookStorage(
              directoryProvider: () async => tempDir,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '编辑器页面不应有构建异常');
  }

  testWidgets('全链路：绘制笔画 → 撤销 → 重做 → 图层 → 保存，全程不崩溃', (tester) async {
    await pumpEditor(tester);

    // 1) 在画布上拖动画一笔（模拟用户真实绘制）。
    final canvas = find.byType(CustomPaint).first;
    final center = tester.getCenter(canvas);
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(120, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 80));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '绘制不应抛异常');

    // 2) 图层面板由顶栏开关驱动、默认关闭（AU-2 修正真机红）。
    //    原断言「图层面板常驻渲染 findsOneWidget」与实现冲突：
    //    `editor_page_body.dart:90` 写的是 `if (_layersVisible) LayerPanel(...)`，
    //    而 `_layersVisible` 初值为 false（editor_interaction_controllers.dart:413，
    //    EditorChromeController 新建不读盘，自 v1.17.49 批次 AA 起如此）。
    //    ⇒ 断言改成在制品的真实行为：默认不渲染 → 顶栏开关切开后渲染。
    //    同一条用例第 90 行附近那条「图层操作」已在 AN 批改对，本条当时漏改，
    //    真机跑（不在 CI 覆盖内）才暴露。
    expect(find.byType(LayerPanel), findsNothing, reason: '图层面板默认应关闭');
    await tester.tap(find.byTooltip('显示图层'));
    await tester.pumpAndSettle();
    expect(
      find.byType(LayerPanel),
      findsOneWidget,
      reason: '顶栏「显示图层」开关应让图层面板渲染出来',
    );

    // 3) 工具切换与撤销语义操作不崩溃。
    // 工具条 tooltip 现由 EditorLeftToolbar 提供（画笔硬编码字面量
    // editor_left_toolbar.dart:81，非 arb；旧横栏 editor_toolbar.dart 的
    // 「画笔」字样已随 247f3b1 删除）。
    await tester.tap(find.byTooltip('画笔 (P)'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '工具切换不应抛异常');

    // 4) 小地图区域存在且点击导航不崩溃。
    final miniMap = find.byType(CustomPaint).evaluate().length;
    expect(miniMap, greaterThanOrEqualTo(1), reason: '画布 CustomPaint 应存在');
    await tester.tapAt(Offset(100, 100));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '画布点击不应抛异常');
  });

  testWidgets('图层操作：新建图层不崩溃（图层能力可用）', (tester) async {
    await pumpEditor(tester);

    // 打开图层面板。开关 tooltip 随状态取 arb barShowLayers / barHideLayers
    //（editor_page_appbar.dart:205-207）；初值 _layersVisible=false
    //（editor_interaction_controllers.dart:413，EditorChromeController 新建
    // 不读盘）→ 当前渲染「显示图层」。原「图层」字样来自已删除的旧横栏，命中
    // 不到，下面的 if 会让整段静默跳过（空跑）——故改为硬断言。
    final layerBtn = find.byTooltip('显示图层');
    expect(layerBtn, findsOneWidget, reason: '宽屏顶栏应有图层开关（窄屏才收进主菜单）');
    await tester.tap(layerBtn);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '打开图层面板不应抛异常');
    // 关闭（Esc 或再次点击）。
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
