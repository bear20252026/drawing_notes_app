// A3-2 甲方案的配套：用户对「云端已删、本机仍留着」选「仍要上传」之后的豁免记录。
//
// 为什么需要一个显式的持久化状态，而不是「把 updatedAt 改一下让它变新」：
// 后者是在伪造文档元数据——那一版并没有真的更晚被编辑过，而 `updatedAt` 是我们
// 整套同步判据（LWW、冲突、墓碑因果锚）的输入。为了绕过一条判据去改判据本身，
// 是拿数据的可信度换一个按钮。
//
// 落点在**数据根之外**（与 `sync_state.json` 同目录），理由和 DN-204 那条一致：
// 恢复一个旧数据根之后，本机手里的内容可能就是当初被删前的那份，这时用户应当
// **重新决定**要不要覆盖云端，而不是继承上一次会话留下的豁免——那会让一次恢复
// 悄悄把云端改回旧版。

/// [SyncPushWaiverStore] 的读写契约（两条，够简单到不必抽象出更多）。
abstract class SyncPushWaiverStore {
  /// 当前被豁免的文档 id 集合。读不出（不存在 / 损坏）一律按**空集**处理——
  /// 空集的后果是「继续按住」，是可逆的保守方向；反过来把损坏读成全豁免，
  /// 就等于悄悄恢复了云端已删的内容。
  Future<Set<String>> load();

  /// 整份覆盖写入（集合很小，不做增量）。
  Future<void> save(Set<String> ids);
}

/// 内存实现（测试与未装配时的安全兜底）。
class MemoryPushWaiverStore implements SyncPushWaiverStore {
  MemoryPushWaiverStore([Set<String>? initial]) : _ids = {...?initial};

  final Set<String> _ids;

  @override
  Future<Set<String>> load() async => {..._ids};

  @override
  Future<void> save(Set<String> ids) async {
    _ids
      ..clear()
      ..addAll(ids);
  }
}
