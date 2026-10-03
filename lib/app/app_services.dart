// 由 Claude 团队生成 | Drawing Notes App
// 应用级服务门面（R2-Q2，架构审计 2026-08-31）。
//
// 收敛 AppShell 中与"数据"相关的横切状态：store 实例、数据版本通知器、
// 全量文档缓存与加载器。AppShell 只保留导航与页面装配；路由函数因需要
// BuildContext 留在 shell。store 实例支持注入（测试用内存实现）。
//
// C-07（审计 2026-09-27）：缺省装配知识移出本文件——服务单例装配唯一
// 落点 = 组合根 `CompositionRoot.createAppServices`（composition_root.dart
// 头注释为裁决原文）。本构造器自此只保留注入参数（required）：实例由
// 组合根装配或测试显式传入，门面自身不再隐式 new 缺省实现。

import 'package:flutter/foundation.dart';

import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/core/storage/tag_store.dart';
import 'package:drawing_notes_app/features/all_docs/infrastructure/favorite_store.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc_store.dart';
import 'package:drawing_notes_app/features/notes/application/sync_controller.dart';

/// 应用级服务门面。
class AppServices {
  AppServices({
    required this.blockDocStore,
    required this.favoriteStore,
    required this.tagStore,
    required this.syncController,
    required this.mediaCrypto,
  });

  /// 块文档存储（打字笔记）。
  final NoteBlockDocStore blockDocStore;

  /// 收藏存储。
  final FavoriteStore favoriteStore;

  /// 标签注册表。
  final TagStore tagStore;

  /// WebDAV 同步控制器（C-05，审计 2026-09-27：同步装配收口 application
  /// 层，设置页经组合根注入，不再自行 new 基础设施）。
  final SyncController syncController;

  /// 媒体会话加密服务（C-06，审计 2026-09-27）：组合根持有解锁生命周期
  /// 作用域的同一单例并向下传线——页面与 shared 渲染管线不再直取
  /// `.instance`（test/security_static_access_gate_test.dart 门禁锁死）。
  final MediaCryptoService mediaCrypto;

  /// 数据版本通知器：任何文档写盘后自增，驱动首页/AllDocs 刷新。
  final ValueNotifier<int> dataVersion = ValueNotifier(0);

  List<NoteBlockDoc>? _blockDocsCache;

  /// [dispose] 已执行——写回调（存储层 onWrite）在此之后仍需静默丢弃。
  bool _disposed = false;

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
    if (_disposed) return;
    dataVersion.value++;
  }

  /// 释放通知器（AppShell dispose 时调用——本方法此前无调用点，P2 修复）。
  /// 幂等：存储层的 onWrite 仍指向 [bumpDataVersion]，释放后的迟到写回调
  /// 静默丢弃（而不是抛「used after being disposed」）。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    dataVersion.dispose();
  }
}
