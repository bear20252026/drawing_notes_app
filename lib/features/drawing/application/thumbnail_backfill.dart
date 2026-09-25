// 退出路径缩略图后台补渲队列（v1.17.20）。
//
// 背景：退出编辑器的保存兜底（SaveScheduler.flushIfDirty）此前在关闭中
// 仍同步渲染 1024px 缩略图——离屏栅格 + PNG 编码是退出路径最贵的一段
// （v1.17.18 只对「无改动」退出免掉了它，脏退出仍要等）。
//
// 方案：退出时只等文档 JSON 落盘，缩略图转交本队列——在编辑页 dispose
// 之后用文档快照重建临时控制器离屏渲染，序列化执行、同文档最新快照覆盖
// 旧排队项（防排队堆积）。渲染管线与在屏保存完全同源
// （DrawingController.renderToPng scale 0.2 / 长边 1024）。
//
// 测试：[renderOverride] 可注入假渲染函数（不触碰 dart:ui）。
import 'dart:async';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';

class ThumbnailBackfill {
  ThumbnailBackfill._();

  /// 缩略图渲染口径（与在屏保存一致）：内容包围盒 × 0.2，长边 1024。
  static const int _kLongEdge = 1024;
  static const double _kScale = 0.2;

  /// 测试注入口：默认 null = 真实管线（临时 DrawingController 离屏渲染）。
  static Future<Uint8List?> Function(DrawingDocument doc)? renderOverride;

  static final List<(DrawingDocument, StorageService)> _queue = [];
  static final Set<String> _pendingIds = <String>{};
  static bool _draining = false;

  /// 提交一次后台缩略图补渲（幂等合并：同文档已有排队项时以最新快照覆盖）。
  ///
  /// 立即对 [doc] 做 JSON 深拷贝快照——编辑页 dispose 后原文档不再安全。
  static void submit(DrawingDocument doc, StorageService storage) {
    final DrawingDocument snapshot;
    try {
      snapshot = DrawingDocument.fromJson(doc.toJson());
    } catch (error) {
      // 快照失败不阻断退出；下次进入编辑器自动保存会再补缩略图。
      AuditLogger.log(
        'thumbnail.backfill.snapshot',
        success: false,
        detail: error.runtimeType.toString(),
      );
      return;
    }
    // 同文档重复提交：覆盖式入队（latest-wins），由 drain 侧自然去重。
    _queue.add((snapshot, storage));
    _pendingIds.add(snapshot.id);
    unawaited(_drain());
  }

  /// 排队中的文档 id（测试观测用）。
  static bool get isPending => _pendingIds.isNotEmpty;

  /// 串行 drain：一次渲一张，异常吞掉不中断队列（缩略图可再生，
  /// 失败下次自动保存重试）。
  static Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final (doc, storage) = _queue.removeLast();
        _pendingIds.remove(doc.id);
        await _renderAndStore(doc, storage);
      }
    } finally {
      _draining = false;
    }
  }

  static Future<void> _renderAndStore(
    DrawingDocument doc,
    StorageService storage,
  ) async {
    try {
      final Uint8List? png;
      final override = renderOverride;
      if (override != null) {
        png = await override(doc);
      } else {
        final controller = DrawingController(doc);
        try {
          png = await controller.renderToPng(
            scale: _kScale,
            maxLongEdge: _kLongEdge,
          );
        } finally {
          controller.dispose();
        }
      }
      if (png != null) await storage.saveThumbnail(doc.id, png);
    } catch (error) {
      AuditLogger.log(
        'thumbnail.backfill.render',
        success: false,
        detail: error.runtimeType.toString(),
      );
    }
  }

  /// 测试辅助：清空队列状态。
  static void resetForTest() {
    _queue.clear();
    _pendingIds.clear();
    _draining = false;
    renderOverride = null;
  }
}
