// 迁移框架回归锁（内核 P1-DOC-001，2026-10-10）。
//
// 钉三条相反方向（T-E 纪律）：
// ① 迁移生效——v1 文件规范化后版本回写、缺键补齐、内容零丢失；
// ② 合法稳态不误伤——当前 v2 文件经 runner 原样通过（幂等）；
// ③ 缺环节不新增拒绝路径——未知版本停留在原样交宽容解码器。
// 另钉 codec 全链路：v1 信封经 decode 出正确文档（AW2 语义保持）。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/documents/migration/document_migration.dart';
import 'package:drawing_notes_app/core/documents/migration/document_migration_registry.dart';
import 'package:drawing_notes_app/core/storage/document_codec.dart';

Map<String, dynamic> _v1Envelope() => {
  // 无 version 键（最早格式）；笔画缺 seed/version/versionNonce；文档缺 textItems。
  'document': {
    'id': 'doc_v1file',
    'title': 'v1 遗留文件',
    'width': 2048,
    'height': 1536,
    'layers': [
      {
        'id': 'layer_1',
        'name': '',
        'strokes': [
          {
            'points': [10, 20, 0.5, 30, 40, 0.75],
            'color': 0xFF1A1A1A,
            'width': 2,
            'type': 'pen',
          },
        ],
        'shapes': <Map<String, dynamic>>[],
        'images': <Map<String, dynamic>>[],
      },
    ],
  },
};

void main() {
  group('DocumentMigrationRunner', () {
    test('① v1 → v2：版本回写、笔画补版本字段、textItems 补空', () {
      final envelope = _v1Envelope();
      final reached = kDocumentMigrationRunner.migrateToCurrent(envelope);

      expect(reached, 2);
      expect(envelope['version'], 2);
      final doc = envelope['document'] as Map<String, dynamic>;
      expect(doc.containsKey('textItems'), isTrue);
      final stroke =
          ((doc['layers'] as List).first as Map)['strokes'].first as Map;
      expect(stroke['version'], 0);
      expect(stroke['versionNonce'], 0);
      expect(stroke.containsKey('seed'), isFalse, reason: 'v1 无 seed——刻意不补（见条目注释）');
      // 内容零丢失：点列/颜色原样。
      expect(stroke['points'], [10, 20, 0.5, 30, 40, 0.75]);
    });

    test('② 当前 v2 文件幂等通过（合法稳态不误伤）', () {
      final envelope = {
        'version': 2,
        'document': {
          'id': 'doc_v2file',
          'title': '现行格式',
          'layers': [
            {
              'id': 'layer_1',
              'name': '',
              'strokes': [
                {
                  'points': [1, 2, 3.0],
                  'color': 255,
                  'width': 1,
                  'type': 'pen',
                  'seed': 42,
                  'version': 3,
                  'versionNonce': 7,
                },
              ],
            },
          ],
          'textItems': <Map<String, dynamic>>[
            {'id': 't1', 'text': '正文'},
          ],
        },
      };
      final snapshot = jsonEncode(envelope);
      expect(kDocumentMigrationRunner.migrateToCurrent(envelope), 2);
      expect(jsonEncode(envelope), snapshot, reason: 'v2 文件零字节变化');
    });

    test('③ 缺迁移环节：停在当前版本，不抛出、不伪造推进', () {
      final sparse = DocumentMigrationRunner(
        supportedVersion: 3,
        migrations: const [MigrationV1ToV2()], // 缺 2→3
      );
      final envelope = _v1Envelope();
      expect(sparse.migrateToCurrent(envelope), 2, reason: '推进到有环节的顶即停');
      expect(envelope['version'], 2);
    });
  });

  group('codec 全链路', () {
    test('v1 信封经 decode：字段默认正确、seed 维持每次新派生', () {
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(_v1Envelope())));
      final doc = const DocumentCodec().decode(bytes);

      expect(doc.id, 'doc_v1file');
      expect(doc.title, 'v1 遗留文件');
      expect(doc.textItems, isEmpty);
      final stroke = doc.layers.single.strokes.single;
      expect(stroke.version, 0);
      expect(stroke.points, hasLength(2));
      expect(stroke.seed, isNot(0), reason: 'v1 无 seed → 构造器派生新随机种子（历史行为）');
    });

    test('注册表支持版本与 codec 单一来源一致', () {
      expect(kSupportedDocumentVersion, DocumentCodec.latestVersion);
    });
  });
}
