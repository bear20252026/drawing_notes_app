import 'package:flutter/foundation.dart';

import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_toolbar.dart';

/// 笔刷与橡皮擦相关的编辑器工具栏动作。
class EditorToolbarBrushActions {
  const EditorToolbarBrushActions({
    required this.selectBrush,
    required this.selectEraser,
    required this.setPixelEraserMode,
    required this.setEraserCanEraseShapesStroke,
    required this.setEraserCanEraseShapesPixel,
    required this.setTemporaryMarkerEnabled,
    required this.showColorPicker,
    required this.onSizeChanged,
    required this.onBrushSelected,
  });

  final VoidCallback selectBrush;
  final VoidCallback selectEraser;
  final ValueChanged<bool> setPixelEraserMode;
  final ValueChanged<bool> setEraserCanEraseShapesStroke;
  final ValueChanged<bool> setEraserCanEraseShapesPixel;
  final ValueChanged<bool> setTemporaryMarkerEnabled;
  final VoidCallback showColorPicker;
  final ValueChanged<double> onSizeChanged;
  final ValueChanged<String> onBrushSelected;
}

/// 文字、图片、选择、链接和页面级内容相关的工具栏动作。
class EditorToolbarObjectActions {
  const EditorToolbarObjectActions({
    required this.selectEyedropper,
    required this.selectRect,
    required this.selectLasso,
    required this.selectText,
    required this.recolorAllText,
    required this.toggleLink,
    required this.showPagination,
    required this.addStickyNote,
    required this.cyclePaper,
    required this.insertImage,
    required this.onSelectedFontSize,
    required this.changeTextColor,
    required this.toggleBold,
    required this.toggleItalic,
    required this.toggleUnderline,
    required this.toggleStrikethrough,
    required this.cycleAlign,
    required this.editText,
    required this.deleteSelected,
  });

  final VoidCallback selectEyedropper;
  final VoidCallback selectRect;
  final VoidCallback selectLasso;
  final VoidCallback selectText;
  final VoidCallback recolorAllText;
  final VoidCallback toggleLink;
  final VoidCallback showPagination;
  final VoidCallback addStickyNote;
  final VoidCallback cyclePaper;
  final VoidCallback insertImage;
  final ValueChanged<double> onSelectedFontSize;
  final VoidCallback changeTextColor;
  final VoidCallback toggleBold;
  final VoidCallback toggleItalic;
  final VoidCallback toggleUnderline;
  final VoidCallback toggleStrikethrough;
  final VoidCallback cycleAlign;
  final VoidCallback editText;
  final VoidCallback deleteSelected;
}

/// 图形对象与多选编辑相关的工具栏动作。
class EditorToolbarShapeActions {
  const EditorToolbarShapeActions({
    required this.onSelectShape,
    required this.setShapeFillEnabled,
    required this.onDistribute,
    required this.onShapeStrokeWidth,
    required this.onShapeOpacity,
    required this.onShapeFillColor,
    required this.onToggleMarquee,
    required this.onReorder,
    required this.onToggleDash,
  });

  final ValueChanged<ShapeType> onSelectShape;
  final ValueChanged<bool> setShapeFillEnabled;
  final ValueChanged<bool> onDistribute;
  final ValueChanged<double> onShapeStrokeWidth;
  final ValueChanged<double> onShapeOpacity;
  final VoidCallback onShapeFillColor;
  final VoidCallback onToggleMarquee;
  final ValueChanged<int> onReorder;
  final VoidCallback onToggleDash;
}

/// 画布视口导航与网格显示相关的工具栏动作。
class EditorToolbarViewportActions {
  const EditorToolbarViewportActions({
    required this.onToggleGrid,
    required this.onToggleSnap,
    required this.onFitToScreen,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
  });

  final VoidCallback onToggleGrid;
  final VoidCallback onToggleSnap;
  final VoidCallback onFitToScreen;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomReset;
}

/// 无副作用地将分组页面委托映射为既有工具栏控件动作契约。
///
/// 工厂只透传回调引用：不读取页面、控制器或 BuildContext，不持有状态，也不
/// 执行任何动作。由调用方决定状态更新、通知和持久化时序。
class EditorToolbarActionFactory {
  const EditorToolbarActionFactory._();

  static EditorToolbarActions build({
    required EditorToolbarBrushActions brush,
    required EditorToolbarObjectActions object,
    required EditorToolbarShapeActions shape,
    required EditorToolbarViewportActions viewport,
  }) => EditorToolbarActions(
    selectBrush: brush.selectBrush,
    selectEraser: brush.selectEraser,
    setPixelEraserMode: brush.setPixelEraserMode,
    setEraserCanEraseShapesStroke: brush.setEraserCanEraseShapesStroke,
    setEraserCanEraseShapesPixel: brush.setEraserCanEraseShapesPixel,
    setTemporaryMarkerEnabled: brush.setTemporaryMarkerEnabled,
    selectEyedropper: object.selectEyedropper,
    selectRect: object.selectRect,
    selectLasso: object.selectLasso,
    selectText: object.selectText,
    recolorAllText: object.recolorAllText,
    toggleLink: object.toggleLink,
    showPagination: object.showPagination,
    addStickyNote: object.addStickyNote,
    cyclePaper: object.cyclePaper,
    insertImage: object.insertImage,
    showColorPicker: brush.showColorPicker,
    onSizeChanged: brush.onSizeChanged,
    onSelectedFontSize: object.onSelectedFontSize,
    changeTextColor: object.changeTextColor,
    toggleBold: object.toggleBold,
    toggleItalic: object.toggleItalic,
    toggleUnderline: object.toggleUnderline,
    toggleStrikethrough: object.toggleStrikethrough,
    cycleAlign: object.cycleAlign,
    editText: object.editText,
    deleteSelected: object.deleteSelected,
    onBrushSelected: brush.onBrushSelected,
    onSelectShape: shape.onSelectShape,
    setShapeFillEnabled: shape.setShapeFillEnabled,
    onDistribute: shape.onDistribute,
    onShapeStrokeWidth: shape.onShapeStrokeWidth,
    onShapeOpacity: shape.onShapeOpacity,
    onShapeFillColor: shape.onShapeFillColor,
    onToggleMarquee: shape.onToggleMarquee,
    onReorder: shape.onReorder,
    onToggleGrid: viewport.onToggleGrid,
    onToggleSnap: viewport.onToggleSnap,
    onFitToScreen: viewport.onFitToScreen,
    onZoomIn: viewport.onZoomIn,
    onZoomOut: viewport.onZoomOut,
    onZoomReset: viewport.onZoomReset,
    onToggleDash: shape.onToggleDash,
  );
}
