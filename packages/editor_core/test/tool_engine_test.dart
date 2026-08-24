import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// 框架级——ToolEngine 统一工具引擎测试（纯逻辑——不搞崩）。
void main() {
  test('初始状态：draw 工具 + 整笔擦除 + 空心填充', () {
    const state = ToolEngineState();
    expect(state.currentTool, ToolType.draw);
    expect(state.eraserMode, EraserMode.stroke);
    expect(state.fillMode, FillMode.stroke);
    expect(state.strokeColor, '#000000');
    expect(state.strokeWidth, 2.0);
    expect(state.rainbowEnabled, false);
  });

  test('switchTool：工具切换（统一状态——不产生不同实现）', () {
    const state = ToolEngineState();
    final erased = state.switchTool(ToolType.erase);
    expect(erased.currentTool, ToolType.erase);
    expect(erased.eraserMode, EraserMode.stroke); // 模式保留（不会消失）。
    expect(state.currentTool, ToolType.draw); // 原实例不变。

    // 切换到其他工具再切回——橡皮擦模式仍保留（用户核心批评修复）。
    final selected = erased.switchTool(ToolType.select);
    final backToErase = selected.switchTool(ToolType.erase);
    expect(backToErase.eraserMode, EraserMode.stroke);
  });

  test('switchEraserMode：橡皮擦模式（整笔/像素——单一状态）', () {
    const state = ToolEngineState();
    final pixel = state.switchEraserMode(EraserMode.pixel);
    expect(pixel.eraserMode, EraserMode.pixel);
    // 切工具再切回——像素模式保留。
    final other = pixel.switchTool(ToolType.draw);
    final back = other.switchTool(ToolType.erase);
    expect(back.eraserMode, EraserMode.pixel); // 模式不丢（用户核心修复）。
  });

  test('isWholeStrokeErase/isPixelErase：橡皮擦模式判定', () {
    var state = const ToolEngineState().switchTool(ToolType.erase);
    expect(ToolEngine.isWholeStrokeErase(state), true);
    expect(ToolEngine.isPixelErase(state), false);

    state = state.switchEraserMode(EraserMode.pixel);
    expect(ToolEngine.isWholeStrokeErase(state), false);
    expect(ToolEngine.isPixelErase(state), true);

    // 非橡皮擦工具——都不是。
    final draw = state.switchTool(ToolType.draw);
    expect(ToolEngine.isWholeStrokeErase(draw), false);
    expect(ToolEngine.isPixelErase(draw), false);
  });

  test('setStrokeWidth：统一粗细范围（荧光与普通一致——用户修复）', () {
    const state = ToolEngineState();
    // 荧光模式——粗细上限与普通一致（32）。
    final highlighter = state.toggleHighlighter();
    expect(highlighter.highlighterMode, true);
    final thick = highlighter.setStrokeWidth(20);
    expect(thick.effectiveStrokeWidth, 20.0); // 荧光也支持 20。
    // 超上限——clamp。
    final over = state.setStrokeWidth(100);
    expect(over.effectiveStrokeWidth, 32.0);
    final under = state.setStrokeWidth(0);
    expect(under.effectiveStrokeWidth, 1.0);
  });

  test('effectiveWidth：荧光有效粗细（统一——用户修复）', () {
    var state = const ToolEngineState();
    state = state.toggleHighlighter().setStrokeWidth(8);
    expect(ToolEngine.effectiveWidth(state), 8.0); // 荧光粗细与其他一致。
    expect(state.effectiveStrokeWidth, 8.0);
  });

  test('fillMode：图形填充（stroke/fill/both——用户修复）', () {
    var state = const ToolEngineState();
    expect(ToolEngine.shouldFill(state), false); // stroke——不填充。
    expect(ToolEngine.shouldStroke(state), true);  // stroke——描边。

    state = state.switchFillMode(FillMode.fill);
    expect(ToolEngine.shouldFill(state), true);   // fill——实心。
    expect(ToolEngine.shouldStroke(state), false);

    state = state.switchFillMode(FillMode.both);
    expect(ToolEngine.shouldFill(state), true);   // both——实心+描边。
    expect(ToolEngine.shouldStroke(state), true);
  });

  test('setStrokeColor/setFillColor：图形颜色可换（用户修复）', () {
    var state = const ToolEngineState();
    state = state.setStrokeColor('#FF0000').setFillColor('#0000FF');
    expect(state.strokeColor, '#FF0000');
    expect(state.fillColor, '#0000FF');
    expect(ToolEngineState().strokeColor, '#000000'); // 原实例不变。
  });

  test('toggleRainbow：彩虹画笔开关', () {
    const state = ToolEngineState();
    final rainbow = state.toggleRainbow();
    expect(rainbow.rainbowEnabled, true);
    expect(state.rainbowEnabled, false); // 原实例不变。
  });

  test('copyWith：不可变 + 相等性', () {
    const state = ToolEngineState();
    final updated = state.copyWith(currentTool: ToolType.shape, strokeWidth: 5);
    expect(state.currentTool, ToolType.draw); // 原实例不变。
    expect(updated.currentTool, ToolType.shape);
    expect(updated.strokeWidth, 5.0);
    const other = ToolEngineState(currentTool: ToolType.shape, strokeWidth: 5);
    expect(updated, other); // 相等性按关键字段。
  });

  test('ToolType/EraserMode/FillMode 枚举', () {
    expect(ToolType.values.length, 8);
    expect(EraserMode.values.length, 2);
    expect(FillMode.values.length, 3);
  });
}
