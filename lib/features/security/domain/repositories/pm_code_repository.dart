/// PM码仓储接口 — 零外部依赖。
///
/// 定义 PM码 持久化的抽象契约，由 infrastructure 层实现。
library;

import '../entities/pm_code_state.dart';

/// PM码仓储抽象接口。
abstract class PmCodeRepository {
  /// 读取 PM码 配置状态。
  Future<PmCodeState> getState();

  /// 保存 Slot B 元数据（PM码 配置）。
  ///
  /// [slotBMetaJson] — Slot B 的 JSON 元数据（含盐、指纹、版本）。
  Future<void> saveSlotB(String slotBMetaJson);

  /// 读取 Slot B 元数据。
  Future<String?> getSlotB();

  /// 删除 Slot B 元数据（关闭 PM码）。
  Future<void> deleteSlotB();

  /// 覆写 Slot A 元数据（销毁真实密钥）。
  ///
  /// [destroyPayload] — 销毁操作的 JSON 载荷。
  Future<void> overwriteSlotA(String destroyPayload);

  /// 读取 Slot A 元数据。
  Future<String?> getSlotA();

  /// 强制刷盘（fsync 语义）。
  Future<void> fsync();
}
