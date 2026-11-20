import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'package:drawing_notes_app/core/theme/apple_design.dart';
import 'package:drawing_notes_app/core/theme/apple_focus.dart';

/// 画布拖拽手柄（44px 命中区 + 可见蓝点）的统一样子。
///
/// 把「视觉 + 命中区 + 读屏 Semantics + 指针拖拽 + 键盘微调」收成一个控件：
/// 形状 8 向手柄、线性端点、文字宽度三处此前各写一遍，读屏标签、焦点环、
/// 按压缩放这类细节容易分叉。
///
/// ## 键盘等价入口（AGENTS.md §3 三输入纪律）
///
/// 聚焦手柄 → 方向键 = **一次离散拖拽**（屏幕像素 8px，Shift 32px），与画布
/// 小地图的 B3 入口同约定（`editor_page_canvas_surface.dart`）。
///
/// **为什么不做成全局快捷键**：8 向手柄的锚点语义各不相同（哪个边/角动），
/// 全局键无法区分「拖的是哪一个手柄」；只有聚焦到具体手柄才能表达。
///
/// ## 会话边界
///
/// 事务边界由**操作语义**决定，不由焦点决定（第四轮审计缺口 3）：指针拖拽的
/// 按下/抬起、键盘的每次按键各自成对 begin/结算（键盘逐键自起自结）。
/// 聚焦只驱动焦点环，不开启事务——只 Tab 到手柄上不会建快照，拖拽中
/// Delete 也不再被并进拖拽事务。
///
/// ## 焦点
///
/// 焦点环走 [AppleFocusRing]（2px Focus Blue 描边，DESIGN.md:300）。
/// Tab 由本控件自己吞掉并转发给焦点遍历：页面级快捷键处理器把 Tab 用作
/// 「轮选画布对象」（`editor_page_shortcuts.dart` 的 V-01），放行会被截走，
/// 键盘用户将困在手柄上。
///
/// 键盘触发的动作**永不动画**（DESIGN_SYSTEM 频率闸门）：本控件只做离散
/// 状态推进，不建 AnimationController。
class CanvasDragHandle extends StatelessWidget {
  const CanvasDragHandle({
    super.key,
    required this.label,
    required this.onPanUpdate,
    this.hint,
    this.onPanStart,
    this.onPanEnd,
    this.onPanCancel,
    this.visualSize = 10,
    this.circular = false,
  });

  /// 读屏标签。
  final String label;

  /// 读屏提示：说明键盘可用（如「方向键微调，Shift 加速」）。
  final String? hint;

  /// 拖拽增量（**屏幕**口径）。指针路径与键盘路径共用。
  ///
  /// 屏幕口径而非画布口径：手柄在屏幕上移动的距离应与缩放级别无关，
  /// 否则同一按键在放大时会「跳」得更多。
  final ValueChanged<Offset> onPanUpdate;

  /// 拖拽/键盘会话开始（宿主取基准、建快照）。
  final VoidCallback? onPanStart;

  /// 拖拽/键盘会话结束（宿主结算）。
  final VoidCallback? onPanEnd;

  /// 拖拽被系统取消（来电/手势竞争失败等）——宿主按取消结算。
  /// P1 架构收口（L-1）：此前无此通道，取消路径只能靠 onPanEnd 兜底，
  /// 语义混淆（取消被当提交）。null = 宿主未接（退化走 onPanEnd）。
  final VoidCallback? onPanCancel;

  /// 可见蓝点边长（px）。形状/文字手柄 10，线性端点 12。
  final double visualSize;

  /// 视觉是否为圆形（线性端点）而非圆角方块（形状/文字手柄）。
  final bool circular;

  /// 命中区边长（pt）：三输入纪律的 44×44 下限。
  static const double hitSize = 44;

  /// 方向键步长（屏幕像素）。
  static const double keyStep = 8;

  /// Shift 加速档（屏幕像素）。4× 步长，与小地图 B3 的 24/96 同倍数
  /// （那边基数大是因为小地图要一次跨过半张画布，本控件是逐像素微调）。
  static const double keyStepFast = 32;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKey,
      child: AppleFocusRing(
        borderRadius: circular ? AppleRadius.full : AppleRadius.xs,
        child: Semantics(
          label: label,
          hint: hint,
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => onPanStart?.call(),
            onPanUpdate: (details) => onPanUpdate(details.delta),
            onPanEnd: (_) => onPanEnd?.call(),
            onPanCancel: () => (onPanCancel ?? onPanEnd)?.call(),
            child: SizedBox(
              width: hitSize,
              height: hitSize,
              child: Center(
                child: Container(
                  width: visualSize,
                  height: visualSize,
                  decoration: BoxDecoration(
                    color: AppleColor.actionBlue,
                    // 四-2 统一（审计第 4 轮遗留）：手柄蓝从 Material #42A5F5
                    // 归位品牌 Action Blue，与 canvas_painter 选框族一致。
                    shape: circular ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: circular
                        ? null
                        : BorderRadius.circular(AppleRadius.xs),
                    border: Border.all(
                      color: Colors.white,
                      width: circular ? 1.5 : 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Tab 自行转发给焦点遍历（见类注释）。必须走**当前手柄节点**：
    // 用 FocusScope.of(context) 拿到的是外层 scope，遍历会跳过手柄群。
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        node.previousFocus();
      } else {
        node.nextFocus();
      }
      return KeyEventResult.handled;
    }

    final step = HardwareKeyboard.instance.isShiftPressed
        ? keyStepFast
        : keyStep;
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
      LogicalKeyboardKey.arrowRight => Offset(step, 0),
      LogicalKeyboardKey.arrowUp => Offset(0, -step),
      LogicalKeyboardKey.arrowDown => Offset(0, step),
      _ => Offset.zero,
    };
    if (delta == Offset.zero) return KeyEventResult.ignored;
    // M-7（第二轮审计 2026-11-18）：键盘微调独立会话——每次按键自起自结
    // （begin→update→end），与指针会话互不干扰。焦点不再触发事务边界
    // （第四轮审计缺口 3），按键是唯一的键盘会话起点。
    onPanStart?.call();
    onPanUpdate(delta);
    onPanEnd?.call();
    return KeyEventResult.handled;
  }
}
