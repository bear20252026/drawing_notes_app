part of 'home_page.dart';

/// 单文件密码与画布删除（F1：自 home_page.dart 拆出，行为零变化）。
extension _HomePagePasswordOps on _HomePageState {
  // ---------------- 单文件密码管理（批次②） ----------------

  /// 画布密码操作 sheet：未设密 → 设置；已设密 → 修改 / 绑定重置盘 / 移除。
  Future<void> _showDrawingPasswordSheet(DocumentMeta meta) async {
    final protected = await _docStorage.isFilePasswordProtected(meta.id);
    final usbBound = protected && await _docStorage.hasFileUsbSlot(meta.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.lock_outline_rounded),
              title: Text(
                _l10nSafe?.docStandalonePasswordTitle(meta.title) ??
                    '「${meta.title}」独立密码',
              ),
              subtitle: Text(
                protected
                    ? _l10nSafe?.canvasStandalonePasswordProtected ??
                          '此画布受独立密码保护'
                    : _l10nSafe?.canvasStandalonePasswordUnset ??
                          '此画布当前未设置独立密码',
              ),
            ),
            const Divider(height: 1),
            if (!protected)
              ListTile(
                leading: const Icon(Icons.add_moderator_outlined),
                title: Text(
                  AppLocalizations.of(sheetContext)?.docSetStandalonePassword ??
                      '设置独立密码',
                ),
                subtitle: Text(
                  AppLocalizations.of(
                        sheetContext,
                      )?.docSetStandalonePasswordHint ??
                      '4–12 位数字，须与开屏密码不同',
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _startSetFilePassword(meta);
                },
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.key_rounded),
                title: Text(
                  AppLocalizations.of(
                        sheetContext,
                      )?.docChangeStandalonePassword ??
                      '修改独立密码',
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _startChangeFilePassword(meta);
                },
              ),
              if (!usbBound)
                ListTile(
                  leading: const Icon(Icons.usb_rounded),
                  title: Text(
                    AppLocalizations.of(sheetContext)?.docBindResetDisk ??
                        '绑定重置密码盘',
                  ),
                  subtitle: Text(
                    AppLocalizations.of(sheetContext)?.docBindResetDiskHint ??
                        '绑定后忘记密码可插 U 盘免旧密码重置',
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _startBindFileUsb(meta);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.no_encryption_outlined),
                title: Text(
                  AppLocalizations.of(
                        sheetContext,
                      )?.docRemoveStandalonePassword ??
                      '移除独立密码',
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _startRemoveFilePassword(meta);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 独立密码收集（两次一致才生效）；与开屏密码同码直接拒绝。
  Future<String?> _collectNewFilePassword(String title) async {
    final pin = await UnlockFlow.show(context, title: title, flexible: true);
    if (pin == null || !mounted) return null;
    // ≠开屏密码强制（哈希加盐不可比对，用 verify 探测）。
    if (await AppLockService.matchesAppLockPin(pin)) {
      _showSnack(_l10nSafe?.docPinSameAsLock ?? '独立密码不能与开屏密码相同');
      return null;
    }
    if (!mounted) return null; // matchesAppLockPin 为异步操作，跨缺口守卫
    final confirm = await UnlockFlow.show(
      context,
      title: _l10nSafe?.docConfirmStandalonePassword ?? '确认独立密码',
      flexible: true,
    );
    if (confirm == null) return null;
    if (confirm != pin) {
      _showSnack(_l10nSafe?.docPinMismatch ?? '两次输入不一致，请重试');
      return null;
    }
    return pin;
  }

  Future<void> _startSetFilePassword(DocumentMeta meta) async {
    final pin = await _collectNewFilePassword(
      _l10nSafe?.docSetStandalonePassword ?? '设置独立密码',
    );
    if (pin == null) return;
    if (!mounted) return;
    // N4 批 2：可选当场绑定重置密码盘（错过本次可事后在密码管理中绑定）。
    List<int>? resetDiskKey;
    final bindUsb = await GlassDialog.confirm(
      context,
      title: _l10nSafe?.docBindDiskConfirmTitle ?? '绑定重置密码盘？',
      content:
          _l10nSafe?.canvasBindConfirmContent ??
          '绑定后忘记此画布的独立密码时，可插入重置密码盘（U 盘）免旧密码重置。\n\n'
              'U 盘上只有随机钥匙文件（password_reset_disk.key），画布数据不会离开设备。',
      confirmText: _l10nSafe?.docBindDiskConfirm ?? '插盘绑定',
      cancelText: _l10nSafe?.docNotNow ?? '暂不',
    );
    if (bindUsb == true) {
      if (!mounted) return;
      final dir = await ResetDiskFile.pickDirectory();
      if (dir != null) {
        resetDiskKey = await ResetDiskFile.readFrom(dir);
        if (resetDiskKey == null && mounted) {
          _showSnack(
            _l10nSafe?.docDiskNotFoundNoBind ??
                '未找到有效的重置密码盘文件（password_reset_disk.key），本次不绑定',
          );
        }
      }
    }
    try {
      await _docStorage.setFilePassword(
        meta.id,
        pin,
        resetDiskKey: resetDiskKey,
      );
      final setMsg = resetDiskKey == null
          ? _l10nSafe?.docPasswordSetFor(meta.title) ??
                '已为「${meta.title}」设置独立密码'
          : _l10nSafe?.canvasPasswordSetDiskBoundFor(meta.title) ??
                '已为「${meta.title}」设置独立密码并绑定重置密码盘';
      _showSnack(setMsg);
      await _refresh();
    } on VaultFileLockException {
      _showSnack(_l10nSafe?.canvasVaultLockedSet ?? '加密底座已锁定：请重新验证开屏密码后再设置');
    } catch (e) {
      _showSnack(_l10nSafe?.docSetFailed ?? '设置失败，请重试');
    }
  }

  Future<void> _startChangeFilePassword(DocumentMeta meta) async {
    final old = await UnlockFlow.show(
      context,
      title: _l10nSafe?.docVerifyCurrent ?? '验证当前独立密码',
      flexible: true,
      onVerify: (p) => _docStorage.verifyFilePassword(meta.id, p),
    );
    if (old == null || !mounted) return;
    final pin = await _collectNewFilePassword(
      _l10nSafe?.docSetNewPassword ?? '设置新密码',
    );
    if (pin == null) return;
    try {
      await _docStorage.changeFilePassword(meta.id, old, pin);
      _showSnack(
        _l10nSafe?.docPasswordChangedFor(meta.title) ??
            '已修改「${meta.title}」的独立密码',
      );
      await _refresh();
    } on VaultFileException {
      _showSnack(_l10nSafe?.docWrongPassword ?? '原密码不正确或密文已损坏');
    } catch (e) {
      _showSnack(_l10nSafe?.docChangeFailed ?? '修改失败，请重试');
    }
  }

  /// 事后绑定重置密码盘（N4 批 2）：验证文件密码 → 插盘 → 嵌入 USB 槽位。
  Future<void> _startBindFileUsb(DocumentMeta meta) async {
    final pin = await UnlockFlow.show(
      context,
      title: _l10nSafe?.docVerifyToBind ?? '验证独立密码以绑定重置盘',
      flexible: true,
      onVerify: (p) => _docStorage.verifyFilePassword(meta.id, p),
    );
    if (pin == null || !mounted) return;
    final dir = await ResetDiskFile.pickDirectory();
    if (dir == null || !mounted) return;
    final usbKey = await ResetDiskFile.readFrom(dir);
    if (usbKey == null) {
      _showSnack(
        _l10nSafe?.lockNoResetDisk ??
            '未找到有效的重置密码盘文件（password_reset_disk.key）',
      );
      return;
    }
    try {
      await _docStorage.bindFileUsbSlot(meta.id, pin, usbKey);
      _showSnack(
        _l10nSafe?.canvasBoundDiskFor(meta.title) ?? '已为「${meta.title}」绑定重置密码盘',
      );
      await _refresh();
    } on StateError catch (e) {
      _showSnack(e.message);
    } on VaultFileException {
      _showSnack(_l10nSafe?.docPasswordWrongOrCorrupt ?? '密码不正确或密文已损坏');
    } catch (e) {
      _showSnack(_l10nSafe?.docBindFailed ?? '绑定失败，请重试');
    }
  }

  Future<void> _startRemoveFilePassword(DocumentMeta meta) async {
    final ok = await _confirmDelete(
      _l10nSafe?.docRemoveStandalonePassword ?? '移除独立密码',
      _l10nSafe?.canvasRemoveConfirmContent(meta.title) ??
          '移除后「${meta.title}」将回到加密底座保护（主密钥信封），不再需要独立密码。确定移除吗？',
    );
    if (ok != true) return;
    if (!mounted) return; // _confirmDelete 为异步操作，跨缺口守卫
    final pin = await UnlockFlow.show(
      context,
      title: _l10nSafe?.docVerifyToRemove ?? '验证独立密码以移除',
      flexible: true,
      onVerify: (p) => _docStorage.verifyFilePassword(meta.id, p),
    );
    if (pin == null) return;
    try {
      await _docStorage.removeFilePassword(meta.id, pin);
      _showSnack(
        _l10nSafe?.docPasswordRemovedFor(meta.title) ??
            '已移除「${meta.title}」的独立密码',
      );
      await _refresh();
    } on VaultFileLockException {
      // fail-closed：绝不回明文。
      _showSnack(
        _l10nSafe?.canvasVaultLockedRemove ?? '加密底座已锁定，无法回封：请重新验证开屏密码后再试',
      );
    } on VaultFileException {
      _showSnack(_l10nSafe?.docPasswordWrongOrCorrupt ?? '密码不正确或密文已损坏');
    } catch (e) {
      _showSnack(_l10nSafe?.docRemoveFailed ?? '移除失败，请重试');
    }
  }

  /// 删除画作（二次确认）。
  Future<void> _deleteDrawing(DocumentMeta meta) async {
    final ok = await _confirmDelete(
      _l10nSafe?.homeDeleteCanvasTitle ?? '删除画布',
      _l10nSafe?.homeDeleteCanvasConfirm(meta.title) ??
          '确定删除画布「${meta.title}」吗？此操作不可恢复。',
    );
    if (ok != true) return;
    try {
      await _docStorage.delete(meta.id);
      await _refresh();
    } catch (e) {
      _showSnack(_l10nSafe?.homeDeleteFailed ?? '删除失败，请重试');
    }
  }

}
