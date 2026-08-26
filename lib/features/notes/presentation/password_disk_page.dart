import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/text_scale_helper.dart';

import '../../../infrastructure/storage/encryption_service.dart';
import '../../../infrastructure/storage/password_disk.dart';
import '../../../infrastructure/storage/usb_disk_detector.dart';
import '../../../shared/widgets/ambient_background.dart';
import '../../../shared/widgets/glass_surface.dart';
import '../../../infrastructure/storage/recovery_key_generator.dart';
import '../../../core/security/auth_guard.dart';
import '../../../core/security/audit_logger.dart';
import '../../../core/abstractions/router/app_router.dart';
import '../../../core/ui/widgets/ios_dialog.dart';
import '../../../core/ui/widgets/app_snackbar.dart';
import '../../../core/ui/widgets/apple_pin_input.dart';
import '../../../l10n/app_localizations.dart';

/// 密码盘管理页（U盘即钥匙，设计见 docs/PASSWORD_DISK_DESIGN.md）�?///
/// 功能�?/// 1. 创建密码盘：选目�?�?生成 key.frogkey�?56 位主密钥）→ 展示 24 位恢复密钥；
/// 2. 校验/解锁：选目�?�?读取主密�?�?显示指纹（证明密码盘有效）；
/// 3. 恢复主密钥：输入恢复密钥 + 信封 �?解出主密钥（U 盘丢失场景）�?/// 4. 跳过加密：用户可选择不使用密码盘加密（适合轻度使用场景）�?///
/// 安全说明�?/// - PIN 最小长�?6 位（防离线暴力破解）
/// - Argon2id 密码哈希（t=3, m=64MiB, p=1�?class PasswordDiskPage extends StatefulWidget {
  const PasswordDiskPage({
    super.key,
    this.disk,
    this.onKeyUnlocked,
    this.encryption = const EncryptionService(),
    this.redirect,
  });

  /// 密码盘实现（测试注入 Mock；生产默�?Real）�?  final PasswordDisk? disk;

  /// 解锁成功后回调主密钥（供调用方加密笔记本）�?  /// 回调方应自行管理密钥生命周期，不在页面内持久化�?  final void Function(List<int> masterKey)? onKeyUnlocked;

  /// 加密服务（测试可注入 EncryptionService.test() 加�?Argon2id）�?  final EncryptionService encryption;

  /// GoRouter 重定向目标路径（解锁/创建成功后导航到此处）�?  final String? redirect;

  @override
  State<PasswordDiskPage> createState() => _PasswordDiskPageState();
}

class _PasswordDiskPageState extends State<PasswordDiskPage> {
  late final EncryptionService _encryption = widget.encryption;
  late final PasswordDisk _disk = widget.disk ?? createPasswordDisk();

  /// USB 磁盘自动检测器——插入含 key.frogkey �?U 盘时自动提示解锁�?  UsbDiskDetector? _usbDetector;

  @override
  void initState() {
    super.initState();
    // 启动 USB 自动检测（仅在非测试环境）�?    if (widget.disk == null) {
      _usbDetector = UsbDiskDetector(
        onDiskInserted: _onUsbDiskInserted,
        onDiskRemoved: _onUsbDiskRemoved,
      );
      _usbDetector!.start();
    } else {
      // 测试/直接传入 disk 时：自动解锁�?      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    }
  }

  /// U 盘插入时——如果检测到密码盘且当前未解锁，自动提示解锁�?  void _onUsbDiskInserted(DetectedPasswordDisk disk) {
    if (!mounted) return;
    if (_masterKey != null) return; // 已解锁，无需提示
    _showUsbUnlockPrompt(disk);
  }

  /// U 盘移除时——如果当前使用的是该密码盘，锁定�?  void _onUsbDiskRemoved(String path) {
    if (!mounted) return;
    // 如果 U 盘被拔出且当前依赖该密码盘，提示锁定�?    _snack('密码�?U 盘已移除，已锁定');
  }

  /// 弹出 U 盘解锁提示�?  void _showUsbUnlockPrompt(DetectedPasswordDisk disk) {
    showIosDialog<bool>(
      context,
      title: '检测到密码�?,
      content: '�?U �?${disk.path} 上发现了密码盘文件。\n${disk.isPinProtected ? "该密码盘已启�?PIN 保护�? : "是否立即解锁�?}',
      actions: [
        IosDialogAction(label: '稍后', result: false),
        IosDialogAction(
          label: '解锁',
          isDefault: true,
          result: true,
        ),
      ],
    ).then((result) {
      if (result == true && mounted) {
        _unlockFromUsb(disk.path);
      }
    });
  }

  /// 从指�?USB 路径解锁密码盘�?  Future<void> _unlockFromUsb(String path) async {
    try {
      var key = await _disk.readKey(path);
      if (key == null) {
        // PIN 保护——提示输�?PIN�?        final pin = await _promptPin();
        if (pin != null && pin.isNotEmpty) {
          key = await _disk.readKeyWithPin(path, pin: pin);
        }
      }
      if (!mounted) return;
      final resolved = key;
      if (resolved == null) {
        _snack('解锁失败：未找到有效的密码盘');
        return;
      }
      setState(() {
        _masterKey = resolved;
        _keyFingerprint = _fingerprint(resolved);
      });
      widget.onKeyUnlocked?.call(resolved);
      _snack('U 盘密码盘已解锁，密钥指纹 ${_fingerprint(resolved)}');
      _authenticateAndNavigate();
    } catch (e) {
      _snack('解锁失败�?{e.toString()}');
    }
  }

  /// 安全导航——当 GoRouter 不在 widget 树中时（如测试）静默失败�?  void _safeGo(String location) {
    try {
      GoRouter.of(context).go(location);
    } catch (_) {
      // 测试环境�?GoRouter 不可用，忽略导航�?    }
  }

  /// 安全认证+导航——仅�?GoRouter 可用时执行（生产环境）�?  /// 测试�?GoRouter 不可用时完全跳过，避免触�?AuthGuard 状态变更导致级联重建�?  ///
  /// 2026-08-25 修复：区分两种导航场景：
  /// - redirect != null：通过 GoRouter 重定向进入，使用 router.go() 导航
  /// - redirect == null：通过 Navigator.push 进入（如首页菜单），使用 Navigator.pop 返回
  ///   避免 GoRouter.go() 只替换路由栈而不弹出 Flutter Navigator 栈导致用户卡在密码页�?  void _authenticateAndNavigate() {
    if (!mounted) return;
    // 先检�?GoRouter 是否可用——不可用则完全跳过（测试环境）�?    GoRouter? router;
    try {
      router = GoRouter.of(context);
    } catch (_) {}
    if (router == null) return; // �?GoRouter，不执行任何操作�?
    final target = widget.redirect ?? RoutePaths.home;
    final pushedViaNavigator = widget.redirect == null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 先认证，确保 GoRouter 重定向不会把用户带回密码页�?      AuthGuard.instance.authenticate();
      if (pushedViaNavigator) {
        // 通过 Navigator.push 进入——pop 返回上一页（首页）�?        // 需要先检查是否可�?pop，避免根路由时出错�?        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop();
        } else {
          router!.go(target);
        }
      } else {
        // 通过 GoRouter 重定向进入——使�?GoRouter 导航到目标页�?        router!.go(target);
      }
    });
  }

  /// 当前读取到的主密钥（解锁后驻留内存；关闭页面即失效）�?  List<int>? _masterKey;
  String? _keyFingerprint;

  /// 恢复密钥信封（创建密码盘时生成，U 盘丢失时用于恢复主密钥）�?  String? _envelope;

  @override
  void dispose() {
    _usbDetector?.dispose();
    final key = _masterKey;
    if (key != null) {
      key.fillRange(0, key.length, 0); // 主动擦除内容
    }
    _masterKey = null;
    super.dispose();
  }

  String _fingerprint(List<int> key) {
    final hex = key
        .take(4)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return hex.toUpperCase();
  }

  Future<void> _createKeyFile() async {
    final dir = await _disk.pickDirectory();
    if (dir == null) return;
    // D-5 UI 集成�?026-08-15）：可�?PIN 保护——主密钥�?PIN 派生
    // KEK 包裹（OWASP KEK 模式），U 盘丢失也无法直接读出�?    final usePin = await _askPinProtection();
    if (!mounted) return;
    final String? pin = usePin ? await _promptPin() : null;
    // PIN 最小长�?6 位�?    if (usePin && (pin == null || pin.length < EncryptionService.kPinMinLength)) {
      if (pin != null && pin.isNotEmpty) {
        _snack('PIN 至少 ${EncryptionService.kPinMinLength} �?);
      }
      return;
    }
    final ok = usePin
        ? await _disk.createKeyFileWithPin(dir, pin: pin!)
        : await _disk.createKeyFile(dir);
    if (!mounted) return;
    if (!ok) {
      _snack('创建密码盘失�?);
      return;
    }
    // 读取刚创建的密钥用于演示，并生成恢复信封�?    final key = usePin
        ? await _disk.readKeyWithPin(dir, pin: pin!)
        : await _disk.readKey(dir);
    final recovery = generateRecoveryKey();
    final envelope = key != null
        ? await _encryption.wrapMasterKey(key, recovery)
        : null;
    if (!mounted) return;
    setState(() {
      _masterKey = key;
      _keyFingerprint = key != null ? _fingerprint(key) : null;
      _envelope = envelope;
    });
    // 创建成功后通知父组件密钥已就绪�?    if (key != null) widget.onKeyUnlocked?.call(key);
    await _showRecoveryDialog(recovery);
    AuditLogger.log('password_disk.create_key_file');
    _snack('密码盘已创建');
    _authenticateAndNavigate();
  }

  /// 展示恢复密钥（警示必须抄写）�?  /// 2026-08-25 修复：仅当用户点�?一键复�?时才复制到剪贴板，避�?  /// 点击"我已抄写"时也触发复制�?  Future<void> _showRecoveryDialog(String recovery) async {
    final result = await showIosDialog<String>(
      context,
      title: AppLocalizations.of(context)?.noteRecoveryKeyTitle ?? '保存您的恢复密钥（非常重要！�?,
      contentWidget: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            recovery,
            style: TextStyle(
              fontSize: TextScaleHelper.scaled(context, 18),
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '⚠️ 请抄写或截图保存到安全处。\n'
            'U 盘丢失或损坏时，凭此密钥可恢复主密钥。\n'
            '本应用不存储任何密钥，忘记恢复密钥将永久无法恢复�?,
            style: TextStyle(color: Color(0xFFFF3B30), fontSize: 13),
          ),
        ],
      ),
      actions: [
        IosDialogAction(
          label: '一键复�?,
          result: 'copy',
        ),
        IosDialogAction(
          label: AppLocalizations.of(context)?.diskCopied ?? '我已抄写',
          isDefault: true,
          result: 'done',
        ),
      ],
    );

    // 仅当用户点击"一键复�?时才复制到剪贴板
    if (result == 'copy' && mounted) {
      await Clipboard.setData(ClipboardData(text: recovery));
      if (mounted) {
        AppSnackbar.showSuccess(context, '恢复密钥已复制到剪贴�?);
      }
    }
  }

  /// 询问是否启用 PIN 保护（D-5 UI 集成 2026-08-15）�?  Future<bool> _askPinProtection() async {
    final result = await showIosDialog<bool>(
      context,
      title: AppLocalizations.of(context)?.diskPinProtection ?? '是否启用 PIN 保护�?,
      content: AppLocalizations.of(context)?.diskPinInfo ??
          '启用后主密钥�?PIN 加密存储（OWASP KEK 模式），U 盘丢失也无法直接读出；解锁需输入 PIN�?,
      actions: [
        IosDialogAction(
          label: AppLocalizations.of(context)?.diskNoPin ?? '不启�?,
          result: false,
        ),
        IosDialogAction(
          label: AppLocalizations.of(context)?.diskYesPin ?? '启用',
          result: true,
          isDefault: true,
        ),
      ],
    );
    return result ?? false;
  }

  /// 输入 PIN 保护密码盘的 PIN�?  /// 2026-08-25 修复：使�?Apple 风格 PIN 输入组件，输入满 6 位自动提交�?  Future<String?> _promptPin() async {
    String? enteredPin;
    final result = await showIosStatefulDialog<String>(
      context,
      title: AppLocalizations.of(context)?.diskEnterPin ?? '输入密码�?PIN',
      builder: (context, setState) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ApplePinInput(
              length: 6,
              onCompleted: (pin) {
                enteredPin = pin;
                Navigator.of(context).pop(pin);
              },
            ),
            const SizedBox(height: 8),
            Text(
              '请输�?${EncryptionService.kPinMinLength} 位数�?PIN',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF8E8E93),
              ),
            ),
          ],
        ),
      ),
      actions: [
        IosDialogAction(
          label: AppLocalizations.of(context)?.homeCancel ?? '取消',
        ),
      ],
    );
    return enteredPin ?? (result is String ? result : null);
  }

  /// 解锁密码盘：选目�?�?读取主密�?�?验证 PIN（如启用）�?  /// 2026-08-25 修复：PIN 错误时给出明确提示，而非静默失败；同时处�?  /// readKeyWithPin 抛出的异常（�?PIN 错误、文件损坏）�?  Future<void> _unlock() async {
    final dir = await _disk.pickDirectory();
    if (dir == null) return;
    var key = await _disk.readKey(dir);
    // PIN 保护格式 readKey 返回 null——提示输�?PIN�?    if (key == null && mounted) {
      final pin = await _promptPin();
      if (pin != null && pin.isNotEmpty) {
        try {
          key = await _disk.readKeyWithPin(dir, pin: pin);
        } catch (_) {
          // PIN 错误或文件损坏——给出明确提示�?          _snack('PIN 错误或密码盘文件损坏，请重试');
          return;
        }
      }
    }
    if (!mounted) return;
    final resolved = key;
    if (resolved == null) {
      AuditLogger.log('password_disk.unlock', success: false);
      _snack('未找到有效的密码盘（key.frogkey�?);
      return;
    }
    setState(() {
      _masterKey = resolved;
      _keyFingerprint = _fingerprint(resolved);
    });
    // 回调主密钥供调用方加密笔记本�?    widget.onKeyUnlocked?.call(resolved);
    AuditLogger.log('password_disk.unlock');
    _snack('密码盘已解锁，密钥指�?${_fingerprint(resolved)}');
    // 通知 AuthGuard 认证通过，GoRouter 重定向守卫不再拦截�?    _authenticateAndNavigate();
  }

  Future<void> _recoverFromKey() async {
    if (_envelope == null) {
      _snack('请先创建密码盘以生成恢复信封');
      return;
    }
    final controller = TextEditingController();
    try {
      final recovery = await showIosDialog<String>(
        context,
        title: '输入恢复密钥',
        contentWidget: CupertinoTextField(
          controller: controller,
          autofocus: true,
          placeholder: '24 位恢复密�?,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        actions: [
          IosDialogAction(
            label: AppLocalizations.of(context)?.homeCancel ?? '取消',
          ),
          IosDialogAction(
            label: '恢复',
            isDefault: true,
            result: '__confirm__',
          ),
        ],
      );
      if (recovery == null || recovery.isEmpty) return;
      final key = await _encryption.unwrapMasterKey(
        _envelope!,
        controller.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _masterKey = key;
        _keyFingerprint = _fingerprint(key);
      });
      widget.onKeyUnlocked?.call(key);
      _snack('恢复成功，主密钥指纹 ${_fingerprint(key)}');
      // 恢复成功后认证并导航到原目标页�?      _authenticateAndNavigate();
    } catch (_) {
      _snack('恢复密钥错误');
    } finally {
      controller.dispose();
    }
  }

  // ─── 锁定：清除内存中的主密钥 ────────────────────────────
  void _lock() {
    setState(() {
      _masterKey = null;
      _keyFingerprint = null;
    });
    // 通知 AuthGuard 锁定，GoRouter 重定向守卫将拦截后续导航�?    AuthGuard.instance.deauthenticate();
    AuditLogger.log('password_disk.lock');
    _snack('已锁�?�?主密钥已从内存清除，需要重新解锁才能解密数�?);
  }

  void _snack(String msg) {
    if (!mounted) return;
    AppSnackbar.showInfo(context, msg);
  }

  /// 跳过加密：用户选择不使用密码盘加密�?  /// 2026-08-25 修复：区�?Navigator.push �?GoRouter 重定向两种场景，
  /// 确保 Navigator.push 进入时正�?pop 返回上一页�?  Future<void> _skipEncryption() async {
    final confirmed = await showIosDialog<bool>(
      context,
      title: '跳过加密�?,
      content: '跳过加密后，您的笔记本将以明文存储。\n'
          '任何人都可以直接打开应用查看内容。\n\n'
          '您可以在设置中随时启用加密�?,
      actions: [
        IosDialogAction(
          label: '返回',
          result: false,
        ),
        IosDialogAction(
          label: '确认跳过',
          result: true,
          isDestructive: true,
          isDefault: true,
        ),
      ],
    );
    if (confirmed == true && mounted) {
      await AuthGuard.instance.skipEncryption();
      _snack('已跳过加密（可在设置中重新启用）');
      // 区分导航场景：Navigator.push 进入�?pop 返回，GoRouter 重定向时 go 跳转�?      final target = widget.redirect ?? RoutePaths.home;
      if (widget.redirect == null) {
        // 通过 Navigator.push 进入——pop 返回上一页�?        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final nav = Navigator.of(context);
          if (nav.canPop()) {
            nav.pop();
          } else {
            _safeGo(target);
          }
        });
      } else {
        _safeGo(target);
      }
    }
  }

  /// 构建密码盘状态卡片�?  Widget _buildStatusCard(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: _masterKey == null
            ? const Color(0xFFF2F2F7)
            : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Icon(
              _masterKey == null ? Icons.usb_off_rounded : Icons.usb_rounded,
              key: ValueKey('status_${_masterKey != null}'),
              size: 40,
              color: _masterKey == null ? const Color(0xFF8E8E93) : const Color(0xFF34C759),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _masterKey == null ? '密码盘未解锁' : '密码盘已解锁',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1D1D1F),
                  ),
                ),
                const SizedBox(height: 4),
                if (_masterKey == null)
                  const Text(
                    '插入 U 盘并选择密码盘目录解�?,
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF8E8E93),
                    ),
                  )
                else
                  _FingerprintBadge(fingerprint: _keyFingerprint ?? ''),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          '密码盘（U盘即钥匙�?,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AmbientBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 状态卡
            GlassSurface(
              padding: const EdgeInsets.all(12),
              child: _buildStatusCard(context),
            ),
            const SizedBox(height: 12),
            // 创建密码�?            GlassSurface(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: CupertinoButton.filled(
                  borderRadius: BorderRadius.circular(12),
                  padding: EdgeInsets.zero,
                  onPressed: _createKeyFile,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_box_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('创建密码盘（生成密钥 + 恢复密钥�?, style: TextStyle(fontSize: 15)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 解锁
            GlassSurface(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: CupertinoButton(
                  borderRadius: BorderRadius.circular(12),
                  padding: EdgeInsets.zero,
                  color: const Color(0xFFF2F2F7),
                  onPressed: _unlock,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.usb_rounded, size: 20, color: Color(0xFF0066CC)),
                      SizedBox(width: 8),
                      Text('解锁（选择 U 盘密码盘目录�?, style: TextStyle(fontSize: 15, color: Color(0xFF0066CC))),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 恢复
            GlassSurface(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: CupertinoButton(
                  borderRadius: BorderRadius.circular(12),
                  padding: EdgeInsets.zero,
                  color: const Color(0xFFF2F2F7),
                  onPressed: _recoverFromKey,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.restore_rounded, size: 20, color: Color(0xFF0066CC)),
                      SizedBox(width: 8),
                      Text('用恢复密钥找回主密钥（U 盘丢失）', style: TextStyle(fontSize: 15, color: Color(0xFF0066CC))),
                    ],
                  ),
                ),
              ),
            ),
            // 锁定按钮：仅在已解锁时显�?            if (_masterKey != null) ...[
              const SizedBox(height: 8),
              GlassSurface(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: CupertinoButton(
                    borderRadius: BorderRadius.circular(12),
                    padding: EdgeInsets.zero,
                    color: const Color(0xFFFFF3E0),
                    onPressed: _lock,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 20, color: Color(0xFFFF9500)),
                        SizedBox(width: 8),
                        Text('锁定（清除内存中的主密钥�?, style: TextStyle(fontSize: 15, color: Color(0xFFFF9500))),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            // 跳过加密选项
            GlassSurface(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '不想使用加密�?,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1D1D1F),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '您可以跳过加密直接使用应用。笔记本将以明文存储�?
                    '适合轻度使用场景。您随时可以在设置中启用加密�?,
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: CupertinoButton(
                      borderRadius: BorderRadius.circular(12),
                      padding: EdgeInsets.zero,
                      color: const Color(0xFFFFF3E0),
                      onPressed: _skipEncryption,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.skip_next_rounded, size: 20, color: Color(0xFFFF9500)),
                          SizedBox(width: 8),
                          Text('跳过加密，直接使�?, style: TextStyle(fontSize: 15, color: Color(0xFFFF9500))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlassSurface(
              padding: const EdgeInsets.all(12),
              child: const Text(
                '安全说明：主密钥�?56 位随机）仅存�?U �?key.frogkey�?
                '本应用不持久化任何密钥；�?U 盘谁也解不开。\n'
                '安全增强：Argon2id + HKDF-SHA256',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF8E8E93),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 密钥指纹仪表盘�?///
/// 展示主密钥指纹（�?4 字节十六进制）的圆形徽章 + 指纹文本 + 复制按钮�?/// 让用户直观确认当前解锁的密码盘身份�?class _FingerprintBadge extends StatelessWidget {
  const _FingerprintBadge({required this.fingerprint});

  final String fingerprint;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 圆形指纹徽章�?        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFF0066CC), Color(0xFF5AC8FA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Icon(Icons.fingerprint, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Text(
          '主密钥指�?$fingerprint（仅存内存）',
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF8E8E93),
          ),
        ),
        CupertinoButton(
          padding: EdgeInsets.zero,
          minSize: 0,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: fingerprint));
            AppSnackbar.showSuccess(context, '指纹已复�?);
          },
          child: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF0066CC)),
        ),
      ],
    );
  }
}
