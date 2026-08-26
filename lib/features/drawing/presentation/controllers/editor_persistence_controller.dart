/// 编辑器持久化控制器 — 自动保存调度。
///
/// 从 editor_page_persistence.dart 拆分出的独立控制器。
/// 负责：
/// - 防抖自动保存调度
/// - 保存状态跟踪（进行中/排队/关闭）
/// - 退出前强制刷盘
///
/// 架构原则：
/// - 单一职责：仅管理保存调度，不处理 UI
/// - 通过回调与上层通信（保存执行器由外部注入）
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// 编辑器持久化控制器。
class EditorPersistenceController {
  EditorPersistenceController({
    required this.onSave,
    this.debounceDelay = const Duration(milliseconds: 800),
  });

  /// 保存执行器（由外部注入，实际执行落盘操作）。
  final Future<void> Function() onSave;

  /// 防抖延迟。
  final Duration debounceDelay;

  // ─── 保存状态 ──────────────────────────────────────────────

  bool _autosaving = false;
  bool _autosaveQueued = false;
  bool _closingEditor = false;
  bool _allowPopAfterSave = false;
  Completer<void>? _autosaveCompletion;
  Timer? _debounceTimer;

  /// 是否正在自动保存。
  bool get isAutosaving => _autosaving;

  /// 是否有排队的保存。
  bool get hasQueuedSave => _autosaveQueued;

  /// 编辑器是否正在关闭。
  bool get isClosing => _closingEditor;

  /// 是否允许弹出（保存完成后）。
  bool get canPop => _allowPopAfterSave;

  /// 保存完成的 Future（供外部等待）。
  Future<void>? get saveCompletion => _autosaveCompletion?.future;

  // ─── 公共方法 ──────────────────────────────────────────────

  /// 安排一次防抖自动保存。
  void scheduleAutosave() {
    if (_closingEditor) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDelay, _doAutosave);
  }

  /// 立即执行保存（取消防抖）。
  Future<void> saveNow() async {
    _debounceTimer?.cancel();
    await _doAutosave();
  }

  /// 退出前强制刷盘。
  Future<bool> flushBeforePop() async {
    await saveNow();
    return true;
  }

  /// 标记编辑器正在关闭。
  void markClosing() {
    _closingEditor = true;
  }

  /// 设置允许弹出状态。
  void setAllowPop(bool allow) {
    _allowPopAfterSave = allow;
  }

  /// 处置资源。
  void dispose() {
    _debounceTimer?.cancel();
    _autosaveCompletion?.complete();
  }

  // ─── 内部方法 ──────────────────────────────────────────────

  Future<void> _doAutosave() async {
    if (_autosaving) {
      _autosaveQueued = true;
      return;
    }

    _autosaving = true;
    _autosaveQueued = false;
    _autosaveCompletion = Completer<void>();

    try {
      await onSave();
    } on Exception catch (e) {
      debugPrint('[EditorPersistence] 自动保存失败: $e');
    } finally {
      _autosaving = false;
      _autosaveCompletion?.complete();
      _autosaveCompletion = null;

      // 如果保存期间又有修改，立即再保存
      if (_autosaveQueued && !_closingEditor) {
        _autosaveQueued = false;
        unawaited(_doAutosave());
      }
    }
  }
}

/// 顶层 unawaited 辅助函数。
void unawaited(Future<void> future) {
  future.catchError((_) {});
}
