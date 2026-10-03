// lib/app/composition_root.dart（专家第一周更正期 V-002/V-003）。
//
// 组合根：V2 依赖的**唯一组装点**——创建 GeometryEngine 唯一实例 +
// notebook_domain ports 的 adapter 注册位。遵守专家约束：不创建 Widget /
// 不读取 File / 不持有用户明文密钥 / 不直接调用旧 DrawingController。
//
// C-07（审计 2026-09-27）装配机制统一裁决——审计实测装配分裂为四套机制
// （可空 static 端口 / AppShell 手工 new / Riverpod / drawing 私有
// provider），本裁决收敛为「组合根单例 + Riverpod 作用域」两轨明文备案：
// - **组合根（本文件）= 服务单例装配的唯一落点**：AppServices 的缺省
//   装配体（store / sync / mediaCrypto 实例创建）收进
//   [CompositionRoot.createAppServices]；AppShell / app.dart 只消费与
//   透传注入，不再自带装配知识（AppShell 手工 new 就此清零）。
// - **Riverpod = 页面/文档级作用域状态**（features/drawing/application/
//   di_providers.dart 的 drawingControllerProvider 等，随页面生命周期
//   创建销毁）：那是状态作用域机制，不属服务装配，不进组合根。
// - **V2 可空 static 端口**（下方 notebookRepository / mediaRepository /
//   keyProvider 三处）维持 S-005「IMPLEMENTED 未接线」现状，接线工作在
//   C-07 ID 下续批，不在其他位置私自 new adapter。
import 'package:editor_core/editor_core.dart';
import 'package:notebook_domain/notebook_domain.dart';

import 'package:drawing_notes_app/app/app_services.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc_store.dart';
import 'package:drawing_notes_app/core/security/media_crypto_service.dart';
import 'package:drawing_notes_app/core/storage/tag_store.dart';
import 'package:drawing_notes_app/features/all_docs/infrastructure/favorite_store.dart';
import 'package:drawing_notes_app/features/notes/application/sync_controller.dart';

/// V2 组合根（composition root——V2 依赖单一事实源组装点）。
class CompositionRoot {
  CompositionRoot._();

  /// GeometryEngine 唯一实例（专家 V-002——UI/核心 renderer/导出器
  /// 调用同一引擎——单一可信来源——不重复实现几何）。
  static const GeometryEngine geometryEngine = GeometryEngine();

  /// notebook_domain ports 注册位（V-003——adapter 由 infrastructure 实现：
  /// EncryptedNotebookRepositoryV2 / MediaRepositoryV2 / 平台 KeyStore——
  /// 后续批次 D 接入——当前保持未接线（S-005 IMPLEMENTED 标注）。
  /// C-07：接线前维持可空 static 端口现状，接线在 C-07 ID 下续批。
  static NotebookRepositoryPort? notebookRepository;
  static MediaRepositoryPort? mediaRepository;
  static KeyProviderPort? keyProvider;

  /// 应用级服务门面的缺省装配（C-07，审计 2026-09-27）：服务单例装配
  /// 唯一落点收进组合根——原 AppServices 构造器初始化列表里的缺省
  /// `??` 装配体原样搬入，实例创建语义逐一等价（零行为变化）；
  /// AppServices 构造器自此只保留注入参数（测试/上游显式覆写用）。
  ///
  /// 注入参数可空：null 时由本方法创建真实实现；AppShell 透传
  /// widget 注入（app_shell_smoke_test 的内存实现路径不受影响）。
  static AppServices createAppServices({
    NoteBlockDocStore? blockDocStore,
    FavoriteStore? favoriteStore,
    TagStore? tagStore,
    SyncController? syncController,
    MediaCryptoService? mediaCrypto,
  }) =>
      AppServices(
        blockDocStore: blockDocStore ?? NoteBlockDocStore(),
        favoriteStore: favoriteStore ?? FavoriteStore(),
        tagStore: tagStore ?? TagStore(),
        syncController: syncController ?? SyncController(),
        mediaCrypto: mediaCrypto ?? MediaCryptoService.instance,
      );
}
