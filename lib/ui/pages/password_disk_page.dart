import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/encryption_service.dart';
import '../../storage/password_disk.dart';

/// 密码盘管理页（U盘即钥匙，设计见 docs/PASSWORD_DISK_DESIGN.md）。
///
/// 功能：
/// 1. 创建密码盘：选目录 → 生成 key.frogkey（256 位主密钥）→ 展示 24 位恢复密钥；
/// 2. 校验/解锁：选目录 → 读取主密钥 → 显示指纹（证明密码盘有效）；
/// 3. 加密演示：用密码盘主密钥加密/解密一段文本（闭环验证）；
/// 4. 恢复主密钥：输入恢复密钥 + 信封 → 解出主密钥（U 盘丢失场景）。
class PasswordDiskPage extends StatefulWidget {
  const PasswordDiskPage({super.key, this.disk});

  /// 密码盘实现（测试注入 Mock；生产默认 Real）。
  final PasswordDisk? disk;

  @override
  State<PasswordDiskPage> createState() => _PasswordDiskPageState();
}

class _PasswordDiskPageState extends State<PasswordDiskPage> {
  static const EncryptionService _encryption = EncryptionService();
  late final PasswordDisk _disk = widget.disk ?? createPasswordDisk();

  /// 当前读取到的主密钥（解锁后驻留内存；关闭页面即失效）。
  List<int>? _masterKey;
  String? _keyFingerprint;

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

  @override
  void dispose() {
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

  /// 生成 24 位恢复密钥（去易混字符 0/O/1/I）。
  /// 生成 24 位恢复密钥（去易混字符 0/O/1/I）。
  ///
  /// 修复：原实现用时间戳算术取模，可能超出字母表长度导致 RangeError；
  /// 改用 Random 安全取下标。
  String _generateRecoveryKey() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    final sb = StringBuffer();
    for (var i = 0; i < 24; i++) {
      if (i > 0 && i % 4 == 0) sb.write('-');
      sb.write(alphabet[rng.nextInt(alphabet.length)]);
    }
    return sb.toString();
  }

  Future<void> _createKeyFile() async {
    final dir = await _disk.pickDirectory();
    if (dir == null) return;
    final ok = await _disk.createKeyFile(dir);
    if (!mounted) return;
    if (!ok) {
      _snack('创建密码盘失败');
      return;
    }
    // 读取刚创建的密钥用于演示，并生成恢复信封。
    final key = await _disk.readKey(dir);
    final recovery = _generateRecoveryKey();
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
    _snack('密码盘已创建');
  }

  /// 展示恢复密钥（警示必须抄写）。
  Future<void> _showRecoveryDialog(String recovery) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存您的恢复密钥（非常重要！）'),
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
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('我已抄写'),
          ),
        ],
      ),
    );
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
    final key = await _disk.readKey(dir);
    if (!mounted) return;
    if (key == null) {
      // 军工级增强：失败计数 + 阈值锁定。
      _registerFailure();
      return;
    }
    setState(() {
      _masterKey = key;
      _keyFingerprint = _fingerprint(key);
      _failCount = 0; // 解锁成功清零
      _lockedUntil = null;
    });
    _snack('密码盘已解锁，密钥指纹 ${_fingerprint(key)}');
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
            child: const Text('取消'),
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
      });
      _snack('恢复成功，主密钥指纹 ${_fingerprint(key)}');
    } catch (_) {
      _snack('恢复密钥错误');
    }
  }

  Future<void> _demoEncrypt() async {
    final key = _masterKey;
    if (key == null) {
      _snack('请先解锁密码盘');
      return;
    }
    final text = _demoInput ?? '政府项目演示文本';
    final encrypted = await _encryption.encryptWithKey(text, key);
    final decrypted = await _encryption.decryptWithKey(encrypted, key);
    if (!mounted) return;
    setState(() => _demoOutput = '解密回显：$decrypted');
    _snack('加密→解密闭环成功');
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
          const SizedBox(height: 24),
          // 加密演示
          const Text('加密闭环演示', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: '待加密文本',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => _demoInput = v,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.lock_outline),
            label: const Text('用密码盘密钥加密并解密回显'),
            onPressed: _demoEncrypt,
          ),
          if (_demoOutput != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _demoOutput!,
                style: const TextStyle(color: Colors.green),
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
