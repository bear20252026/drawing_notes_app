import 'package:drawing_notes_app/core/documents/migration/document_migration.dart';
import 'package:drawing_notes_app/core/storage/local_id_generator.dart';

/// 工程文件迁移注册表（内核 P1-DOC-001，2026-10-10）。
///
/// 当前唯一条目 v1→v2：把 v1 时代的「解码器内兼容默认」显式化为数据变换。
/// v1→v2 的实际差异（AW2 修复 2026-10-05，commit 2015663）：
/// - v1 笔画缺 `seed` / `version` / `versionNonce`（旧解码器丢弃导致重开
///   抖动/质感变化、冲突检测失效）；
/// - v1 文档缺 `textItems`（打字内容保存重开消失）。
///
/// 变换语义：**补齐缺键为文档化默认值**，已存在的键一律不动（用户数据
/// 绝不重写）。补齐是幂等规范化——解码器仍保留宽容默认（双保险），文件
/// 自此自描述其版本。注意 seed **刻意不补**：v1 文件从未携带 seed，补任何
/// 确定值都会让全部笔画共享同一抖动纹理；留空维持「每次打开派生新种子」
/// 的 v1 历史行为（AW2 修复只保证 v2+ 文件不再丢 seed）。
final class MigrationV1ToV2 extends DocumentMigration {
  const MigrationV1ToV2();

  @override
  int get from => 1;

  @override
  int get to => 2;

  @override
  void migrate(Map<String, dynamic> envelope) {
    final document = envelope['document'];
    if (document is! Map) return;
    final doc = Map<String, dynamic>.from(document);

    // v1 文档缺 textItems：补空列表（解码器同款默认）。
    doc['textItems'] ??= <Map<String, dynamic>>[];

    final layers = doc['layers'];
    if (layers is List) {
      for (final layer in layers) {
        if (layer is! Map) continue;
        final strokes = layer['strokes'];
        if (strokes is! List) continue;
        for (final stroke in strokes) {
          if (stroke is! Map) continue;
          stroke['version'] ??= 0; // v1 笔画早于版本化 → 0
          stroke['versionNonce'] ??= 0;
        }
      }
    }
    envelope['document'] = doc;
  }
}

/// v2→v3：为缺 id 的笔画补持久唯一 id（格式 v3，2026-10-11）。
///
/// v2 及更早的笔画无身份字段（操作记录/增量同步只能按会话内对象引用寻址）。
/// 迁移按 `LocalIdGenerator` 逐条派生——**一次性定格**：id 写回文件后跨会话
/// 稳定，这正是它与「解码器缺省派生」的区别（后者每次打开都会换新 id）。
final class MigrationV2ToV3 extends DocumentMigration {
  const MigrationV2ToV3();

  @override
  int get from => 2;

  @override
  int get to => 3;

  @override
  void migrate(Map<String, dynamic> envelope) {
    final document = envelope['document'];
    if (document is! Map) return;
    final layers = document['layers'];
    if (layers is! List) return;
    for (final layer in layers) {
      if (layer is! Map) continue;
      final strokes = layer['strokes'];
      if (strokes is! List) continue;
      for (final stroke in strokes) {
        if (stroke is! Map) continue;
        if (stroke['id'] is String && (stroke['id'] as String).isNotEmpty) {
          continue; // 已有 id（同版本重放/部分升级）——绝不重写。
        }
        stroke['id'] = LocalIdGenerator.next('str');
      }
    }
  }
}

/// v3→v4：把「靠布尔值猜」的线型与填充样式定格成显式键（格式 v4，2026-10-12）。
///
/// v4 新增两个**可选**形状键：`strokeStyle`（solid/dashed/dotted）与
/// `fillStyle`（solid/hachure/crossHatch）。`dash`/`rough`/`fillColor` 全部保留并继续写，
/// 所以旧版本读到 v4 文件时形状仍能画——只是会丢掉 dotted/crossHatch 这两档。
/// 正因如此必须升版本号：留在 v3 就是「旧版本静默降级」，本仓明令禁止。
///
/// 迁移只清一件事：**非法取值的样式键**（解码层本来也会丢弃，留在文件里会让
/// 「同一份内容编码两次」不幂等）。非法值判据用常量表，避免与模型漂移。
///
/// **刻意不补默认值**——这是本步最要紧的一条：一旦把缺键按 `dash`/`rough` 定格成
/// 显式值，显式值就永久压过这两个布尔，桌面端工具条的「虚线/手绘」开关会变成点了没反应，
/// 每个被打开过的旧文件也会无谓地长出新键。写盘侧同理：只有**偏离旧推导**的取值才落键
/// （见 `PageShapeItem.toJson`），所以 v3 文件语义本来就完整，v4 只是取得了一个环节。
final class MigrationV3ToV4 extends DocumentMigration {
  const MigrationV3ToV4();

  static const List<String> _strokeStyles = ['solid', 'dashed', 'dotted'];
  static const List<String> _fillStyles = ['solid', 'hachure', 'crossHatch'];

  @override
  int get from => 3;

  @override
  int get to => 4;

  @override
  void migrate(Map<String, dynamic> envelope) {
    final document = envelope['document'];
    if (document is! Map) return;
    final shapes = document['shapes'];
    if (shapes is! List) return;
    for (final shape in shapes) {
      if (shape is! Map) continue;
      final stroke = shape['strokeStyle'];
      if (stroke != null && !_strokeStyles.contains(stroke)) {
        shape.remove('strokeStyle');
      }
      final fill = shape['fillStyle'];
      if (fill != null && !_fillStyles.contains(fill)) {
        shape.remove('fillStyle');
      }
    }
  }
}

/// 当前支持版本的迁移注册表（顺序即推进链）。
const List<DocumentMigration> kDocumentMigrations = [
  MigrationV1ToV2(),
  MigrationV2ToV3(),
  MigrationV3ToV4(),
];

/// 当前支持版本。**刻意不 import DocumentCodec**（codec 反向 import 本注册表
/// 做迁移接线——引回即循环依赖，架构测试规则 2 实际拦截过）。与
/// `DocumentCodec.latestVersion` 的一致性由 document_migration_test 钉住。
const int kSupportedDocumentVersion = 4;

const DocumentMigrationRunner kDocumentMigrationRunner =
    DocumentMigrationRunner(
      supportedVersion: kSupportedDocumentVersion,
      migrations: kDocumentMigrations,
    );
