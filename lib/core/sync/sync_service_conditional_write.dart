// 由 Claude 团队生成 | Drawing Notes App
// SyncService 的 DN-201 一侧：文档级条件写入的两个辅助步骤（HEAD 探测的降级、
// 412 被挡回后的「先保两端」处置）。同库 part——私有成员互相可见。
part of 'sync_service.dart';

/// DN-201：条件写入的辅助步骤（`SyncService` 的一部分）。
///
/// 注意 extension 的一条语言规则：引用被扩展类型的**静态**成员必须带类名限定
/// （`SyncService._safeCopyId`），这是拆分时唯一被迫写出来的差异，行为不变。
extension SyncServiceConditionalWrite on SyncService {
  /// DN-201：HEAD 探测远端版本；**探不到就按「无法条件写」返回，不抛出**。
  ///
  /// 为什么不因为一次探测失败就把这篇判成同步失败：那等于新增一个「服务器响应
  /// 形态不合我意 ⇒ 断同步」的开关，比现状（无条件写）更糟。探测失败退回既有
  /// 行为，同时把「这台服务器上防不住并发覆盖」如实上报到界面——诚实的降级
  /// 好过假装安全的降级。
  Future<WebDavPresence> _probeOrUnknown(String relativePath) async {
    try {
      return await transport.probe(relativePath);
    } catch (_) {
      return const WebDavPresence.presentUnknown();
    }
  }

  /// DN-201：条件写入被 412 挡回之后的处置——**先保两端，再上报，绝不重试覆盖**。
  ///
  /// 412 说的是一件很具体的事：远端这一篇在本机读过之后又被别的设备改过。此刻
  /// 本机手里一份、云端一份，是两份都真实存在的内容，任何一边的「顺手覆盖」都是
  /// 数据丢失。所以把云端那一版另存成本地副本（与 keepBoth 同一套 `_safeCopyId`
  /// 命名与消毒），id 记进 remoteChangedIds；连副本都没能留住时记 failedIds，
  /// 享受「清单/基线都不回写、下轮重试」的毒丸保护。
  ///
  /// 两条腿都在本轮**不写云端**——remoteChangedIds 与 failedIds 都并进
  /// `_ExecuteOutcome.notSyncedIds`，绝不出现「远端没动，本地清单却说同步过了」。
  Future<void> _handleRejectedWrite(
    String docId,
    String relativePath,
    List<String> remoteChangedIds,
    List<String> failedIds,
  ) async {
    try {
      final remoteBytes = await transport.getBytes(relativePath);
      if (remoteBytes == null) {
        // 远端对象在这一步已经消失：没有要保护的内容，本轮按未同步收工。
        if (!remoteChangedIds.contains(docId)) remoteChangedIds.add(docId);
        return;
      }
      final plain = await cipher.decryptDocumentBytes(remoteBytes, docId);
      await documentStore.writeDocument(SyncService._safeCopyId(docId), plain);
      if (!remoteChangedIds.contains(docId)) remoteChangedIds.add(docId);
    } on SyncKeyMismatchException {
      rethrow; // 确定性失败：交给外层，同时进 unreadableIds 供 UI 给可执行文案
    } catch (_) {
      if (!failedIds.contains(docId)) failedIds.add(docId);
    }
  }
}
