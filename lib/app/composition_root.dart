// lib/app/composition_root.dart（专家第一周更正期 V-002/V-003）。
//
// 组合根：V2 依赖的**唯一组装点**——创建 GeometryEngine 唯一实例 +
// notebook_domain ports 的 adapter 注册位。遵守专家约束：不创建 Widget /
// 不读取 File / 不持有用户明文密钥 / 不直接调用旧 DrawingController。
import 'package:editor_core/editor_core.dart';
import 'package:notebook_domain/notebook_domain.dart';

/// V2 组合根（composition root——V2 依赖单一事实源组装点）。
class CompositionRoot {
  CompositionRoot._();

  /// GeometryEngine 唯一实例（专家 V-002——UI/核心 renderer/导出器
  /// 调用同一引擎——单一可信来源——不重复实现几何）。
  static const GeometryEngine geometryEngine = GeometryEngine();

  /// notebook_domain ports 注册位（V-003——adapter 由 infrastructure 实现：
  /// EncryptedNotebookRepositoryV2 / MediaRepositoryV2 / 平台 KeyStore——
  /// 后续批次 D 接入——当前保持未接线（S-005 IMPLEMENTED 标注）。
  static NotebookRepositoryPort? notebookRepository;
  static MediaRepositoryPort? mediaRepository;
  static KeyProviderPort? keyProvider;
}
