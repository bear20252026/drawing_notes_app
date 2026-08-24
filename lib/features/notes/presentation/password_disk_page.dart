import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'package:drawing_notes_app/core/storage/encryption_service.dart';
import 'package:drawing_notes_app/core/storage/password_disk.dart';
import 'package:drawing_notes_app/core/storage/recovery_key_generator.dart';
import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

/// 密码盘管理页（U盘即钥匙，设计见 docs/PASSWORD_DISK_DESIGN.md）。
///
/// 功能：
/// 1. 创建密码盘：选目录 → 生成 key.frogkey（256 位主密钥）→ 展示 24 位恢复密钥；
/// 2. 校验/解锁：选目录 → 读取主密钥 → 显示指纹（证明密码盘有效）；
/// 3. 加密演示：用密码盘主密钥加密/解密一段文本（闭环验证）；
/// 4. 恢复主密钥：输入恢复密钥 + 信封 → 解出主密钥（U 盘丢失场景）。
class PasswordDiskPage extends StatefulWidget {
  const PasswordDiskPage({super.key, this.disk, this.onKeyUnlocked});

  /// 密码盘实现（测试注入 Mock；生产默认 Real）。
  final PasswordDisk? disk;

  /// 解锁成功后回调主密钥（供调用方加密笔记本）。
  /// 回调方应自行管理密钥生命周期，不在页面内持久化。
  final void Function(List<int> masterKey)? onKeyUnlocked;

  @override
  State<PasswordDiskPage> createState() => _PasswordDiskPageState();
}

class _PasswordDiskPageState extends State<PasswordDiskPage> {
  static const EncryptionService _encryption = EncryptionService();
  late final PasswordDisk _disk = widget.disk ?? createPasswordDisk();

  /// 当前读取到的主密钥（解锁后驻留内存；关闭页面即失效）。
  List<int>? _masterKey;
  String? _keyFingerprint;

  /// #11 密码盘目录（解锁/创建后缓存，供落盘验证使用）。
  Directory? _diskDir;

  /// 恢复密钥信封（创建密码盘时生成，U 盘丢失时用于恢复主密钥）。
  String? _envelope;

  /// 军工级增强：连续解锁失败计数（达到阈值触发临时锁定）。
  int _failCount = 0;

  /// 军工级增强：锁定截止时间（锁定期间拒绝解锁尝试）。
  DateTime? _lockedUntil;

  /// 军工级增强：连续失败锁定阈值与锁定时长。
  static const int _maxFailures = 3;
  static const Duration _lockDuration = Duration(seconds: 30);

  /// 是否处于锁定状态。
  bool get _isLocked =>
      _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

  String? _demoInput;
  String? _demoOutput;

  /// #11 落盘密文验证：加密后写入的文件路径。
  String? _diskVerifyPath;

  /// #11 落盘密文验证：验证是否通过（文件内容不可读）。
  bool? _diskVerifyPassed;

  /// #11 用户主动锁定后标记（区别于自动过期锁定）。
  bool _userLocked = false;

  @override
  void dispose() {
    final key = _masterKey;
    if (key != null) {
      key.fillRange(0, key.length, 0); // S-4 增强（专家审查）：主动擦除内容
    }
    _masterKey = null; // 内存安全：关闭页面即清空密钥
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
    _diskDir = dir; // #11 缓存目录供落盘验证使用
    // D-5 UI 集成（2026-08-15）：可选 PIN 保护——主密钥经 PIN 派生
    // KEK 包裹（OWASP KEK 模式），U 盘丢失也无法直接读出。
    final usePin = await _askPinProtection();
    if (!mounted) return;
    final String? pin = usePin ? await _promptPin() : null;
    if (usePin && (pin == null || pin.length < 4)) {
      if (pin != null && pin.isNotEmpty) {
        _snack('PIN 至少 4 位（短 PIN 可被离线暴力破解）');
      }
      return;
    }
    final ok = usePin
        ? await _disk.createKeyFileWithPin(dir, pin: pin!)
        : await _disk.createKeyFile(dir);
    if (!mounted) return;
    if (!ok) {
      _snack('创建密码盘失败');
      return;
    }
    // 读取刚创建的密钥用于演示，并生成恢复信封。
    final key = usePin
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
    await _showRecoveryDialog(recovery);
    AuditLogger.log('password_disk.create_key_file');
    _snack('密码盘已创建');
  }

  /// 展示恢复密钥（警示必须抄写）。
  Future<void> _showRecoveryDialog(String recovery) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)?.noteRecoveryKeyTitle ?? '保存您的恢复密钥（非常重要！）'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              recovery,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ 请抄写或截图保存到安全处。\n'
              'U 盘丢失或损坏时，凭此密钥可恢复主密钥。\n'
              '本应用不存储任何密钥，忘记恢复密钥将永久无法恢复！',
              style: TextStyle(color: Colors.red),
            ),
          ],
        ),
        actions: [
          // #12 一键复制恢复密钥到剪贴板
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('一键复制'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: recovery));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('恢复密钥已复制到剪贴板')),
                );
              }
            },
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(context)?.diskCopied ?? '我已抄写'),
          ),
        ],
      ),
    );
  }

  /// 询问是否启用 PIN 保护（D-5 UI 集成 2026-08-15）。
  Future<bool> _askPinProtection() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(AppLocalizations.of(context)?.diskPinProtection ?? '是否启用 PIN 保护？'),
            content: Text(
              AppLocalizations.of(context)?.diskPinInfo ??
                  '启用后主密钥经 PIN 加密存储（OWASP KEK 模式），U 盘丢失也无法直接读出；解锁需输入 PIN。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(AppLocalizations.of(context)?.diskNoPin ?? '不启用'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(AppLocalizations.of(context)?.diskYesPin ?? '启用'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// 输入 PIN 保护密码盘的 PIN。
  Future<String?> _promptPin() async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)?.diskEnterPin ?? '输入密码盘 PIN'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '请输入 PIN',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(context)?.homeCancel ?? '取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(AppLocalizations.of(context)?.diskConfirm ?? '确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    return pin;
  }

  Future<void> _unlock() async {
    // 军工级增强：锁定期间拒绝解锁尝试（防暴力破解）。
    if (_isLocked) {
      final remain = _lockedUntil!.difference(DateTime.now()).inSeconds + 1;
      _snack('解锁尝试过多，已锁定 $remain 秒');
      return;
    }
    final dir = await _disk.pickDirectory();
    if (dir == null) return;
    _diskDir = dir; // #11 缓存目录供落盘验证使用
    var key = await _disk.readKey(dir);
    // D-5 UI 集成：v2 PIN 保护格式 readKey 返回 null——提示输入 PIN。
    if (key == null && mounted) {
      final pin = await _promptPin();
      if (pin != null && pin.isNotEmpty) {
        key = await _disk.readKeyWithPin(dir, pin: pin);
      }
    }
    if (!mounted) return;
    final resolved = key;
    if (resolved == null) {
      AuditLogger.log('password_disk.unlock', success: false);
      // 军工级增强：失败计数 + 阈值锁定。
      _registerFailure();
      return;
    }
    setState(() {
      _masterKey = resolved;
      _keyFingerprint = _fingerprint(resolved);
      _failCount = 0; // 解锁成功清零
      _lockedUntil = null;
      _userLocked = false;
      _diskVerifyPath = null;
      _diskVerifyPassed = null;
    });
    // #11 回调主密钥供调用方加密笔记本。
    widget.onKeyUnlocked?.call(resolved);
    AuditLogger.log('password_disk.unlock');
    _snack('密码盘已解锁，密钥指纹 ${_fingerprint(resolved)}');
  }

  /// 军工级增强：记录一次失败，达到阈值触发临时锁定。
  void _registerFailure() {
    setState(() {
      _failCount++;
      if (_failCount >= _maxFailures) {
        _lockedUntil = DateTime.now().add(_lockDuration);
        _failCount = 0;
      }
    });
    if (_isLocked) {
      _snack('连续失败 $_maxFailures 次，密码盘已锁定 ${_lockDuration.inSeconds} 秒');
    } else {
      _snack('未找到有效的密码盘（key.frogkey），还剩 ${_maxFailures - _failCount} 次机会');
    }
  }

  Future<void> _recoverFromKey() async {
    if (_envelope == null) {
      _snack('请先创建密码盘以生成恢复信封');
      return;
    }
    final controller = TextEditingController();
    final recovery = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入恢复密钥'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '24 位恢复密钥'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(context)?.homeCancel ?? '取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (recovery == null || recovery.isEmpty) return;
    try {
      final key = await _encryption.unwrapMasterKey(
        _envelope!,
        recovery.trim(),
      );
      if (!mounted) return;
      setState(() {
        _masterKey = key;
        _keyFingerprint = _fingerprint(key);
        _userLocked = false;
        _diskVerifyPath = null;
        _diskVerifyPassed = null;
      });
      // #11 回调主密钥供调用方加密笔记本。
      widget.onKeyUnlocked?.call(key);
      _snack('恢复成功，主密钥指纹 ${_fingerprint(key)}');
    } catch (_) {
      _snack('恢复密钥错误');
    }
  }

  // ─── #11 锁定：清除内存中的主密钥 ────────────────────────────
  void _lock() {
    setState(() {
      _masterKey = null;
      _keyFingerprint = null;
      _userLocked = true;
      _demoInput = null;
      _demoOutput = null;
      // 保留 _diskVerifyPath 和 _diskVerifyPassed 供用户验证落盘密文。
    });
    AuditLogger.log('password_disk.lock');
    _snack('已锁定 — 主密钥已从内存清除，需要重新解锁才能解密数据');
  }

  // ─── #11 落盘加密闭环演示 ─────────────────────────────────
  /// 加密演示文本 → 写入磁盘文件 → 读回验证肉眼不可读 → 解密验证可还原。
  Future<void> _demoEncrypt() async {
    final key = _masterKey;
    if (key == null) {
      _snack('请先解锁密码盘');
      return;
    }
    const plaintext = '这是测试明文数据_用于验证落盘密文不可读_假数据';
    setState(() {
      _demoInput = plaintext;
      _demoOutput = null;
      _diskVerifyPassed = null;
    });
    try {
      // 1. 加密
      final encrypted = await _encryption.encryptWithKey(plaintext, key);
      // 2. 写入磁盘文件（密码盘目录旁；若目录未知则用系统临时目录）
      final baseDir = _diskDir ?? Directory.systemTemp;
      final verifyFile = File(
        '${baseDir.path}${Platform.pathSeparator}.encryption_verify.bin',
      );
      await verifyFile.writeAsString(encrypted, flush: true);
      // 3. 读回原始文件内容
      final rawContent = await verifyFile.readAsString();
      // 4. 验证：文件内容不包含原始明文
      final containsPlaintext = rawContent.contains('这是测试明文数据');
      // 5. 解密验证可还原
      final decrypted = await _encryption.decryptWithKey(rawContent, key);
      if (!mounted) return;
      setState(() {
        _diskVerifyPath = verifyFile.path;
        _diskVerifyPassed = !containsPlaintext;
        _demoOutput = '📁 落盘文件: ${verifyFile.path}'
            '\n🔍 文件含明文: ${containsPlaintext ? '⚠️ 是 — 未通过' : '✅ 否 — 通过'}'
            '\n🔓 解密回显: $decrypted'
            '\n\n✅ 落盘后打开文件，看到的是密文而非明文';
      });
      if (!containsPlaintext) {
        _snack('✅ 落盘密文验证通过：文件内容肉眼不可读');
      } else {
        _snack('⚠️ 落盘验证失败：文件中仍包含明文');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _demoOutput = '加密验证失败: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('密码盘（U盘即钥匙）')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 状态卡（军工级增强：状态动画 + 锁定倒计时 + 指纹仪表盘）
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: _isLocked
                  ? Theme.of(context).colorScheme.errorContainer
                  : (_masterKey == null
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : Theme.of(context).colorScheme.primaryContainer),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    _isLocked
                        ? Icons.lock_clock
                        : (_masterKey == null ? Icons.usb_off : Icons.usb),
                    key: ValueKey('status_${_isLocked}_${_masterKey != null}'),
                    size: 40,
                    color: _isLocked
                        ? Theme.of(context).colorScheme.error
                        : (_masterKey == null ? Colors.grey : Colors.green),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isLocked
                            ? '密码盘已临时锁定'
                            : (_masterKey == null ? '密码盘未解锁' : '密码盘已解锁'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      // 锁定倒计时 / 指纹仪表盘 / 提示
                      if (_isLocked)
                        Text(
                          '解锁尝试过多，${_lockedUntil!.difference(DateTime.now()).inSeconds + 1} 秒后重试',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        )
                      else if (_masterKey == null)
                        Text(
                          '插入 U 盘并选择密码盘目录解锁 · 剩余机会 '
                          '${_maxFailures - _failCount} 次',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else
                        _FingerprintBadge(fingerprint: _keyFingerprint ?? ''),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 创建密码盘
          FilledButton.icon(
            icon: const Icon(Icons.add_box_outlined),
            label: const Text('创建密码盘（生成密钥 + 恢复密钥）'),
            onPressed: _createKeyFile,
          ),
          const SizedBox(height: 8),
          // 解锁
          OutlinedButton.icon(
            icon: const Icon(Icons.usb),
            label: const Text('解锁（选择 U 盘密码盘目录）'),
            onPressed: _unlock,
          ),
          const SizedBox(height: 8),
          // 恢复
          OutlinedButton.icon(
            icon: const Icon(Icons.restore),
            label: const Text('用恢复密钥找回主密钥（U 盘丢失）'),
            onPressed: _recoverFromKey,
          ),
          // #11 锁定按钮：仅在已解锁时显示
          if (_masterKey != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.lock_outline),
              label: const Text('锁定（清除内存中的主密钥）'),
              onPressed: _lock,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
              ),
            ),
          ],
          const SizedBox(height: 24),
          // #11 落盘加密闭环演示
          const Text('落盘加密验证', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            '加密测试数据 → 写入磁盘文件 → 读回验证肉眼不可读 → 解密验证可还原',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.lock_outline),
            label: Text(_masterKey != null
                ? '加密并落盘验证'
                : '请先解锁密码盘'),
            onPressed: _masterKey != null ? _demoEncrypt : null,
          ),
          // #11 落盘验证结果指示器
          if (_diskVerifyPassed != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(
                    _diskVerifyPassed! ? Icons.check_circle : Icons.error,
                    color: _diskVerifyPassed! ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _diskVerifyPassed!
                          ? '✅ 落盘密文验证通过：文件内容肉眼不可读'
                          : '⚠️ 落盘验证失败：文件中仍包含明文',
                      style: TextStyle(
                        color: _diskVerifyPassed! ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_demoOutput != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _demoOutput!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            '安全说明：主密钥（256 位随机）仅存于 U 盘 key.frogkey，'
            '本应用不持久化任何密钥；无 U 盘谁也解不开。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// 军工级增强：密钥指纹仪表盘。
///
/// 展示主密钥指纹（前 4 字节十六进制）的圆形徽章 + 指纹文本 + 复制按钮，
/// 让用户直观确认当前解锁的密码盘身份。
class _FingerprintBadge extends StatelessWidget {
  const _FingerprintBadge({required this.fingerprint});

  final String fingerprint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 圆形指纹徽章（仪表盘视觉）。
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [scheme.primary, scheme.tertiary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Icon(Icons.fingerprint, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Text(
          '主密钥指纹 $fingerprint（仅存内存）',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        IconButton(
          tooltip: '复制指纹',
          icon: const Icon(Icons.copy, size: 16),
          visualDensity: VisualDensity.compact,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: fingerprint));
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('指纹已复制')));
          },
        ),
      ],
    );
  }
}
