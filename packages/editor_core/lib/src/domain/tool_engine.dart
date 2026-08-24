// editor_core——ToolEngine 统一工具引擎（框架级重构——2026-08-22）。
//
// 用户批评：积木式拼接不能让一个功能在不同操作后出现不同实现——
// 橡皮擦时而能用时而不能用/整笔模式消失/荧光粗细不一致/图形不能换色。
// 根因：工具状态散落多处——没有统一工具引擎（单一状态源）。
//
// 框架级设计：ToolEngine = 所有工具的单一状态 + 行为源——
// 任何操作后工具行为一致（消除"不同实现"根因）。
// 纯 Dart 不可变模型——可独立测试——不搞崩。
library;

/// 工具类型（统一枚举——所有工具单一来源）。
enum ToolType {
  draw,          // 画笔
  select,        // 选择
  erase,         // 橡皮擦
  text,          // 文本
  shape,         // 形状（矩形/椭圆/箭头/三角形/棱锥）
  pan,           // 平移
  fill,          // 填充（实心覆盖）
  eyedropper,    // 取色
}

/// 橡皮擦模式（统一——不再"点几下就变"——stroke 兼容 V1）。
enum EraserMode {
  /// 整笔擦除（触碰笔画任意位置——整体移除——V1 语义 stroke）。
  stroke,

  /// 像素擦除（精确像素清除——BlendMode.clear）。
  pixel,
}

/// 填充模式（图形——stroke/fill/both——统一）。
enum FillMode {
  /// 仅描边（空心）。
  stroke,

  /// 仅填充（实心）。
  fill,

  /// 描边 + 填充。
  both,
}

/// 统一工具状态（不可变——单一状态源）。
///
/// 所有工具行为依赖此状态——任何操作后行为一致。
class ToolEngineState {
  const ToolEngineState({
    this.currentTool = ToolType.draw,
    this.eraserMode = EraserMode.stroke,
    this.fillMode = FillMode.stroke,
    this.strokeColor = '#000000',
    this.fillColor = '#000000',
    this.strokeWidth = 2.0,
    this.opacity = 1.0,
    this.rainbowEnabled = false,
    this.highlighterMode = false,
    this.maxStrokeWidth = 32.0,
    this.minStrokeWidth = 1.0,
  });

  final ToolType currentTool;
  final EraserMode eraserMode;
  final FillMode fillMode;
  final String strokeColor;
  final String fillColor;
  final double strokeWidth;
  final double opacity;

  /// 彩虹画笔（七彩色——复杂颜色混合变化）。
  final bool rainbowEnabled;

  /// 荧光模式（统一粗细上限——与普通画笔一致）。
  final bool highlighterMode;

  /// 统一粗细范围（荧光与普通画笔一致——消除粗细不一致根因）。
  final double maxStrokeWidth;
  final double minStrokeWidth;

  /// 荧光有效粗细（荧光透明度低——但粗细上限统一）。
  double get effectiveStrokeWidth => strokeWidth.clamp(minStrokeWidth, maxStrokeWidth);

  /// 切换工具。
  ToolEngineState switchTool(ToolType tool) {
    return copyWith(currentTool: tool);
  }

  /// 切换橡皮擦模式（统一状态——不会消失）。
  ToolEngineState switchEraserMode(EraserMode mode) {
    return copyWith(eraserMode: mode);
  }

  /// 切换填充模式。
  ToolEngineState switchFillMode(FillMode mode) {
    return copyWith(fillMode: mode);
  }

  /// 设置描边颜色。
  ToolEngineState setStrokeColor(String color) {
    return copyWith(strokeColor: color);
  }

  /// 设置填充颜色。
  ToolEngineState setFillColor(String color) {
    return copyWith(fillColor: color);
  }

  /// 设置线宽（统一范围限制——荧光也一致）。
  ToolEngineState setStrokeWidth(double width) {
    return copyWith(strokeWidth: width.clamp(minStrokeWidth, maxStrokeWidth));
  }

  /// 切换彩虹画笔。
  ToolEngineState toggleRainbow() {
    return copyWith(rainbowEnabled: !rainbowEnabled);
  }

  /// 切换荧光模式。
  ToolEngineState toggleHighlighter() {
    return copyWith(highlighterMode: !highlighterMode);
  }

  ToolEngineState copyWith({
    ToolType? currentTool,
    EraserMode? eraserMode,
    FillMode? fillMode,
    String? strokeColor,
    String? fillColor,
    double? strokeWidth,
    double? opacity,
    bool? rainbowEnabled,
    bool? highlighterMode,
  }) {
    return ToolEngineState(
      currentTool: currentTool ?? this.currentTool,
      eraserMode: eraserMode ?? this.eraserMode,
      fillMode: fillMode ?? this.fillMode,
      strokeColor: strokeColor ?? this.strokeColor,
      fillColor: fillColor ?? this.fillColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      opacity: opacity ?? this.opacity,
      rainbowEnabled: rainbowEnabled ?? this.rainbowEnabled,
      highlighterMode: highlighterMode ?? this.highlighterMode,
      maxStrokeWidth: maxStrokeWidth,
      minStrokeWidth: minStrokeWidth,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolEngineState &&
          currentTool == other.currentTool &&
          eraserMode == other.eraserMode &&
          strokeColor == other.strokeColor &&
          strokeWidth == other.strokeWidth;

  @override
  int get hashCode => Object.hash(currentTool, eraserMode, strokeColor, strokeWidth);
}

/// 统一工具引擎（框架级——所有工具的单一行为入口）。
///
/// 用户批评的核心修复：任何操作后工具行为一致——
/// - 橡皮擦模式（整笔/像素）单一状态——不会消失
/// - 荧光/普通画笔统一粗细上限
/// - 图形填充（stroke/fill/both）统一
/// - 取色/彩虹——统一开关
class ToolEngine {
  const ToolEngine();

  /// 处理工具切换（统一——不产生"不同实现"）。
  static ToolEngineState handleToolSelection(
    ToolEngineState state,
    ToolType selected,
  ) {
    return state.switchTool(selected);
  }

  /// 处理橡皮擦模式切换（统一状态——整笔/像素不会消失）。
  static ToolEngineState handleEraserMode(
    ToolEngineState state,
    EraserMode mode,
  ) {
    // 必须处于橡皮擦工具——但模式独立于工具状态（不会丢）。
    return state.switchEraserMode(mode);
  }

  /// 判断当前是否整笔擦除模式。
  static bool isWholeStrokeErase(ToolEngineState state) {
    return state.currentTool == ToolType.erase &&
        state.eraserMode == EraserMode.stroke;
  }

  /// 判断当前是否像素擦除模式。
  static bool isPixelErase(ToolEngineState state) {
    return state.currentTool == ToolType.erase &&
        state.eraserMode == EraserMode.pixel;
  }

  /// 荧光有效粗细（统一——荧光与普通画笔一致）。
  static double effectiveWidth(ToolEngineState state) {
    return state.effectiveStrokeWidth;
  }

  /// 图形是否应填充（fill/both——实心覆盖）。
  static bool shouldFill(ToolEngineState state) {
    return state.fillMode == FillMode.fill || state.fillMode == FillMode.both;
  }

  /// 图形是否应描边（stroke/both——空心）。
  static bool shouldStroke(ToolEngineState state) {
    return state.fillMode == FillMode.stroke || state.fillMode == FillMode.both;
  }
}
