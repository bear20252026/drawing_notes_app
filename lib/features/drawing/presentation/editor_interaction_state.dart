/// 画布混排对象交互暂态（C-04）：类型自 application 合并控制器库 re-export，
/// 保持 presentation 既有 import 路径与测试类名可用。
library;

import 'package:drawing_notes_app/features/drawing/application/editor_interaction_controllers.dart'
    as controllers;

export 'package:drawing_notes_app/features/drawing/application/editor_interaction_controllers.dart'
    show EditorCanvasInteractionState, EditorSelectionTransformState;

/// 历史类名：工具模式互斥状态（与 application [controllers.EditorToolModeController] 同一实现）。
typedef EditorToolModeState = controllers.EditorToolModeController;
