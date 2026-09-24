part of 'doc_page.dart';

// 文档密码域（O1 拆分自 doc_page.dart）：设密/改密/绑盘/除密四流与
// 密码输入收集（与 home_page_password 拆分同原则）。行为零变化。

/// 文档密码四流域私有助手（拆分自 doc_page.dart）。
extension _DocPagePassword on _DocPageState {

  // ── N2：文件密码管理（与画布/分页画布同口径；入口在 ⋯ 菜单） ──

  /// 笔记密码操作 sheet：未设密 → 设置；已设密 → 修改 / 绑定重置盘 / 移除。
  Future<void> _showPasswordSheet() async {
    final store = widget.blockDocStore;
    if (store == null) return;
    final protected = await store.isBlockDocPasswordProtected(_doc.id);
    final usbBound = protected && await store.hasBlockDocUsbSlot(_doc.id);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final name = _docName(_doc);
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
                l10n?.docStandalonePasswordTitle(name) ?? '「$name」独立密码',
              ),
              subtitle: Text(
                protected
                    ? (l10n?.docStandalonePasswordProtected ?? '此笔记受独立密码保护')
                    : (l10n?.docStandalonePasswordUnset ?? '此笔记当前未设置独立密码'),
              ),
            ),
            const Divider(height: 1),
            if (!protected)
              ListTile(
                leading: const Icon(Icons.add_moderator_outlined),
                title: Text(l10n?.docSetStandalonePassword ?? '设置独立密码'),
                subtitle: Text(
                  l10n?.docSetStandalonePasswordHint ?? '4–12 位数字，须与开屏密码不同',
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _startSetPassword();
                },
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.key_rounded),
                title: Text(l10n?.docChangeStandalonePassword ?? '修改独立密码'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _startChangePassword();
                },
              ),
              if (!usbBound)
                ListTile(
                  leading: const Icon(Icons.usb_rounded),
                  title: Text(l10n?.docBindResetDisk ?? '绑定重置密码盘'),
                  subtitle: Text(
                    l10n?.docBindResetDiskHint ?? '绑定后忘记密码可插 U 盘免旧密码重置',
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _startBindUsb();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.no_encryption_outlined),
                title: Text(l10n?.docRemoveStandalonePassword ?? '移除独立密码'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _startRemovePassword();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }


  /// 独立密码收集（两次一致才生效）；与开屏密码同码直接拒绝。
  Future<String?> _collectNewPassword(String title) async {
    final l10n = AppLocalizations.of(context);
    final pin = await UnlockFlow.show(context, title: title, flexible: true);
    if (pin == null || !mounted) return null;
    // ≠开屏密码强制（哈希加盐不可比对，用 verify 探测）。
    if (await AppLockService.matchesAppLockPin(pin)) {
      _snack(l10n?.docPinSameAsLock ?? '独立密码不能与开屏密码相同');
      return null;
    }
    if (!mounted) return null; // matchesAppLockPin 为异步操作，跨缺口守卫
    final confirm = await UnlockFlow.show(
      context,
      title: l10n?.docConfirmStandalonePassword ?? '确认独立密码',
      flexible: true,
    );
    if (confirm == null) return null;
    if (confirm != pin) {
      _snack(l10n?.docPinMismatch ?? '两次输入不一致，请重试');
      return null;
    }
    return pin;
  }


  Future<void> _startSetPassword() async {
    final store = widget.blockDocStore;
    if (store == null) return;
    final l10n = AppLocalizations.of(context);
    final pin = await _collectNewPassword(
      l10n?.docSetStandalonePassword ?? '设置独立密码',
    );
    if (pin == null) return;
    if (!mounted) return;
    // 可选当场绑定重置密码盘（错过本次可事后在密码管理中绑定）。
    List<int>? resetDiskKey;
    final bindUsb = await GlassDialog.confirm(
      context,
      title: l10n?.docBindDiskConfirmTitle ?? '绑定重置密码盘？',
      content:
          l10n?.docBindDiskConfirmContent ??
          '绑定后忘记此笔记的独立密码时，可插入重置密码盘（U 盘）免旧密码重置。\n\n'
              'U 盘上只有随机钥匙文件（password_reset_disk.key），笔记数据不会离开设备。',
      confirmText: l10n?.docBindDiskConfirm ?? '插盘绑定',
      cancelText: l10n?.docNotNow ?? '暂不',
    );
    if (bindUsb == true) {
      if (!mounted) return;
      final dir = await ResetDiskFile.pickDirectory();
      if (dir != null) {
        resetDiskKey = await ResetDiskFile.readFrom(dir);
        if (resetDiskKey == null && mounted) {
          _snack(
            l10n?.docDiskNotFoundNoBind ??
                '未找到有效的重置密码盘文件（password_reset_disk.key），本次不绑定',
          );
        }
      }
    }
    try {
      await store.encryptAndSave(_doc, pin, usbKey: resetDiskKey);
      _snack(
        resetDiskKey == null
            ? (l10n?.docPasswordSetFor(_docName(_doc)) ??
                  '已为「${_doc.title.isEmpty ? '未命名' : _doc.title}」设置独立密码')
            : (l10n?.docPasswordSetDiskBound ?? '已设置独立密码并绑定重置密码盘'),
      );
    } on StateError catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(l10n?.docSetFailed ?? '设置失败，请重试');
    }
  }


  Future<void> _startChangePassword() async {
    final store = widget.blockDocStore;
    if (store == null) return;
    final l10n = AppLocalizations.of(context);
    final old = await UnlockFlow.show(
      context,
      title: l10n?.docVerifyCurrent ?? '验证当前独立密码',
      flexible: true,
      onVerify: (p) => store.verifyBlockDocPassword(_doc.id, p),
    );
    if (old == null || !mounted) return;
    final pin = await _collectNewPassword(l10n?.docSetNewPassword ?? '设置新密码');
    if (pin == null) return;
    try {
      await store.changeBlockDocPassword(_doc.id, old, pin);
      _snack(
        l10n?.docPasswordChangedFor(_docName(_doc)) ??
            '已修改「${_doc.title.isEmpty ? '未命名' : _doc.title}」的独立密码',
      );
    } on FormatException {
      _snack(l10n?.docWrongPassword ?? '原密码不正确或密文已损坏');
    } on StateError catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(l10n?.docChangeFailed ?? '修改失败，请重试');
    }
  }


  /// 事后绑定重置密码盘：验证文件密码 → 插盘 → 嵌入 USB 槽位。
  Future<void> _startBindUsb() async {
    final store = widget.blockDocStore;
    if (store == null) return;
    final l10n = AppLocalizations.of(context);
    final pin = await UnlockFlow.show(
      context,
      title: l10n?.docVerifyToBind ?? '验证独立密码以绑定重置盘',
      flexible: true,
      onVerify: (p) => store.verifyBlockDocPassword(_doc.id, p),
    );
    if (pin == null || !mounted) return;
    final dir = await ResetDiskFile.pickDirectory();
    if (dir == null || !mounted) return;
    final usbKey = await ResetDiskFile.readFrom(dir);
    if (usbKey == null) {
      _snack(l10n?.docDiskNotFound ?? '未找到有效的重置密码盘文件（password_reset_disk.key）');
      return;
    }
    try {
      await store.bindBlockDocUsbSlot(_doc.id, pin, usbKey);
      _snack(l10n?.docDiskBound ?? '已绑定重置密码盘');
    } on FormatException {
      _snack(l10n?.docWrongOrAlreadyBound ?? '密码不正确或已绑定重置密码盘');
    } on StateError catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(l10n?.docBindFailed ?? '绑定失败，请重试');
    }
  }


  Future<void> _startRemovePassword() async {
    final store = widget.blockDocStore;
    if (store == null) return;
    final l10n = AppLocalizations.of(context);
    final name = _docName(_doc);
    final ok = await GlassDialog.confirm(
      context,
      title: l10n?.docRemoveStandalonePassword ?? '移除独立密码',
      content:
          l10n?.docRemoveConfirmContent(name) ??
          '移除后「$name」不再需要独立密码即可打开。确定移除吗？',
      confirmText: l10n?.docRemove ?? '移除',
      dangerous: true,
    );
    if (ok != true) return;
    if (!mounted) return;
    final pin = await UnlockFlow.show(
      context,
      title: l10n?.docVerifyToRemove ?? '验证独立密码以移除',
      flexible: true,
      onVerify: (p) => store.verifyBlockDocPassword(_doc.id, p),
    );
    if (pin == null) return;
    try {
      await store.removeBlockDocPassword(_doc.id, pin);
      _snack(l10n?.docPasswordRemovedFor(name) ?? '已移除「$name」的独立密码');
    } on FormatException {
      _snack(l10n?.docPasswordWrongOrCorrupt ?? '密码不正确或密文已损坏');
    } on StateError catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack(l10n?.docRemoveFailed ?? '移除失败，请重试');
    }
  }
}
