import 'dart:async';

import 'package:flutter/foundation.dart';

/// 搜索输入防抖（U3 批次 2026-09-02，P1-12）。
///
/// 此前 AllDocs / 分页画布页内搜索每敲一个字符就整页 setState + 全量
/// 过滤排序，文档多时输入跟手性差。本工具把「输入 → 触发过滤」之间
/// 加 [duration] 合帧：连续击键只刷新输入框本身（由 TextEditingController
/// 驱动），停顿 [duration] 后才执行一次过滤刷新。
class SearchDebouncer {
  SearchDebouncer({this.duration = const Duration(milliseconds: 250)});

  final Duration duration;
  Timer? _timer;

  /// 合帧调度：连续调用只保留最后一次，[duration] 后执行 [action]。
  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  /// 立即执行并取消挂起的合帧（清空搜索等需要即时反馈的场景）。
  void flush(VoidCallback action) {
    _timer?.cancel();
    action();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
