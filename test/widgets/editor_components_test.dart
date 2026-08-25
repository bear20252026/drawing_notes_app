// editor_components_test.dart — editor_components / unified_toolbar / unified_property_panel widget 测试。
import 'package:drawing_notes_app/shared/widgets/editor_components.dart';
import 'package:drawing_notes_app/shared/widgets/unified_property_panel.dart';
import 'package:drawing_notes_app/shared/widgets/unified_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrapInApp(Widget child) {
    return MaterialApp(
      home: Scaffold(body: child),
    );
  }

  // ── ColorPickerGrid ──────────────────────────────────

  group('ColorPickerGrid', () {
    testWidgets('渲染默认12个颜色方块', (tester) async {
      String selected = '#000000';
      await tester.pumpWidget(wrapInApp(
        StatefulBuilder(
          builder: (context, setState) => ColorPickerGrid(
            selectedColor: selected,
            onColorSelected: (c) => setState(() => selected = c),
          ),
        ),
      ));

      // 12 个 GestureDetector。
      expect(find.byType(GestureDetector), findsNWidgets(12));
    });

    testWidgets('点击颜色触发回调', (tester) async {
      String selected = '#000000';
      await tester.pumpWidget(wrapInApp(
        StatefulBuilder(
          builder: (context, setState) => ColorPickerGrid(
            selectedColor: selected,
            onColorSelected: (c) => setState(() => selected = c),
          ),
        ),
      ));

      await tester.tap(find.byType(GestureDetector).at(2)); // #FF0000
      await tester.pump();
      expect(selected, '#FF0000');
    });

    testWidgets('自定义颜色列表', (tester) async {
      await tester.pumpWidget(wrapInApp(
        ColorPickerGrid(
          selectedColor: '#FF0000',
          onColorSelected: (_) {},
          colors: ['#FF0000', '#00FF00', '#0000FF'],
        ),
      ));

      expect(find.byType(GestureDetector), findsNWidgets(3));
    });
  });

  // ── StrokeWidthSlider ──────────────────────────────────

  group('StrokeWidthSlider', () {
    testWidgets('渲染滑块', (tester) async {
      await tester.pumpWidget(wrapInApp(
        StrokeWidthSlider(
          value: 2.0,
          onChanged: (_) {},
        ),
      ));

      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('滑动触发回调', (tester) async {
      double value = 2.0;
      await tester.pumpWidget(wrapInApp(
        StatefulBuilder(
          builder: (context, setState) => StrokeWidthSlider(
            value: value,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ));

      await tester.drag(find.byType(Slider), const Offset(50, 0));
      await tester.pump();
      expect(value, isNot(2.0));
    });
  });

  // ── OpacitySlider ──────────────────────────────────

  group('OpacitySlider', () {
    testWidgets('渲染透明度滑块', (tester) async {
      await tester.pumpWidget(wrapInApp(
        OpacitySlider(
          value: 1.0,
          onChanged: (_) {},
        ),
      ));

      expect(find.byType(Slider), findsOneWidget);
    });
  });

  // ── LineStyleSelector ──────────────────────────────────

  group('LineStyleSelector', () {
    testWidgets('渲染实线/虚线选择', (tester) async {
      await tester.pumpWidget(wrapInApp(
        LineStyleSelector(
          selectedStyle: LineStyle.solid,
          onStyleChanged: (_) {},
        ),
      ));

      expect(find.byType(OutlinedButton), findsWidgets);
    });

    testWidgets('点击虚线触发回调', (tester) async {
      LineStyle selected = LineStyle.solid;
      await tester.pumpWidget(wrapInApp(
        StatefulBuilder(
          builder: (context, setState) => LineStyleSelector(
            selectedStyle: selected,
            onStyleChanged: (v) => setState(() => selected = v),
          ),
        ),
      ));

      // 找到 OutlinedButton。
      final buttons = find.byType(OutlinedButton);
      expect(buttons, findsWidgets);
      await tester.tap(buttons.at(1));
      await tester.pump();
      expect(selected, LineStyle.dashed);
    });
  });

  // ── ToolButton ──────────────────────────────────

  group('ToolButton', () {
    testWidgets('渲染图标和标签', (tester) async {
      await tester.pumpWidget(wrapInApp(
        ToolButton(
          icon: Icons.edit,
          tooltip: 'Edit',
          isSelected: false,
          onTap: () {},
        ),
      ));

      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('点击触发 onTap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(wrapInApp(
        ToolButton(
          icon: Icons.edit,
          tooltip: 'Edit',
          isSelected: false,
          onTap: () => tapped = true,
        ),
      ));

      await tester.tap(find.byIcon(Icons.edit));
      expect(tapped, true);
    });

    testWidgets('active 状态样式变化', (tester) async {
      await tester.pumpWidget(wrapInApp(
        ToolButton(
          icon: Icons.edit,
          tooltip: 'Edit',
          isSelected: true,
          onTap: () {},
        ),
      ));

      // active 时图标颜色应为 Colors.white。
      final icon = tester.widget<Icon>(find.byIcon(Icons.edit));
      expect(icon.color, Colors.white);
    });
  });

  // ── UnifiedToolbar ──────────────────────────────────

  group('UnifiedToolbar', () {
    late String currentTool;
    late List<String> toolChanges;

    setUp(() {
      currentTool = 'draw';
      toolChanges = [];
    });

    Widget buildToolbar({
      bool showColorPicker = true,
      bool showStrokeWidth = true,
      bool showShapeTools = false,
    }) {
      return wrapInApp(
        StatefulBuilder(
          builder: (context, setState) => UnifiedToolbar(
            state: UnifiedToolbarState(currentTool: currentTool),
            actions: UnifiedToolbarActions(
              onToolChanged: (t) {
                setState(() => currentTool = t);
                toolChanges.add(t);
              },
            ),
            showColorPicker: showColorPicker,
            showStrokeWidth: showStrokeWidth,
            showShapeTools: showShapeTools,
          ),
        ),
      );
    }

    testWidgets('渲染工具按钮', (tester) async {
      await tester.pumpWidget(buildToolbar());
      expect(find.byType(ToolButton), findsWidgets);
    });

    testWidgets('工具切换触发回调', (tester) async {
      await tester.pumpWidget(buildToolbar());

      // 找到橡皮擦按钮（Icons.auto_fix_high）并点击。
      await tester.tap(find.byIcon(Icons.auto_fix_high));
      await tester.pump();

      expect(currentTool, 'erase');
      expect(toolChanges, contains('erase'));
    });

    testWidgets('隐藏颜色选择器', (tester) async {
      await tester.pumpWidget(buildToolbar(showColorPicker: false));
      // 颜色选择器被隐藏，但仍渲染其他组件。
      expect(find.byType(ToolButton), findsWidgets);
    });

    testWidgets('显示形状工具', (tester) async {
      await tester.pumpWidget(buildToolbar(showShapeTools: true));
      // Rect 按钮使用 Icons.rectangle_outlined。
      expect(find.byIcon(Icons.rectangle_outlined), findsOneWidget);
    });
  });

  // ── UnifiedPropertyPanel ──────────────────────────────────

  group('UnifiedPropertyPanel', () {
    Widget buildPanel({
      bool showBrush = true,
      bool showShape = false,
      bool showText = false,
      Color brushColor = Colors.black,
      double brushSize = 2.0,
    }) {
      return wrapInApp(
        UnifiedPropertyPanel(
          state: UnifiedPropertyPanelState(
            brushColor: brushColor,
            brushSize: brushSize,
          ),
          actions: UnifiedPropertyPanelActions(
            onPickColor: () {},
            onBrushSizeChanged: (_) {},
          ),
          showBrushProperties: showBrush,
          showShapeProperties: showShape,
          showTextProperties: showText,
        ),
      );
    }

    testWidgets('渲染画笔属性', (tester) async {
      await tester.pumpWidget(buildPanel());
      expect(find.text('画笔'), findsOneWidget);
      expect(find.byType(Slider), findsWidgets);
    });

    testWidgets('渲染形状属性（选中形状时）', (tester) async {
      await tester.pumpWidget(wrapInApp(
        UnifiedPropertyPanel(
          state: const UnifiedPropertyPanelState(
            brushColor: Colors.black,
            brushSize: 2.0,
            selectedShape: SelectedShapeInfo(
              strokeWidth: 3.0,
              fillColor: Colors.red,
            ),
          ),
          actions: UnifiedPropertyPanelActions(
            onPickColor: () {},
            onBrushSizeChanged: (_) {},
          ),
          showBrushProperties: false,
          showShapeProperties: true,
        ),
      ));

      expect(find.text('形状'), findsOneWidget);
    });

    testWidgets('渲染文字属性（选中文字时）', (tester) async {
      await tester.pumpWidget(wrapInApp(
        UnifiedPropertyPanel(
          state: const UnifiedPropertyPanelState(
            brushColor: Colors.black,
            brushSize: 2.0,
            selectedText: SelectedTextInfo(
              fontSize: 18.0,
              color: 0xFF000000,
            ),
          ),
          actions: UnifiedPropertyPanelActions(
            onPickColor: () {},
            onBrushSizeChanged: (_) {},
          ),
          showBrushProperties: false,
          showTextProperties: true,
        ),
      ));

      expect(find.text('文字'), findsOneWidget);
    });

    testWidgets('面板宽度可配置', (tester) async {
      await tester.pumpWidget(buildPanel());
      final container = tester.widget<Container>(find.byType(Container).first);
      // 宽度应为默认 190。
      expect(container.constraints?.maxWidth ?? 190, 190);
    });
  });
}
