// SYNC-003 冲突中心在设置页的接线（`webdav_sync_settings_page.dart` 的 part）。
//
// 为什么拆 part：主页文件在本次接线后到了 1015 行，越过 linecheck 的 1000 行
// 硬上限（`linecheck.yml` 的 `**/*.dart` error 档）。它原本就已 905 行、
// 远超 500 行警告线——不是本次改动引入的退化，但本次把它推过了阻断线。
//
// 拆法沿用本仓既有先例（`doc_page.dart` 六 part、`doc_editor.dart` 八 part）：
// part 与主库共享私有成员与 import，`_ledger` / `_autoAppliedConflicts`
// 仍可被主页的 `build`/`_summaryOf` 直接读写，不需要把私有态提升成公共 API。
// 具体到写法：Dart 不允许把 class 体拆到 part 里，所以本文件用
// `extension ... on _WebDavSyncSettingsPageState` 承载方法（这正是
// `doc_page_save_export.dart` 的形状）；两个状态字段因此留在主页——
// extension 不能声明实例字段。
//
// 本文件只装「冲突台账的读写与改判」，不含任何 UI 组件——组件本体在
// `conflict_center_section.dart`（那是独立 widget 库，不是 part）。

part of 'webdav_sync_settings_page.dart';

/// SYNC-003：台账读写与改判逻辑（拆分自 `webdav_sync_settings_page.dart`）。
extension _WebDavSyncConflictWiring on _WebDavSyncSettingsPageState {
  /// SYNC-003：读一次冲突台账。读不出来（文件损坏/目录解析失败）按空处理，
  /// 不弹错——台账是事后可查性，不该在设置页一打开就弹一个红条。
  Future<void> _refreshLedger() async {
    try {
      final entries = await _sync.loadConflictLedger();
      if (!mounted) return;
      _pageSetState(() => _ledger = entries);
    } catch (_) {
      // 与文件实现的容错同口径：读不出就是读不出，页面继续可用。
    }
  }

  /// SYNC-003：设定一篇的改判（写台账 + 刷新 + 提示）。
  ///
  /// 不改本轮任何行为：方向从**下一次**同步开始生效（见台账合同）。
  Future<void> _applyOverride(
    ConflictLedgerEntry entry,
    ConflictResolution resolution,
  ) async {
    await _sync.setConflictResolutionOverride(entry.docId, resolution);
    await _refreshLedger();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    _toast(
      l10n?.conflictCenterOverrideSet(
            conflictResolutionLabel(resolution, l10n),
          ) ??
          '已记录：下次这篇冲突时按「${conflictResolutionLabel(resolution, l10n)}」处理',
    );
  }

  /// SYNC-003：清除改判（回到「下次重新问」）。可逆——再改一次就回来了，
  /// 所以不做二次确认。
  Future<void> _clearOverride(ConflictLedgerEntry entry) async {
    await _sync.setConflictResolutionOverride(entry.docId, null);
    await _refreshLedger();
    if (!mounted) return;
    _toast(
      AppLocalizations.of(context)?.conflictCenterOverrideCleared ??
          '已清除改判：下次这篇冲突时会重新问你',
    );
  }
}

// ---------------------------------------------------------------------------
// 冲突处理器
// ---------------------------------------------------------------------------

/// 冲突处理器：遇到冲突时弹窗询问用户逐条裁决；用户取消则返回空（走默认 LWW）。
class _DialogConflictHandler implements ConflictHandler {
  _DialogConflictHandler(this._state, {this.onAutoApplied});

  // 具体 State 类型而不是 `State<WebDavSyncSettingsPage>`：`_sync` 是 State 类上
  // 的私有 getter，声明成基类就看不见了。
  final _WebDavSyncSettingsPageState _state;

  /// SYNC-003：本轮有 N 条冲突是**按台账改判**自动处理的（没有弹窗问）。
  /// 不为空则报给页面写进摘要——「已按你的选择处理」在改判场景下是假的。
  final void Function(int count)? onAutoApplied;

  @override
  Future<Map<String, ConflictResolution>> resolve(
    List<SyncConflict> conflicts,
  ) async {
    if (conflicts.isEmpty || !_state.mounted) return const {};
    // SYNC-003：台账里设了改判的那些文档**不再重复问**——用户已经为它们指定过
    // 方向，每轮重新问一次只是噪声（而且它会让「改判」显得根本没生效）。
    final ledger = await _state._sync.loadConflictLedger();
    if (!_state.mounted) return const {};
    final standing = {
      for (final e in ledger)
        if (e.hasOverride) e.docId: e.resolutionOverride!,
    };
    final auto = <String, ConflictResolution>{};
    final pending = <SyncConflict>[];
    for (final c in conflicts) {
      final r = standing[c.docId];
      if (r == null) {
        pending.add(c);
      } else {
        auto[c.docId] = r;
      }
    }
    if (auto.isNotEmpty) onAutoApplied?.call(auto.length);
    if (pending.isEmpty) return auto;
    final result = await GlassDialog.show<Map<String, ConflictResolution>>(
      context: _state.context,
      barrierDismissible: false,
      builder: (_) => ConflictResolutionDialog(conflicts: pending),
    );
    return {...auto, ...?result};
  }
}
