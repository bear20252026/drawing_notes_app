// 迁移框架回归锁（内核 P1-DOC-001，2026-10-10；v2→v3 增补 2026-10-11；v4 样式键 2026-10-12）。
//
// 钉三条相反方向（T-E 纪律）：
// ① 迁移生效——v1 文件规范化后版本回写、缺键补齐、内容零丢失；
// ② 合法稳态不误伤——当前 v4 文件经 runner 原样通过（幂等）；
// ③ 缺环节不新增拒绝路径——未知版本停留在原样交宽容解码器。
// v2→v3 额外钉：id 派生唯一、已有 id 绝不重写、codec 全链路保 id。
// v4 额外钉：样式键**只删非法值、绝不补默认值**（补了会压住 dash/rough 开关），
// 且写盘只记偏离旧推导的值（旧文件重存不长新键）。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'package:drawing_notes_app/core/documents/migration/document_migration.dart';
import 'package:drawing_notes_app/core/documents/migration/document_migration_registry.dart';
import 'package:drawing_notes_app/core/storage/document_codec.dart';

Map<String, dynamic> _v1Envelope() => {
  // 无 version 键（最早格式）；笔画缺 seed/version/versionNonce/id；文档缺 textItems。
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

Map<String, dynamic> _v2Envelope() {
  final envelope = _v1Envelope();
  envelope['version'] = 2;
  final doc = envelope['document'] as Map<String, dynamic>;
  doc['textItems'] = <Map<String, dynamic>>[];
  final stroke =
      (((doc['layers'] as List).first as Map)['strokes'] as List).first as Map;
  stroke['version'] = 0;
  stroke['versionNonce'] = 0;
  return envelope;
}

void main() {
  group('DocumentMigrationRunner', () {
    test('① v1 → v4：逐级推进，版本回写、缺键补齐、id 派生、内容零丢失', () {
      final envelope = _v1Envelope();
      final reached = kDocumentMigrationRunner.migrateToCurrent(envelope);

      expect(reached, 4);
      expect(envelope['version'], 4);
      final doc = envelope['document'] as Map<String, dynamic>;
      expect(doc.containsKey('textItems'), isTrue);
      final stroke =
          ((doc['layers'] as List).first as Map)['strokes'].first as Map;
      expect(stroke['version'], 0);
      expect(stroke['versionNonce'], 0);
      expect(stroke.containsKey('seed'), isFalse, reason: 'v1 无 seed——刻意不补（见条目注释）');
      expect(stroke['id'], isA<String>(), reason: 'v3 迁移派生持久 id');
      expect((stroke['id'] as String).isNotEmpty, isTrue);
      // 内容零丢失：点列/颜色原样。
      expect(stroke['points'], [10, 20, 0.5, 30, 40, 0.75]);
      expect(stroke['color'], 0xFF1A1A1A);
    });

    test('② 当前 v4 文件幂等通过（合法稳态不误伤）', () {
      final envelope = {
        'version': 4,
        'document': {
          'id': 'doc_v4file',
          'title': '现行格式',
          'layers': [
            {
              'id': 'layer_1',
              'name': '',
              'strokes': [
                {
                  'id': 'str_fixed_identity',
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
      expect(kDocumentMigrationRunner.migrateToCurrent(envelope), 4);
      expect(jsonEncode(envelope), snapshot, reason: 'v4 文件零字节变化（含 id 不重写）');
    });

    test('②a v3 → v4：只删非法样式键，绝不补默认值', () {
      final envelope = {
        'version': 3,
        'document': {
          'id': 'doc_v3styles',
          'title': '带样式',
          'layers': <Map<String, dynamic>>[],
          'shapes': [
            {
              'id': 'sh_legacy',
              'shapeType': 'rect',
              'x': 0.0, 'y': 0.0, 'width': 10.0, 'height': 10.0,
              'color': 255,
              'fillColor': 255,
              'strokeWidth': 1.0,
              'dash': true,
              'rough': true,
            },
            {
              'id': 'sh_explicit_kept',
              'shapeType': 'rect',
              'x': 0.0, 'y': 0.0, 'width': 10.0, 'height': 10.0,
              'color': 255,
              'strokeWidth': 1.0,
              'dash': false,
              'rough': false,
              'strokeStyle': 'dotted',
            },
            {
              'id': 'sh_bogus_value',
              'shapeType': 'rect',
              'x': 0.0, 'y': 0.0, 'width': 10.0, 'height': 10.0,
              'color': 255,
              'strokeWidth': 1.0,
              'dash': true,
              'rough': false,
              'strokeStyle': 'squiggly',
              'fillStyle': 'polkaDot',
            },
          ],
        },
      };
      expect(kDocumentMigrationRunner.migrateToCurrent(envelope), 4);
      final shapes = (envelope['document'] as Map)['shapes'] as List;
      // 缺键不补：一补就把 dash/rough 定格，工具条开关随后会被显式值压住。
      expect(shapes[0].containsKey('strokeStyle'), isFalse, reason: '旧布尔不能被定格成显式键');
      expect(shapes[0].containsKey('fillStyle'), isFalse);
      expect(shapes[1]['strokeStyle'], 'dotted', reason: '合法显式值原样保留');
      expect(shapes[2].containsKey('strokeStyle'), isFalse, reason: '非法取值删除（解码层本来也丢弃）');
      expect(shapes[2].containsKey('fillStyle'), isFalse);
    });

    test('②c 写盘只记偏离旧推导的样式键（旧文件重存不长键）', () {
      PageShapeItem shape({
        required bool dash,
        required bool rough,
        int? fillColor,
        StrokeStyle? strokeStyle,
        FillStyle? fillStyle,
      }) => PageShapeItem(
        id: 'sh',
        shapeType: ShapeType.rect,
        x: 0,
        y: 0,
        width: 10,
        height: 10,
        dash: dash,
        rough: rough,
        fillColor: fillColor,
        strokeStyle: strokeStyle,
        fillStyle: fillStyle,
      );

      // 与旧推导一致的显式值不落键。
      expect(
        shape(dash: true, rough: true, fillColor: 255, strokeStyle: StrokeStyle.dashed, fillStyle: FillStyle.hachure)
            .toJson()
            .keys,
        isNot(contains('strokeStyle')),
      );
      expect(
        shape(dash: true, rough: true, fillColor: 255, strokeStyle: StrokeStyle.dashed, fillStyle: FillStyle.hachure)
            .toJson()
            .keys,
        isNot(contains('fillStyle')),
      );
      // 偏离的才落键。
      expect(shape(dash: false, rough: false, strokeStyle: StrokeStyle.dotted).toJson()['strokeStyle'], 'dotted');
      expect(
        shape(dash: false, rough: true, fillColor: 255, fillStyle: FillStyle.solid).toJson()['fillStyle'],
        'solid',
        reason: '手绘形状显式关掉斜线——v4 的新能力',
      );
      expect(
        shape(dash: false, rough: true, fillColor: 255, fillStyle: FillStyle.crossHatch).toJson()['fillStyle'],
        'crossHatch',
      );
      expect(
        shape(dash: false, rough: false, strokeStyle: StrokeStyle.dotted).toJson()['fillStyle'],
        isNull,
        reason: '无填充色时不写 fillStyle',
      );
      // dash/rough 两个旧键始终还在，旧版本读得到基本观感。
      final json = shape(dash: true, rough: true, strokeStyle: StrokeStyle.dotted).toJson();
      expect(json['dash'], isTrue);
      expect(json['rough'], isTrue);
    });

    test('②b v2 → v3：id 逐条派生且唯一；已有 id 的笔画绝不重写', () {
      final envelope = _v2Envelope();
      // 预置一条已有 id 的笔画（部分升级/同版本重放场景）。
      final strokes =
          (((envelope['document'] as Map)['layers'] as List).first as Map)
              ['strokes'] as List;
      strokes.add({
        'id': 'str_preexisting',
        'points': [5, 6, 1.0],
        'color': 255,
        'width': 1,
        'type': 'pen',
        'version': 1,
        'versionNonce': 1,
      });

      expect(kDocumentMigrationRunner.migrateToCurrent(envelope), 4);
      expect(strokes[0]['id'], isA<String>());
      expect(strokes[0]['id'], isNot('str_preexisting'));
      expect(strokes[1]['id'], 'str_preexisting', reason: '已有 id 绝不重写');
      expect(strokes[0]['id'], isNot(strokes[1]['id']), reason: '派生 id 互不相同');
    });

    test('③ 缺迁移环节：停在当前版本，不抛出、不伪造推进', () {
      final sparse = DocumentMigrationRunner(
        supportedVersion: 5,
        migrations: kDocumentMigrations, // 缺 4→5
      );
      final envelope = _v1Envelope();
      expect(sparse.migrateToCurrent(envelope), 4, reason: '推进到有环节的顶即停');
      expect(envelope['version'], 4);
    });
  });

  group('codec 全链路', () {
    test('v1 信封经 decode：字段默认正确、id 派生、seed 维持每次新派生', () {
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(_v1Envelope())));
      final doc = const DocumentCodec().decode(bytes);

      expect(doc.id, 'doc_v1file');
      expect(doc.title, 'v1 遗留文件');
      expect(doc.textItems, isEmpty);
      final stroke = doc.layers.single.strokes.single;
      expect(stroke.version, 0);
      expect(stroke.points, hasLength(2));
      expect(stroke.id, isNotEmpty, reason: '迁移派生的 id 回读到文档');
      expect(stroke.seed, isNot(0), reason: 'v1 无 seed → 构造器派生新随机种子（历史行为）');
    });

    test('encode/decode 往返：id 保真，多笔 id 互不冲突', () {
      final doc = _v1Envelope(); // 借构造逻辑造多笔文档
      const codec = DocumentCodec();
      final strokes = doc['document']['layers'][0]['strokes'];
      for (var i = 0; i < 5; i++) {
        strokes.add({
          'points': [i * 1.0, i * 2.0, 0.5],
          'color': 255,
          'width': 1,
          'type': 'pen',
        });
      }
      final decoded = codec.decode(
        Uint8List.fromList(utf8.encode(jsonEncode(doc))),
      );
      final ids = decoded.layers.single.strokes.map((s) => s.id).toList();
      expect(ids, everyElement(isNotEmpty));
      expect(ids.toSet().length, ids.length, reason: '同批派生 id 全局唯一');

      final roundtripped = codec.decode(codec.encode(decoded));
      expect(
        roundtripped.layers.single.strokes.map((s) => s.id).toList(),
        ids,
        reason: 'encode/decode 往返 id 保真（跨会话稳定的前提）',
      );
    });

    test('注册表支持版本与 codec 单一来源一致', () {
      expect(kSupportedDocumentVersion, DocumentCodec.latestVersion);
      expect(kSupportedDocumentVersion, 4);
    });
  });
}
