import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import 'package:drawing_notes_app/core/storage/encryption_service.dart';

/// 密码盘（U盘即钥匙）服务接口（设计见 docs/PASSWORD_DISK_DESIGN.md）。
///
/// 零知识架构：主密钥（256 位随机）只存在 U 盘的 key.frogkey 文件中，
/// 应用软件不持久化任何密钥；无 U 盘谁也解不开。
/// UI/ViewModel 只依赖本抽象，通过依赖注入切换 Real/Mock 实现。
abstract class PasswordDisk {
  /// 让用户选择密码盘位置（U 盘目录 / 测试目录），取消返回 null。
  Future<String?> pickDirectory();

  /// 在 [dir] 下生成并写入 key.frogkey（含主密钥），返回是否成功。
  Future<bool> createKeyFile(String dir);

  /// 读取 [dir] 下密码盘的主密钥（32 字节）；无效返回 null。
  Future<List<int>?> readKey(String dir);

  /// 校验 [dir] 下的密码盘文件是否有效（Magic/版本/长度）。
  Future<bool> validateKeyFile(String dir);

  /// 创建带 PIN 保护的密码盘（v2：主密钥经 PIN 派生 KEK 包裹，防物理提取）。
  Future<bool> createKeyFileWithPin(String dir, {required String pin});

  /// 读取 PIN 保护密码盘的主密钥（v2 格式；PIN 错误/损坏返回 null）。
  Future<List<int>?> readKeyWithPin(String dir, {required String pin});
}

/// key.frogkey 文件格式（37 字节定长）：
///   0..3   Magic `FROG`（0x46 0x52 0x4F 0x47）
///   4     版本 0x01
///   5..36  32 字节主密钥（256 位，Random.secure() 生成）
class PasswordDiskFile {
  static const List<int> _magic = [0x46, 0x52, 0x4F, 0x47]; // FROG
  static const int _version = 0x01;
  static const int keyLength = 32;
  static const int fileLength = 37;

  /// 生成 32 字节主密钥（加密安全随机源）。
  static List<int> generateKey() {
    final rng = Random.secure();
    return List<int>.generate(keyLength, (_) => rng.nextInt(256));
  }

  /// 组装密钥文件字节（Magic + 版本 + 主密钥）。
  static List<int> encode(List<int> key) => [..._magic, _version, ...key];

  /// 解析密钥文件字节；格式无效返回 null。
  static List<int>? decode(List<int> bytes) {
    if (bytes.length != fileLength) return null;
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return null;
    }
    if (bytes[4] != _version) return null;
    return bytes.sublist(5);
  }

  /// PIN 保护 v2 编码（红蓝攻防 D-5 修复 2026-08-15，P2 中期核心机制）：
  /// 用 PIN 派生 KEK 包裹主密钥（OWASP Key Management Cheat Sheet：存储
  /// 密钥须用 KEK 加密，KEK 强度不低于被保护密钥）——key.frogkey 不再
  /// 明文存主密钥，物理获取 U 盘也无法直接读出。
  /// 格式：[magic(4), 0x02, ...信封 JSON（salt/nonce/ek/mac，复用
  /// EncryptionService.wrapMasterKey——PIN 作 KEK 派生输入）]。
  static Future<List<int>> encodeWithPin({
    required List<int> key,
    required String pin,
  }) async {
    final envelope = await const EncryptionService().wrapMasterKey(key, pin);
    return [..._magic, 0x02, ...utf8.encode(envelope)];
  }

  /// PIN 保护 v2 解码：PIN 正确返回主密钥，错误/损坏返回 null。
  static Future<List<int>?> decodeWithPin(
    List<int> bytes,
    String pin,
  ) async {
    if (bytes.length < 6 ||
        bytes[0] != _magic[0] ||
        bytes[1] != _magic[1] ||
        bytes[2] != _magic[2] ||
        bytes[3] != _magic[3] ||
        bytes[4] != 0x02) {
      return null;
    }
    try {
      final envelope = utf8.decode(bytes.sublist(5));
      return await const EncryptionService().unwrapMasterKey(envelope, pin);
    } catch (_) {
      return null;
    }
  }
}

/// 真实密码盘：通过系统文件选择器选取 U 盘目录（生产环境）。
class RealPasswordDisk implements PasswordDisk {
  const RealPasswordDisk();

  static const String keyFileName = 'key.frogkey';

  @override
  Future<String?> pickDirectory() async {
    final dir = await getDirectoryPath(confirmButtonText: '选择密码盘位置');
    return dir == null || dir.isEmpty ? null : dir;
  }

  @override
  Future<bool> createKeyFile(String dir) async {
    try {
      final key = PasswordDiskFile.generateKey();
      final file = File('$dir${Platform.pathSeparator}$keyFileName');
      await file.writeAsBytes(PasswordDiskFile.encode(key), flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<int>?> readKey(String dir) async {
    final file = File('$dir${Platform.pathSeparator}$keyFileName');
    if (!await file.exists()) return null;
    try {
      return PasswordDiskFile.decode(await file.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> validateKeyFile(String dir) async {
    final key = await readKey(dir);
    return key != null && key.length == PasswordDiskFile.keyLength;
  }

  @override
  Future<bool> createKeyFileWithPin(String dir, {required String pin}) async {
    try {
      final key = PasswordDiskFile.generateKey();
      final file = File('$dir${Platform.pathSeparator}key.frogkey');
      final encoded = await PasswordDiskFile.encodeWithPin(key: key, pin: pin);
      await file.writeAsBytes(encoded, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<int>?> readKeyWithPin(String dir, {required String pin}) async {
    final file = File('$dir${Platform.pathSeparator}key.frogkey');
    if (!await file.exists()) return null;
    try {
      return await PasswordDiskFile.decodeWithPin(await file.readAsBytes(), pin);
    } catch (_) {
      return null;
    }
  }
}

/// 模拟密码盘：固定测试目录（开发/测试环境，kDebugMode 注入）。
///
/// 无需插 U 盘即可验证完整流程（创建→加密→解锁→恢复）。
class MockPasswordDisk implements PasswordDisk {
  MockPasswordDisk({this.baseDir});

  /// 模拟 U 盘根目录；null 时使用系统临时目录。
  final String? baseDir;

  String _dir() =>
      baseDir ??
      '${Directory.systemTemp.path}${Platform.pathSeparator}frogkey_mock';

  @override
  Future<String?> pickDirectory() async => _dir();

  @override
  Future<bool> createKeyFile(String dir) async {
    try {
      final key = PasswordDiskFile.generateKey();
      final file = File('$dir${Platform.pathSeparator}key.frogkey');
      await file.writeAsBytes(PasswordDiskFile.encode(key), flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<int>?> readKey(String dir) async {
    final file = File('$dir${Platform.pathSeparator}key.frogkey');
    if (!await file.exists()) return null;
    try {
      return PasswordDiskFile.decode(await file.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> validateKeyFile(String dir) async {
    final key = await readKey(dir);
    return key != null && key.length == PasswordDiskFile.keyLength;
  }

  @override
  Future<bool> createKeyFileWithPin(String dir, {required String pin}) async {
    try {
      final key = PasswordDiskFile.generateKey();
      final file = File('$dir${Platform.pathSeparator}key.frogkey');
      final encoded = await PasswordDiskFile.encodeWithPin(key: key, pin: pin);
      await file.writeAsBytes(encoded, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<int>?> readKeyWithPin(String dir, {required String pin}) async {
    final file = File('$dir${Platform.pathSeparator}key.frogkey');
    if (!await file.exists()) return null;
    try {
      return await PasswordDiskFile.decodeWithPin(await file.readAsBytes(), pin);
    } catch (_) {
      return null;
    }
  }
}

/// 依赖注入工厂：Debug/测试用 Mock，Release 用 Real。
PasswordDisk createPasswordDisk({String? mockBaseDir}) {
  if (kDebugMode) return MockPasswordDisk(baseDir: mockBaseDir);
  return const RealPasswordDisk();
}
