/// 工程文件迁移框架（内核 P1-DOC-001，2026-10-10）。
///
/// 背景：`DocumentCodec` 早有**版本门**（高版本拒绝打开）与**防御性宽容
/// 解码**（旧文件缺键走默认值），但没有形式化的迁移管线——版本演化语义
/// 散落在解码器的 `?? default` 里，三次格式变更后就会不可维护（专家审计
/// DOC-001）。本框架把「旧版本数据 → 当前版本数据」的变换显式化：
/// - 迁移 = 一步 `from → to` 的**原地变换**（只补齐/重排，绝不删除用户数据）；
/// - Runner 按 `from` 链式应用；缺失环节的文件保持原样交给宽容解码器
///   （沿用既有兜底，不在迁移层引入新的拒绝路径）；
/// - 高版本拒绝逻辑保持在 Runner **之前**（未来版本无法向后迁移）。
///
/// 铁律（对齐项目「严禁静默丢数据」）：迁移变换必须逐条配测试钉住；
/// 新增版本 = 注册新的 [DocumentMigration] 条目 + 单测，不改 Runner。
library;

/// 一次 `from → to` 版本迁移：对解码后的文件信封（`{version, document}`）
/// 做**原地**规范化变换。实现不得抛出异常以外的方式失败，也不得丢弃字段。
abstract class DocumentMigration {
  const DocumentMigration();

  int get from;
  int get to;

  void migrate(Map<String, dynamic> envelope);
}

/// Runner：把信封从其声明的版本逐级推进到 [supportedVersion]。
///
/// - 版本缺失视为 1（最早格式，与解码器既有口径一致）；
/// - 无对应迁移环节时**原地中断**（返回已到达版本），交由解码器的宽容
///   默认兜底——迁移层绝不新增拒绝路径；
/// - 每推进一级即回写 `version`，重复调用幂等。
final class DocumentMigrationRunner {
  const DocumentMigrationRunner({
    required this.supportedVersion,
    required this.migrations,
  });

  final int supportedVersion;
  final List<DocumentMigration> migrations;

  /// 返回迁移后到达的版本（≤ [supportedVersion]）。
  int migrateToCurrent(Map<String, dynamic> envelope) {
    var version = _readVersion(envelope);
    while (version < supportedVersion) {
      DocumentMigration? step;
      for (final m in migrations) {
        if (m.from == version) {
          step = m;
          break;
        }
      }
      if (step == null) break; // 缺环节：交给宽容解码器兜底。
      step.migrate(envelope);
      version = step.to;
      envelope['version'] = version;
    }
    return version;
  }

  static int _readVersion(Map<String, dynamic> envelope) {
    final v = envelope['version'];
    return v is num ? v.toInt() : 1;
  }
}
