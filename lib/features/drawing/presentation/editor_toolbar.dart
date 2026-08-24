import 'package:material_ui/material_ui.dart';

import 'package:drawing_notes_app/features/drawing/application/plugin_registry.dart';
import 'editor_toolbar_drawing_tools.dart';
import 'editor_toolbar_object_edit.dart';
import 'editor_toolbar_state.dart';

/// 编辑器工具栏（架构重构 R2：从 editor_page 外移，回调参数化）。
///
/// 设计原则（见 docs/ARCHITECTURE_REVISION.md）：
/// - 本组件**只负责工具栏 UI 布局**，不含业务逻辑；
/// - 所有状态经 [EditorToolbarState] 传入（只读）；
/// - 所有操作经 [EditorToolbarActions] 回调返回（由 editor_page 实现）；
/// - 不读写文件、不直接操作引擎——纯展示层。
///
/// 构建逻辑已拆分为：
/// - [DrawingToolsSection]：绘图/橡皮/选区/文字/形状/缩放工具按钮
/// - [ObjectEditSection]：混排对象（文字/形状）的样式编辑控件
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.state,
    required this.actions,
    required this.brushes,
  });

  final EditorToolbarState state;
  final EditorToolbarActions actions;
  final List<BrushExtension> brushes;

  @override
  Widget build(BuildContext context) {
    final isEraser = state.isEraser;
    return Material(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          children: [
            // 绘图工具区（画笔/橡皮/选区/文字/形状/缩放）
            DrawingToolsSection(state: state, actions: actions),
            // 当前颜色选择圆点
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Tooltip(
                message: '选择颜色',
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: actions.showColorPicker,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: state.color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black26),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 粗细滑块
            SizedBox(
              width: 120,
              child: Row(
                children: [
                  const Icon(Icons.line_weight, size: 18),
                  Expanded(
                    child: Slider(
                      value: state.activeSize.clamp(1, 100),
                      min: 1,
                      max: 100,
                      onChanged: actions.onSizeChanged,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${state.activeSize.round()}px',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            // 混排对象编辑控件
            ObjectEditSection(state: state, actions: actions),
            // 模式提示文本
            if (state.eyedropperActive)
              Text(
                '点击画布取色',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            else if (state.textToolActive)
              Text(
                '点击画布放置文字',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            else
              Text(
                isEraser ? '橡皮擦' : '画笔',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
        ),
      ),
    );
  }
}
