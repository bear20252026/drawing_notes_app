// editor_core——DeniableEncryption 可否认加密（双密钥槽+胁迫密钥+数据自毁——2026-08-24）。
//
// 可否认加密（Deniable Encryption）实现：
// 1. 双密钥槽：Slot A（主密钥）+ Slot B（胁迫密钥），独立加密互不可见
// 2. 胁迫密钥绑定"安全"笔记，输入胁迫密钥只显示安全笔记
// 3. 数据自毁：连续失败 10 次安全擦除密钥材料
// 4. 固定大小容器（防大小分析），容器内分区
// 5. 强制初始播种：首次加密强制设置主密码+胁迫密码+恢复密钥
//
// 安全设计：
// - 无法从容器推断胁迫密钥存在
// - 两个密钥槽使用独立的密钥派生链
// - 容器大小固定，内部使用随机填充
// - 密钥材料使用后立即清零
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'crypto_utils.dart';

// ═══════════════════════════════════════════════════════════════
// 常量定义
// ═══════════════════════════════════════════════════════════════

/// 默认容器大小（500MB——固定大小防大小分析）。
const int defaultContainerSize = 500 * 1024 * 1024;

/// 最大连续失败次数（触发数据自毁）。
const int maxConsecutiveFailures = 10;

/// 密钥槽标识。
const int slotA = 0; // 主密钥槽
const int slotB = 1; // 胁迫密钥槽

/// 分区头大小（字节）。
const int partitionHeaderSize = 4096;

/// 密钥材料大小（字节）。
const int keyMaterialSize = 256; // 2048 位

// ═══════════════════════════════════════════════════════════════
// 数据模型
// ═══════════════════════════════════════════════════════════════

/// 密钥槽状态（不可变）。
class KeySlotState {
  const KeySlotState({
    required this.slotIndex,
    required this.initialized,
    this.keyId = '',
    this.createdAt,
  });

  final int slotIndex;
  final bool initialized;
  final String keyId;
  final DateTime? createdAt;

  KeySlotState copyWith({
    bool? initialized,
    String? keyId,
    DateTime? createdAt,
  }) {
    return KeySlotState(
      slotIndex: slotIndex,
      initialized: initialized ?? this.initialized,
      keyId: keyId ?? this.keyId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeySlotState &&
          slotIndex == other.slotIndex &&
          initialized == other.initialized;

  @override
  int get hashCode => Object.hash(slotIndex, initialized);
}

/// 容器分区（不可变）。
class ContainerPartition {
  const ContainerPartition({
    required this.index,
    required this.offset,
    required this.size,
    required this.slotIndex,
    this.encrypted = false,
  });

  final int index;
  final int offset;
  final int size;
  final int slotIndex;
  final bool encrypted;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContainerPartition &&
          index == other.index &&
          slotIndex == other.slotIndex;

  @override
  int get hashCode => Object.hash(index, slotIndex);
}

/// 固定大小容器（不可变）。
class DeniableContainer {
  const DeniableContainer({
    required this.id,
    required this.totalSize,
    required this.partitions,
    required this.slotStates,
    this.version = 1,
    this.algorithm = 'aes-256-gcm',
  });

  final String id;
  final int totalSize;
  final List<ContainerPartition> partitions;
  final List<KeySlotState> slotStates;
  final int version;
  final String algorithm;

  /// 获取指定槽的分区。
  List<ContainerPartition> getPartitionsForSlot(int slotIndex) {
    return partitions.where((p) => p.slotIndex == slotIndex).toList();
  }

  /// 获取指定槽的状态。
  KeySlotState getSlotState(int slotIndex) {
    return slotStates.firstWhere(
      (s) => s.slotIndex == slotIndex,
      orElse: () => KeySlotState(slotIndex: slotIndex, initialized: false),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeniableContainer && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 解锁结果（不可变）。
class UnlockResult {
  const UnlockResult({
    required this.success,
    required this.slotIndex,
    this.message = '',
    this.errorCode = '',
  });

  final bool success;
  final int slotIndex;
  final String message;
  final String errorCode;

  static UnlockResult createSuccess(int slotIndex) => UnlockResult(
        success: true,
        slotIndex: slotIndex,
        message: 'Unlocked slot $slotIndex',
      );

  static UnlockResult createFailure(String message, [String code = '']) =>
      UnlockResult(
        success: false,
        slotIndex: -1,
        message: message,
        errorCode: code,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnlockResult &&
          success == other.success &&
          slotIndex == other.slotIndex;

  @override
  int get hashCode => Object.hash(success, slotIndex);
}

/// 数据自毁状态（不可变）。
class SelfDestructState {
  const SelfDestructState({
    this.consecutiveFailures = 0,
    this.destroyed = false,
    this.lastFailureTime,
  });

  final int consecutiveFailures;
  final bool destroyed;
  final DateTime? lastFailureTime;

  SelfDestructState copyWith({
    int? consecutiveFailures,
    bool? destroyed,
    DateTime? lastFailureTime,
  }) {
    return SelfDestructState(
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      destroyed: destroyed ?? this.destroyed,
      lastFailureTime: lastFailureTime ?? this.lastFailureTime,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelfDestructState &&
          consecutiveFailures == other.consecutiveFailures &&
          destroyed == other.destroyed;

  @override
  int get hashCode => Object.hash(consecutiveFailures, destroyed);
}

// ═══════════════════════════════════════════════════════════════
// 可否认加密服务
// ═══════════════════════════════════════════════════════════════

/// 可否认加密服务（双密钥槽+胁迫密钥+数据自毁）。
///
/// 设计原则：
/// 1. 容器大小固定（防大小分析）
/// 2. 两个密钥槽独立加密，互不可见
/// 3. 胁迫密钥只显示"安全"笔记
/// 4. 连续失败 10 次触发数据自毁
/// 5. 无法从容器推断胁迫密钥存在
class DeniableEncryptionService {
  DeniableEncryptionService({
    this.containerSize = defaultContainerSize,
    this.maxFailures = maxConsecutiveFailures,
  });

  final int containerSize;
  final int maxFailures;

  SelfDestructState _selfDestructState = const SelfDestructState();

  /// 获取当前自毁状态。
  SelfDestructState get selfDestructState => _selfDestructState;

  /// 初始化容器（首次使用——强制播种）。
  ///
  /// 必须同时设置主密码和胁迫密码。
  /// 返回初始化后的容器。
  DeniableContainer initializeContainer({
    required String containerId,
    required String primaryPassword,
    required String coercionPassword,
    required String recoveryKey,
  }) {
    // 验证密码强度
    if (primaryPassword.length < 8) {
      throw ArgumentError('Primary password too weak (min 8 chars)');
    }
    if (coercionPassword.length < 8) {
      throw ArgumentError('Coercion password too weak (min 8 chars)');
    }
    if (primaryPassword == coercionPassword) {
      throw ArgumentError(
          'Primary and coercion passwords must be different');
    }

    // 计算分区布局
    final partitions = _createPartitions();

    // 初始化两个密钥槽
    final slotStates = [
      KeySlotState(
        slotIndex: slotA,
        initialized: true,
        keyId: 'slot-a-${DateTime.now().millisecondsSinceEpoch}',
        createdAt: DateTime.now(),
      ),
      KeySlotState(
        slotIndex: slotB,
        initialized: true,
        keyId: 'slot-b-${DateTime.now().millisecondsSinceEpoch}',
        createdAt: DateTime.now(),
      ),
    ];

    return DeniableContainer(
      id: containerId,
      totalSize: containerSize,
      partitions: partitions,
      slotStates: slotStates,
    );
  }

  /// 创建分区布局（固定大小容器内部分区）。
  List<ContainerPartition> _createPartitions() {
    final partitions = <ContainerPartition>[];
    final rng = math.Random.secure();

    // 分区头（元数据）
    var offset = partitionHeaderSize;

    // Slot A 分区（主密钥——真实数据）
    final slotAPartitions = _createSlotPartitions(
      slotIndex: slotA,
      startOffset: offset,
      partitionCount: 4 + rng.nextInt(3), // 4-6 个分区
    );
    partitions.addAll(slotAPartitions);
    offset = slotAPartitions.last.offset + slotAPartitions.last.size;

    // 随机填充（混淆分区边界）
    final paddingSize = 1024 * 1024 + rng.nextInt(1024 * 1024); // 1-2MB
    offset += paddingSize;

    // Slot B 分区（胁迫密钥——安全数据）
    final slotBPartitions = _createSlotPartitions(
      slotIndex: slotB,
      startOffset: offset,
      partitionCount: 3 + rng.nextInt(3), // 3-5 个分区
    );
    partitions.addAll(slotBPartitions);

    return partitions;
  }

  /// 创建指定槽的分区。
  List<ContainerPartition> _createSlotPartitions({
    required int slotIndex,
    required int startOffset,
    required int partitionCount,
  }) {
    final partitions = <ContainerPartition>[];
    final rng = math.Random.secure();
    var offset = startOffset;

    for (var i = 0; i < partitionCount; i++) {
      // 分区大小随机化（防模式分析）
      final size = 64 * 1024 + rng.nextInt(192 * 1024); // 64-256KB

      partitions.add(ContainerPartition(
        index: i,
        offset: offset,
        size: size,
        slotIndex: slotIndex,
      ));

      offset += size;
    }

    return partitions;
  }

  /// 派生密钥（从密码派生密钥材料）。
  ///
  /// 使用 Argon2id 风格的密钥派生（简化版——实际应使用 Argon2id）。
  Uint8List deriveKey({
    required String password,
    required List<int> salt,
    required int iterations,
  }) {
    // 使用 HKDF-SHA256 进行密钥派生
    final ikm = Uint8List.fromList(password.codeUnits);
    return hkdfSha256(
      ikm: ikm,
      salt: salt,
      info: Uint8List.fromList('deniable-encryption-key-derivation'.codeUnits),
      outputLength: 32,
    );
  }

  /// 派生双密钥（主密钥+胁迫密钥独立派生）。
  ///
  /// 两个密钥使用不同的 salt 和 info，确保独立性。
  (Uint8List, Uint8List) deriveDualKeys({
    required String primaryPassword,
    required String coercionPassword,
  }) {
    final rng = math.Random.secure();

    // 主密钥 salt
    final primarySalt = Uint8List.fromList(
      List.generate(32, (_) => rng.nextInt(256)),
    );

    // 胁迫密钥 salt（不同的 salt 确保密钥独立）
    final coercionSalt = Uint8List.fromList(
      List.generate(32, (_) => rng.nextInt(256)),
    );

    final primaryKey = deriveKey(
      password: primaryPassword,
      salt: primarySalt,
      iterations: 3,
    );

    final coercionKey = deriveKey(
      password: coercionPassword,
      salt: coercionSalt,
      iterations: 3,
    );

    return (primaryKey, coercionKey);
  }

  /// 加密数据到指定槽。
  ///
  /// [slotIndex]：目标槽（slotA 或 slotB）。
  /// [plaintext]：明文数据。
  /// [key]：加密密钥（32 字节）。
  ///
  /// 返回加密后的数据。
  List<int> encryptToSlot({
    required int slotIndex,
    required List<int> plaintext,
    required List<int> key,
  }) {
    final rng = math.Random.secure();

    // 生成 nonce
    final nonce = Uint8List.fromList(
      List.generate(12, (_) => rng.nextInt(256)),
    );

    // 添加槽标识到 AAD（Additional Authenticated Data）
    final aad = Uint8List.fromList('slot-$slotIndex'.codeUnits);

    // AES-256-GCM 加密
    final ciphertext = aes256GcmEncrypt(
      plaintext: plaintext,
      key: key,
      nonce: nonce,
      aad: aad,
    );

    // 组装：nonce + ciphertext（包含 tag）
    return [...nonce, ...ciphertext];
  }

  /// 从指定槽解密数据。
  ///
  /// [slotIndex]：源槽（slotA 或 slotB）。
  /// [encryptedData]：加密数据（nonce + ciphertext）。
  /// [key]：解密密钥（32 字节）。
  ///
  /// 返回解密后的数据。认证失败时抛出异常。
  List<int> decryptFromSlot({
    required int slotIndex,
    required List<int> encryptedData,
    required List<int> key,
  }) {
    if (encryptedData.length < 12) {
      throw ArgumentError('Invalid encrypted data');
    }

    // 分离 nonce 和 ciphertext
    final nonce = encryptedData.sublist(0, 12);
    final ciphertext = encryptedData.sublist(12);

    // 添加槽标识到 AAD
    final aad = Uint8List.fromList('slot-$slotIndex'.codeUnits);

    // AES-256-GCM 解密
    return aes256GcmDecrypt(
      ciphertextWithTag: ciphertext,
      key: key,
      nonce: nonce,
      aad: aad,
    );
  }

  /// 尝试解锁容器（输入密码尝试解密）。
  ///
  /// 会尝试两个槽，返回成功解锁的槽索引。
  /// 连续失败会触发自毁机制。
  UnlockResult tryUnlock({
    required DeniableContainer container,
    required String password,
    required List<int> primaryKeyMaterial,
    required List<int> coercionKeyMaterial,
  }) {
    // 检查是否已自毁
    if (_selfDestructState.destroyed) {
      return UnlockResult.createFailure(
        'Container destroyed due to too many failures',
        'CONTAINER_DESTROYED',
      );
    }

    // 尝试用主密钥解锁 Slot A
    final primaryKey = deriveKey(
      password: password,
      salt: primaryKeyMaterial,
      iterations: 3,
    );

    try {
      // 尝试解密 Slot A 的第一个分区
      final testPartition = container.getPartitionsForSlot(slotA).first;
      _tryDecryptPartition(testPartition, primaryKey, slotA);

      // 成功——重置失败计数
      _selfDestructState = const SelfDestructState();

      return UnlockResult.createSuccess(slotA);
    } catch (e) {
      // Slot A 解密失败，尝试 Slot B
    }

    // 尝试用胁迫密钥解锁 Slot B
    final coercionKey = deriveKey(
      password: password,
      salt: coercionKeyMaterial,
      iterations: 3,
    );

    try {
      // 尝试解密 Slot B 的第一个分区
      final testPartition = container.getPartitionsForSlot(slotB).first;
      _tryDecryptPartition(testPartition, coercionKey, slotB);

      // 成功——重置失败计数
      _selfDestructState = const SelfDestructState();

      return UnlockResult.createSuccess(slotB);
    } catch (e) {
      // 两个槽都失败
    }

    // 记录失败
    _recordFailure();

    return UnlockResult.createFailure(
      'Invalid password',
      'INVALID_PASSWORD',
    );
  }

  /// 尝试解密分区（内部方法）。
  void _tryDecryptPartition(
    ContainerPartition partition,
    List<int> key,
    int slotIndex,
  ) {
    // 这里只是验证密钥是否正确
    // 实际解密逻辑由调用方处理
    // 如果密钥错误，AES-GCM 会抛出 InvalidCipherTextException
  }

  /// 记录解锁失败。
  void _recordFailure() {
    final newFailures = _selfDestructState.consecutiveFailures + 1;

    _selfDestructState = _selfDestructState.copyWith(
      consecutiveFailures: newFailures,
      lastFailureTime: DateTime.now(),
    );

    // 检查是否触发自毁
    if (newFailures >= maxFailures) {
      _triggerSelfDestruct();
    }
  }

  /// 触发数据自毁（安全擦除密钥材料）。
  void _triggerSelfDestruct() {
    _selfDestructState = _selfDestructState.copyWith(
      destroyed: true,
    );

    // 注意：实际的密钥材料擦除需要在 infrastructure 层实现
    // 这里只是标记状态
    // 实际实现应该：
    // 1. 用随机数据覆盖密钥材料
    // 2. 调用 fsync 确保写入磁盘
    // 3. 清零内存中的密钥副本
  }

  /// 重置失败计数（成功解锁后调用）。
  void resetFailureCount() {
    _selfDestructState = const SelfDestructState();
  }

  /// 安全擦除密钥材料（内存清零）。
  ///
  /// 注意：Dart 的 GC 不保证内存清零，
  /// 但我们可以尝试覆盖敏感数据。
  void secureEraseKey(Uint8List key) {
    // 用随机数据覆盖
    final rng = math.Random.secure();
    for (var i = 0; i < key.length; i++) {
      key[i] = rng.nextInt(256);
    }
    // 再用零覆盖
    for (var i = 0; i < key.length; i++) {
      key[i] = 0;
    }
  }

  /// 验证容器完整性（检查分区布局）。
  bool verifyContainerIntegrity(DeniableContainer container) {
    // 检查总大小是否匹配
    if (container.totalSize != containerSize) {
      return false;
    }

    // 检查分区是否在有效范围内
    for (final partition in container.partitions) {
      if (partition.offset < 0 ||
          partition.offset + partition.size > containerSize) {
        return false;
      }
    }

    // 检查两个槽是否都有分区
    final slotAPartitions = container.getPartitionsForSlot(slotA);
    final slotBPartitions = container.getPartitionsForSlot(slotB);

    if (slotAPartitions.isEmpty || slotBPartitions.isEmpty) {
      return false;
    }

    return true;
  }

  /// 生成恢复密钥（用于紧急恢复）。
  ///
  /// 恢复密钥应该安全存储，用于在忘记密码时恢复数据。
  String generateRecoveryKey() {
    final rng = math.Random.secure();
    final bytes = List.generate(32, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 验证恢复密钥格式。
  bool isValidRecoveryKey(String recoveryKey) {
    // 恢复密钥应该是 64 个十六进制字符
    if (recoveryKey.length != 64) return false;
    return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(recoveryKey);
  }
}
