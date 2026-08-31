// 全应用统一的布局断点（AFFiNE 式设备级分流的 Flutter 落地）。
//
// 背景：AFFiNE 在 `packages/common/env/src/ua-helper.ts` 里一次判定 isMobile，
// 然后渲染 `src/desktop/` 或 `src/mobile/` 两棵独立的视图树——移动端不是"把
// 桌面布局挤一挤"，而是重新设计信息架构。
//
// 本项目沿用其思路，但由于外层导航壳与内层页面是各自独立的 Widget，
// 判断必须在**每一层各做一次**：只在外层判断，内层的固定宽度面板（侧栏、
// 大纲条）就会原样进入手机屏——这正是「全部文档」页在手机上被 248px 侧栏
// 挤成 1/3 的根因。因此阈值必须收敛为单一来源，避免各层各自漂移。
import 'package:flutter/widgets.dart';

/// 桌面布局断点：可用宽度 ≥ 本值视为桌面/平板横屏（侧边栏、停靠面板、双栏）。
const double kDesktopBreakpoint = 900;

/// 当前上下文是否应渲染桌面布局。
///
/// 适用于拿不到约束的位置（顶栏按钮回调、showModalBottomSheet 分支等）。
/// 若已处于 [LayoutBuilder] 内，直接比较 [kDesktopBreakpoint] 更准确。
bool isDesktopLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

/// [LayoutBuilder] 内的断点判定：使用布局阶段传入的最大宽度。
bool isDesktopWidth(double maxWidth) => maxWidth >= kDesktopBreakpoint;
