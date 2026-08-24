// shared/widgets——统一绘图工具栏（V1/V2 合并——2026-08-24）。
//
// 从 V1/V2 重复代码中统一的工具栏：
// - 支持 V1 DrawingController 和 V2 Riverpod 两种状态管理
// - 使用公共组件（ToolButton、ColorPickerDot 等）
// - 可配置显示哪些工具组
//
// 设计原则：
// - 纯 UI 组件，不含业务逻辑
// - 所有状态通过参数传入
// - 所有操作通过回调返回
// - 可被 V1/V2 共同使用
library;

import 'package:flutter/material.dart';

import 'editor_components.dart';

/// 统一工具栏（V1/V2 合并——2026-08-24）。
///
/// 支持配置：
/// - 工具组（画笔/橡皮擦/形状/文字/选择等）
/// - 颜色选择
/// - 线宽滑块
/// - 扩展按钮
class UnifiedToolbar extends StatelessWidget {
  const UnifiedToolbar({
    super.key,
    required this.state,
    required this.actions,
    this.showColorPicker = true,
    this.showStrokeWidth = true,
    this.showShapeTools = false,
    this.showTextTools = false,
    this.showSelectionTools = false,
    this.showEraserOptions = false,
    this.showZoomControls = false,
    this.showGridControls = false,
    this.customButtons = const [],
  });

  final UnifiedToolbarState state;
  final UnifiedToolbarActions actions;

  /// 是否显示颜色选择器。
  final bool showColorPicker;

  /// 是否显示线宽滑块。
  final bool showStrokeWidth;

  /// 是否显示形状工具。
  final bool showShapeTools;

  /// 是否显示文字工具。
  final bool showTextTools;

  /// 是否显示选择工具。
  final bool showSelectionTools;

  /// 是否显示橡皮擦选项。
  final bool showEraserOptions;

  /// 是否显示缩放控件。
  final bool showZoomControls;

  /// 是否显示网格控件。
  final bool showGridControls;

  /// 自定义按钮列表。
  final List<Widget> customButtons;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.grey[200],
      child: Row(
        children: [
          // 画笔工具
          ToolButton(
            icon: Icons.brush,
            tooltip: '画笔',
            isSelected: state.currentTool == 'draw',
            onTap: () => actions.onToolChanged('draw'),
          ),

          // 橡皮擦工具
          ToolButton(
            icon: Icons.auto_fix_high,
            tooltip: '橡皮擦',
            isSelected: state.currentTool == 'erase',
            onTap: () => actions.onToolChanged('erase'),
          ),

          // 橡皮擦选项
          if (showEraserOptions && state.currentTool == 'erase')
            _buildEraserOptions(context),

          // 选择工具
          if (showSelectionTools) ...[
            ToolButton(
              icon: Icons.select_all,
              tooltip: '选择',
              isSelected: state.currentTool == 'select',
              onTap: () => actions.onToolChanged('select'),
            ),
            ToolButton(
              icon: Icons.rectangle_outlined,
              tooltip: '矩形选区',
              isSelected: state.selectionTool == 'rect',
              onTap: () => actions.onSelectionToolChanged?.call('rect'),
            ),
            ToolButton(
              icon: Icons.gesture,
              tooltip: '套索选区',
              isSelected: state.selectionTool == 'lasso',
              onTap: () => actions.onSelectionToolChanged?.call('lasso'),
            ),
          ],

          // 形状工具
          if (showShapeTools) ...[
            ToolButton(
              icon: Icons.rectangle_outlined,
              tooltip: '矩形',
              isSelected: state.currentTool == 'shape' &&
                  state.currentShapeType == 'rect',
              onTap: () {
                actions.onToolChanged('shape');
                actions.onShapeTypeChanged?.call('rect');
              },
            ),
            ToolButton(
              icon: Icons.circle_outlined,
              tooltip: '椭圆',
              isSelected: state.currentTool == 'shape' &&
                  state.currentShapeType == 'ellipse',
              onTap: () {
                actions.onToolChanged('shape');
                actions.onShapeTypeChanged?.call('ellipse');
              },
            ),
            ToolButton(
              icon: Icons.remove,
              tooltip: '直线',
              isSelected: state.currentTool == 'shape' &&
                  state.currentShapeType == 'line',
              onTap: () {
                actions.onToolChanged('shape');
                actions.onShapeTypeChanged?.call('line');
              },
            ),
            ToolButton(
              icon: Icons.arrow_forward,
              tooltip: '箭头',
              isSelected: state.currentTool == 'shape' &&
                  state.currentShapeType == 'arrow',
              onTap: () {
                actions.onToolChanged('shape');
                actions.onShapeTypeChanged?.call('arrow');
              },
            ),
          ],

          // 文字工具
          if (showTextTools)
            ToolButton(
              icon: Icons.text_fields,
              tooltip: '文字',
              isSelected: state.currentTool == 'text',
              onTap: () => actions.onToolChanged('text'),
            ),

          // 吸管工具
          ToolButton(
            icon: Icons.colorize,
            tooltip: '吸管取色',
            isSelected: state.currentTool == 'eyedropper',
            onTap: () => actions.onToolChanged('eyedropper'),
          ),

          // 分隔线
          if (showColorPicker || showStrokeWidth)
            VerticalDivider(width: 16, thickness: 1),

          // 颜色选择器
          if (showColorPicker)
            ColorPickerDot(
              color: state.currentColor,
              onTap: actions.onShowColorPicker,
            ),

          // 线宽滑块
          if (showStrokeWidth)
            SizedBox(
              width: 120,
              child: Row(
                children: [
                  Icon(Icons.line_weight, size: 18),
                  Expanded(
                    child: Slider(
                      value: state.strokeWidth.clamp(1, 100),
                      min: 1,
                      max: 100,
                      onChanged: actions.onStrokeWidthChanged,
                    ),
                  ),
                ],
              ),
            ),

          // 线宽显示
          if (showStrokeWidth)
            Text(
              '${state.strokeWidth.round()}px',
              style: Theme.of(context).textTheme.bodySmall,
            ),

          // 分隔线
          if (showZoomControls || showGridControls)
            VerticalDivider(width: 16, thickness: 1),

          // 网格控件
          if (showGridControls) ...[
            ToolButton(
              icon: Icons.grid_4x4,
              tooltip: '网格显示',
              isSelected: state.gridVisible,
              onTap: actions.onToggleGrid ?? () {},
            ),
            ToolButton(
              icon: Icons.auto_fix_high,
              tooltip: '网格吸附',
              isSelected: state.snapToGrid,
              onTap: actions.onToggleSnap ?? () {},
            ),
          ],

          // 缩放控件
          if (showZoomControls) ...[
            ToolButton(
              icon: Icons.zoom_out,
              tooltip: '缩小',
              isSelected: false,
              onTap: actions.onZoomOut ?? () {},
            ),
            ToolButton(
              icon: Icons.zoom_in,
              tooltip: '放大',
              isSelected: false,
              onTap: actions.onZoomIn ?? () {},
            ),
            ToolButton(
              icon: Icons.fit_screen,
              tooltip: '适应画布',
              isSelected: false,
              onTap: actions.onFitToScreen ?? () {},
            ),
          ],

          // 自定义按钮
          ...customButtons,

          // 填充剩余空间
          Spacer(),

          // 模式提示
          _buildModeHint(context),
        ],
      ),
    );
  }

  Widget _buildEraserOptions(BuildContext context) {
    return PopupMenuButton<VoidCallback>(
      tooltip: '橡皮擦选项',
      icon: Icon(Icons.shape_line_outlined, size: 20),
      onSelected: (callback) => callback(),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          checked: state.eraserCanEraseShapes,
          value: () => actions.onEraserOptionChanged?.call(
            !state.eraserCanEraseShapes,
          ),
          child: Text('可擦除形状'),
        ),
      ],
    );
  }

  Widget _buildModeHint(BuildContext context) {
    String hint;
    Color? color;

    switch (state.currentTool) {
      case 'draw':
        hint = '画笔';
        break;
      case 'erase':
        hint = '橡皮擦';
        break;
      case 'text':
        hint = '点击画布放置文字';
        color = Theme.of(context).colorScheme.primary;
        break;
      case 'eyedropper':
        hint = '点击画布取色';
        color = Theme.of(context).colorScheme.primary;
        break;
      case 'select':
        hint = '选择';
        break;
      default:
        hint = '';
    }

    if (hint.isEmpty) return SizedBox.shrink();

    return Text(
      hint,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: color,
      ),
    );
  }
}

/// 统一工具栏状态（V1/V2 公共状态模型）。
class UnifiedToolbarState {
  const UnifiedToolbarState({
    required this.currentTool,
    this.currentShapeType = 'rect',
    this.selectionTool,
    this.currentColor = Colors.black,
    this.strokeWidth = 2.0,
    this.eraserCanEraseShapes = true,
    this.gridVisible = false,
    this.snapToGrid = false,
  });

  /// 当前工具（draw/erase/shape/text/select/eyedropper）。
  final String currentTool;

  /// 当前形状类型（rect/ellipse/line/arrow）。
  final String currentShapeType;

  /// 当前选择工具（rect/lasso/null）。
  final String? selectionTool;

  /// 当前颜色。
  final Color currentColor;

  /// 当前线宽。
  final double strokeWidth;

  /// 橡皮擦是否可擦除形状。
  final bool eraserCanEraseShapes;

  /// 网格是否可见。
  final bool gridVisible;

  /// 是否吸附到网格。
  final bool snapToGrid;
}

/// 统一工具栏操作（V1/V2 公共操作模型）。
class UnifiedToolbarActions {
  const UnifiedToolbarActions({
    required this.onToolChanged,
    this.onShapeTypeChanged,
    this.onSelectionToolChanged,
    this.onStrokeWidthChanged,
    this.onShowColorPicker,
    this.onEraserOptionChanged,
    this.onToggleGrid,
    this.onToggleSnap,
    this.onZoomIn,
    this.onZoomOut,
    this.onFitToScreen,
  });

  /// 工具变更回调。
  final ValueChanged<String> onToolChanged;

  /// 形状类型变更回调。
  final ValueChanged<String>? onShapeTypeChanged;

  /// 选择工具变更回调。
  final ValueChanged<String>? onSelectionToolChanged;

  /// 线宽变更回调。
  final ValueChanged<double>? onStrokeWidthChanged;

  /// 显示颜色选择器回调。
  final VoidCallback? onShowColorPicker;

  /// 橡皮擦选项变更回调。
  final ValueChanged<bool>? onEraserOptionChanged;

  /// 网格显示切换回调。
  final VoidCallback? onToggleGrid;

  /// 网格吸附切换回调。
  final VoidCallback? onToggleSnap;

  /// 缩放回调。
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onFitToScreen;
}
