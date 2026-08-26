// integrity_verifier.dart — 数据完整性 SHA-256 校验（2026-08-24）。
//
// 职责：
// - 对存储文档计算 SHA-256 校验和
// - 写入时嵌入校验和
// - 读取时验证校验和
// - 批量完整性扫描

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 完整性校验结果。
class VerificationResult {
  const VerificationResult({
    required this.key,
    required this.valid,
    this.storedChecksum,
    this.computedChecksum,
    this.error,
  });

  final String key;
  final bool valid;
  final String? storedChecksum;
  final String? computedChecksum;
  final String? error;

  Map<String, dynamic> toJson() => {
    'key': key,
    'valid': valid,
    if (storedChecksum != null) 'storedChecksum': storedChecksum,
    if (computedChecksum != null) 'computedChecksum': computedChecksum,
    if (error != null) 'error': error,
  };
}

/// 批量校验报告。
class IntegrityScanReport {
  const IntegrityScanReport({
    required this.results,
    required this.scanTime,
  });

  final List<VerificationResult> results;
  final DateTime scanTime;

  int get totalDocuments => results.length;
  int get validCount => results.where((r) => r.valid).length;
  int get corruptedCount => results.where((r) => !r.valid).length;
  bool get allValid => corruptedCount == 0;

  List<VerificationResult> get corruptedResults =>
      results.where((r) => !r.valid).toList();

  Map<String, dynamic> toJson() => {
    'scanTime': scanTime.toIso8601String(),
    'totalDocuments': totalDocuments,
    'validCount': validCount,
    'corruptedCount': corruptedCount,
    'allValid': allValid,
    'results': results.map((r) => r.toJson()).toList(),
  };
}

/// 数据完整性校验器。
class IntegrityVerifier {
  const IntegrityVerifier();

  /// 计算数据的 SHA-256 校验和（hex 字符串）。
  static String computeChecksum(String data) {
    return sha256.convert(utf8.encode(data)).toString();
  }

  /// 计算字节数据的 SHA-256 校验和。
  static String computeBytesChecksum(Uint8List bytes) {
    return sha256.convert(bytes).toString();
  }

  /// 验证单个文档的完整性。
  ///
  /// [content] 文档的 JSON 字符串内容。
  /// [storedChecksum] 存储的校验和。
  VerificationResult verify(String key, String content, String storedChecksum) {
    try {
      final computed = computeChecksum(content);
      return VerificationResult(
        key: key,
        valid: computed == storedChecksum,
        storedChecksum: storedChecksum,
        computedChecksum: computed,
      );
    } catch (e) {
      return VerificationResult(
        key: key,
        valid: false,
        error: e.toString(),
      );
    }
  }

  /// 验证 JSON 文档的完整性（从 JSON 中提取 checksum 字段）。
  VerificationResult verifyDocument(String key, String jsonContent) {
    try {
      final json = jsonDecode(jsonContent) as Map<String, dynamic>;
      final storedChecksum = json['checksum'] as String?;
      if (storedChecksum == null) {
        return VerificationResult(
          key: key,
          valid: false,
          error: 'No checksum field found',
        );
      }
      final dataJson = jsonEncode(json['data']);
      final computed = computeChecksum(dataJson);
      return VerificationResult(
        key: key,
        valid: computed == storedChecksum,
        storedChecksum: storedChecksum,
        computedChecksum: computed,
      );
    } catch (e) {
      return VerificationResult(
        key: key,
        valid: false,
        error: e.toString(),
      );
    }
  }

  /// 批量扫描目录下所有 JSON 文件的完整性。
  Future<IntegrityScanReport> scanDirectory(Directory dir) async {
    final results = <VerificationResult>[];

    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final key = entity.path.split(Platform.pathSeparator).last;
      try {
        final content = await entity.readAsString();
        results.add(verifyDocument(key, content));
      } catch (e) {
        results.add(VerificationResult(
          key: key,
          valid: false,
          error: e.toString(),
        ));
      }
    }

    return IntegrityScanReport(
      results: results,
      scanTime: DateTime.now(),
    );
  }

  /// 为数据生成带校验和的 JSON 字符串。
  static String wrapWithChecksum(Map<String, dynamic> data) {
    final dataJson = jsonEncode(data);
    final checksum = computeChecksum(dataJson);
    return jsonEncode({
      'data': data,
      'checksum': checksum,
      'verifiedAt': DateTime.now().toIso8601String(),
    });
  }

  /// 从带校验和的 JSON 中提取数据（验证通过）。
  static Map<String, dynamic>? unwrapWithVerification(String jsonContent) {
    try {
      final json = jsonDecode(jsonContent) as Map<String, dynamic>;
      final checksum = json['checksum'] as String?;
      if (checksum == null) return null;
      final dataJson = jsonEncode(json['data']);
      final computed = computeChecksum(dataJson);
      if (computed != checksum) return null;
      return json['data'] as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
