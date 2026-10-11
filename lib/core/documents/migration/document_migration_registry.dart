import 'package:drawing_notes_app/core/documents/migration/document_migration.dart';

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

/// 当前支持版本的迁移注册表（顺序即推进链）。
const List<DocumentMigration> kDocumentMigrations = [MigrationV1ToV2()];

/// 当前支持版本。**刻意不 import DocumentCodec**（codec 反向 import 本注册表
/// 做迁移接线——引回即循环依赖，架构测试规则 2 实际拦截过）。与
/// `DocumentCodec.latestVersion` 的一致性由 document_migration_test 钉住。
const int kSupportedDocumentVersion = 2;

const DocumentMigrationRunner kDocumentMigrationRunner =
    DocumentMigrationRunner(
      supportedVersion: kSupportedDocumentVersion,
      migrations: kDocumentMigrations,
    );
