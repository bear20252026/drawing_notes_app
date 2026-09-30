/// 编辑器指针/压感采样暂态（C-04 交互状态机拆分）。
///
/// 拖动增量基准（画布坐标）与压感笔上一点位置/时间——手势高频更新，
/// 不进文档、不触发重建。页面经 getter/setter 代理本类。
library;

import 'dart:ui';

/// 一次指针手势内的采样基准。
class EditorPointerSampleState {
  /// 上次拖动位置（画布坐标），用于计算移动增量。
  Offset? lastDragCanvas;

  /// 上次取色时间：pickColorAt 全量重绘的冷却节流锚点。
  DateTime? lastPickColorAt;

  /// 压感笔：上一采样点位置与时间（鼠标速度模拟压感）。
  Offset? lastPenPos;
  DateTime? lastPenTime;

  /// 抬起/取消手势：清空拖动增量基准。
  void resetDrag() {
    lastDragCanvas = null;
  }

  /// 新一轮书写：重置压感采样。
  void resetPen() {
    lastPenPos = null;
    lastPenTime = null;
  }

  /// 记录拖动增量基准。
  void noteDrag(Offset canvasPoint) {
    lastDragCanvas = canvasPoint;
  }

  /// 记录压感采样点。
  void notePen(Offset canvasPoint, DateTime at) {
    lastPenPos = canvasPoint;
    lastPenTime = at;
  }

  /// 标记取色时间（冷却节流）。
  void notePickColor(DateTime at) {
    lastPickColorAt = at;
  }
}
