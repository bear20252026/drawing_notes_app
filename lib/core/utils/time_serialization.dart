// ============================================================================
// time_serialization.dart —— 持久化时间戳归一化（UTC 兼容迁移 / G15 2026-09-07）
// ============================================================================
//
// 背景：持久化层此前把 `DateTime.now().toIso8601String()` 直接落盘——本地
// DateTime 的 ISO 串**不含时区偏移**。跨时区换机/换区后，同一串被读成当前
// 本地钟面时间，等价的 LWW（last-write-wins）比较在不同的时区语义下产生
// 时差扭曲（审计 G15）。
//
// 策略（两阶段收敛，不强制重写存量）：
//   - **写侧统一 UTC**：[timeToIso] 先 `toUtc()` 再序列化，永远带 `Z` 后缀。
//     新写入的文件跨时区读数恒定。
//   - **读侧双格式兼容**：[timeFromIso] 同时吃带 `Z` / 带偏移 / 历史无偏移
//     三种字符串。归一为**设备本地** DateTime（对展示层零行为变化：
//     `format*` 工具与历史一致读本地字段）；比较仍按绝对时刻进行，
//     LWW/epoch 裁决不受 local/utc 表示影响。
//
// 边界：仅服务**持久化层**的 DateTime 序列化。展示层格式化仍用
// lib/shared/utils/time_format.dart；基于 epoch 毫秒的同步元数据（int）
// 本身时区无关，不在此列。
//
// 注意：存量无偏移字符串没有任何时区标注，只能按「当前本地时区」解读，
// 无法重建写入时的真实时区——这是唯一可行的启发，且对已写好文件
// **不做重写**（等下次保存随 UTC 串自然覆盖）。

/// 写侧序列化：统一为 UTC ISO8601（始终带 `Z` 后缀）。
String timeToIso(DateTime t) => t.toUtc().toIso8601String();

/// 读侧反序列化：兼容带 `Z` / 带偏移 / 无偏移三种 ISO 串，归一为设备本地。
///
/// - `Z` 或带偏移 → 解析为准确时刻后转换到本地钟面（展示层读数正确）。
/// - 历史无偏移 → `DateTime.parse` 按本地解读，`.toLocal()` 为幂等，保持旧行为。
/// - 无法解析 / 传入非字符串 → 返回 [fallback]（默认 `DateTime.now()`）。
DateTime timeFromIso(Object? source, {DateTime? fallback}) {
  final parsed = source is String ? DateTime.tryParse(source) : null;
  return parsed?.toLocal() ?? fallback ?? DateTime.now();
}

/// 读侧反序列化的**严格**变体：无法解析 / 非字符串时返回 `null`（不落回退值）。
///
/// 用于需要区分「时间缺失/非法」的防御性入口（如附件 `tryParse` 对毒数据的
/// 隔离）——保留原先 `DateTime.tryParse` 的 null 语义，同时复用 UTC/无偏移
/// 归一化逻辑。
DateTime? timeFromIsoOrNull(Object? source) {
  final parsed = source is String ? DateTime.tryParse(source) : null;
  return parsed?.toLocal();
}
