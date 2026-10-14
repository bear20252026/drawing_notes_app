// Spike C 的重放一致性（桌面端一侧）。
//
// 与网页版 `drawing_notes_web/tools/replay/check.mjs` 跑同一批
// `test/fixtures/v3/replay-*.json` 与同一份 `replay-manifest.json`（跨仓逐字节比对由
// 网页侧 runner 负责）。每个用例断言三个摘要：初始、正向重放、逆序回退之后。
// 任一侧改坏 op 粒度、寻址方式、默认值口径或插入位置，两端就同时变红。
//
// 刻意的不对称记在 `replay-manifest.json` 的 notes 与 roadmap §7：异常**类型**与
// 消息文本两端不同（Dart `StateError`/`FormatException` vs TS `Error`/`TypeError`），
// 这里只断言「抛/不抛」与「抛完之后文档的形状」。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/operation/document_operation.dart';
import 'package:drawing_notes_app/core/storage/document_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import 'replay_canonical.dart';

const String _dir = 'test/fixtures/v3';
const DocumentCodec _codec = DocumentCodec();

Map<String, dynamic> _json(String relative) =>
    jsonDecode(utf8.decode(File('$_dir/$relative').readAsBytesSync()))
        as Map<String, dynamic>;

/// 每次都要新鲜解码：apply/revert 就地改文档，同一个 doc 跑两遍会串味。
DrawingDocument _fresh(Map<String, dynamic> envelope) =>
    _codec.decode(Uint8List.fromList(utf8.encode(jsonEncode(envelope))));

List<DocumentOperation> _ops(List<dynamic> raw) => [
  for (final op in raw)
    DocumentOperation.fromJson(Map<String, dynamic>.from(op as Map)),
];

void main() {
  final manifest = _json('replay-manifest.json');

  test('摘要规格与清单同一份', () {
    expect(manifest['digestSpec'], digestSpec);
  });

  for (final item in (manifest['cases'] as List).cast<Map<String, dynamic>>()) {
    final file = item['file'] as String;
    final data = _json(file);
    final envelope = Map<String, dynamic>.from(data['doc'] as Map);
    final want = Map<String, dynamic>.from(data['expect'] as Map);
    final ops = data['ops'];

    group(file, () {
      test('初始状态两端同一（顺带钉住整份解码那条宽容腿）', () {
        expect(stateDigest(_fresh(envelope)), want['digestBefore']);
      });

      if (ops is List) {
        test('toJson/fromJson 往返闭合', () {
          final parsed = _ops(ops);
          for (var i = 0; i < parsed.length; i++) {
            final again = DocumentOperation.fromJson(parsed[i].toJson());
            expect(
              jsonEncode(again.toJson()),
              jsonEncode(parsed[i].toJson()),
              reason: '第 $i 条操作往返不闭合',
            );
          }
        });

        test('正向重放', () {
          final doc = _fresh(envelope);
          for (final op in _ops(ops)) {
            op.apply(doc);
          }
          expect(stateDigest(doc), want['digestAfter']);
        });

        test('逆序回退', () {
          final doc = _fresh(envelope);
          final parsed = _ops(ops);
          for (final op in parsed) {
            op.apply(doc);
          }
          for (final op in parsed.reversed) {
            op.revert(doc);
          }
          expect(stateDigest(doc), want['digestRestored']);
        });
      }

      final badOps = data['badOps'];
      if (badOps is List) {
        for (var i = 0; i < badOps.length; i++) {
          final bad = Map<String, dynamic>.from(badOps[i] as Map);
          test('拒绝：${bad['why']}', () {
            final doc = _fresh(envelope);
            var threw = false;
            try {
              DocumentOperation.fromJson(
                Map<String, dynamic>.from(bad['op'] as Map),
              ).apply(doc);
            } catch (_) {
              threw = true;
            }
            expect(threw, isTrue, reason: '应抛，但应用成功了');
            final after = bad['digestAfterError'];
            if (after is String) {
              expect(stateDigest(doc), after, reason: '抛完之后文档形状两端不同');
            }
          });
        }
      }
    });
  }
}
