// 由 Claude 团队生成 | Drawing Notes App
// 应用级服务门面（R2-Q2，架构审计 2026-08-31）。
//
// 收敛 AppShell 中与"数据"相关的横切状态：store 实例、数据版本通知器、
// 全量文档缓存与加载器。AppShell 只保留导航与页面装配；路由函数因需要
// BuildContext 留在 shell。store 实例支持注入（测试用内存实现）。

import 'package:flutter/foundation.dart';

import 'package:drawing_notes_app/core/storage/tag_store.dart';
import 'package:drawing_notes_app/features/all_docs/infrastructure/favorite_store.dart';
import 'package:drawing_notes_app/features/doc/domain/note_block_doc.dart';
import 'package:drawing_notes_app/features/doc/infrastructure/note_block_doc_store.dart';
import 'package:drawing_notes_app/features/schedule/infrastructure/schedule_event_store.dart';

/// 应用级服务门面。
class AppServices {
  AppServices({
    NoteBlockDocStore? blockDocStore,
    FavoriteStore? favoriteStore,
    TagStore? tagStore,
    ScheduleEventStore? scheduleEventStore,
  }) : blockDocStore = blockDocStore ?? NoteBlockDocStore(),
       favoriteStore = favoriteStore ?? FavoriteStore(),
       tagStore = tagStore ?? TagStore(),
       scheduleEventStore = scheduleEventStore ?? ScheduleEventStore();

  /// 块文档存储（打字笔记）。
  final NoteBlockDocStore blockDocStore;

  /// 收藏存储。
  final FavoriteStore favoriteStore;

  /// 标签注册表。
  final TagStore tagStore;

  /// 日程存储（日历页；存储收口后由组合根创建并透传）。
  final ScheduleEventStore scheduleEventStore;

  /// 数据版本通知器：任何文档写盘后自增，驱动首页/AllDocs 刷新。
  final ValueNotifier<int> dataVersion = ValueNotifier(0);

  List<NoteBlockDoc>? _blockDocsCache;

  /// 全量块文档读取（反向链接索引数据源）。
  /// 内存缓存，[bumpDataVersion] 时失效。
  Future<List<NoteBlockDoc>> loadAllBlockDocs() {
    final cached = _blockDocsCache;
    if (cached != null) return Future.value(cached);
    return blockDocStore.loadAll().then((docs) {
      _blockDocsCache = docs;
      return docs;
    });
  }

  /// 数据版本自增 + 文档缓存失效（shell 内所有写盘后的统一出口）。
  void bumpDataVersion() {
    _blockDocsCache = null;
    dataVersion.value++;
  }

  /// 释放通知器（AppShell dispose 时调用）。
  void dispose() => dataVersion.dispose();
}
