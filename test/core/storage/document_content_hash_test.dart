// H1 修复回归：文档本体的整体校验和（contentHash）。
//
// 修复前的现状是「明文模式下文档本体零检测」：位翻转、静默截断、部分写入
// 都能读起来正常，等用户发现笔画少了已经来不及（加密文档由保险库 AEAD 的
// MAC 兼着，明文文档没有任何东西兼着）。
//
// 本文件锁三件事：
//  ① 编码器真的写 contentHash，且它是 document 子树的规范化 SHA-256；
//  ② 规范化是**内容级**的（键序无关、int/double 表示无关、不受 version 影响），
//     不会因为格式/类型漂移把完好文件误判成损坏；
//  ③ 校验和真的能挡住宿扰——codec 层拒绝，StorageService 层回退 `.bak`。
//
// 向后兼容单独一条：旧文档没有 contentHash 时必须照常打开（本仓明令禁止
// 「升级即打不开旧数据」）。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/core/storage/document_codec.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir_cleanup.dart';

DrawingDocument _doc(String id, {String title = '标题'}) {
  final layer = Layer(id: 'layer_1', name: '');
  layer.strokes.add(
    Stroke(
      id: 'str_1',
      points: const [StrokePoint(10, 20, 1), StrokePoint(30, 40, 0.5)],
      color: const Color(0xFF000000),
      width: 2,
      type: BrushType.pen,
    ),
  );
  return DrawingDocument(id: id, title: title, layers: [layer]);
}

Map<String, dynamic> _decodeJson(Uint8List bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

/// encode/decode 是实例方法（encodeSnapshot/computeContentHash 是静态）。
const DocumentCodec _codec = DocumentCodec();

void main() {
  group('DocumentCodec contentHash 编码侧', () {
    test('落盘 JSON 带 contentHash，且等于 document 子树的规范化哈希', () {
      final bytes = _codec.encode(_doc('hash_doc'));
      final map = _decodeJson(bytes);

      expect(map[DocumentCodec.contentHashField], isA<String>());
      final stored = map[DocumentCodec.contentHashField] as String;
      expect(stored, hasLength(64)); // SHA-256 hex
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(stored), isTrue);

      final recomputed = DocumentCodec.computeContentHash(map['document']);
      expect(recomputed, stored);
    });

    test('encode → decode 往返：文档内容不变', () {
      final doc = _doc('hash_roundtrip', title: '往返标题');
      final restored = _codec.decode(_codec.encode(doc));

      expect(restored.id, doc.id);
      expect(restored.title, '往返标题');
      expect(restored.layers.single.strokes.single.points.first.x, 10);
    });

    test('同一文档两次编码得到同一 contentHash（确定性）', () {
      final doc = _doc('hash_det');
      final a = _decodeJson(_codec.encode(doc));
      final b = _decodeJson(_codec.encode(doc));
      expect(a[DocumentCodec.contentHashField], b[DocumentCodec.contentHashField]);
    });

    test('规范化：键序无关（同一内容不同插入序 → 同一哈希）', () {
      final a = DocumentCodec.computeContentHash({
        'b': 2,
        'a': {'d': 4, 'c': 3},
      });
      final b = DocumentCodec.computeContentHash({
        'a': {'c': 3, 'd': 4},
        'b': 2,
      });
      expect(a, b);
    });

    test('规范化：int/double 表示无关（2048 与 2048.0 同一内容）', () {
      final a = DocumentCodec.computeContentHash({
        'width': 2048,
        'nested': [
          {'x': 10.0},
        ],
      });
      final b = DocumentCodec.computeContentHash({
        'width': 2048.0,
        'nested': [
          {'x': 10},
        ],
      });
      expect(a, b);
    });

    test('contentHash 不受 version 字段影响（哈希对象只是 document 子树）', () {
      final document = <String, dynamic>{'id': 'v', 'title': 't'};
      final v4 = _decodeJson(
        DocumentCodec.encodeSnapshot({'version': 4, 'document': document}),
      );
      final v3 = _decodeJson(
        DocumentCodec.encodeSnapshot({'version': 3, 'document': document}),
      );
      expect(
        v4[DocumentCodec.contentHashField],
        v3[DocumentCodec.contentHashField],
      );
    });
  });

  group('DocumentCodec contentHash 解码侧', () {
    test('向后兼容：旧文档没有 contentHash → 照常打开', () {
      final bytes = _codec.encode(_doc('hash_legacy'));
      final map = _decodeJson(bytes);
      map.remove(DocumentCodec.contentHashField);

      final restored = _codec.decode(
        Uint8List.fromList(utf8.encode(jsonEncode(map))),
      );
      expect(restored.id, 'hash_legacy');
      expect(restored.layers.single.strokes, hasLength(1));
    });

    test('向后兼容：contentHash 为空串 → 视为无校验和，照常打开', () {
      final bytes = _codec.encode(_doc('hash_empty'));
      final map = _decodeJson(bytes);
      map[DocumentCodec.contentHashField] = '';

      final restored = _codec.decode(
        Uint8List.fromList(utf8.encode(jsonEncode(map))),
      );
      expect(restored.id, 'hash_empty');
    });

    test('防篡改：改了内容但留着旧哈希 → 拒绝打开', () {
      final bytes = _codec.encode(_doc('hash_tamper', title: '原始'));
      final map = _decodeJson(bytes);
      (map['document'] as Map<String, dynamic>)['title'] = '被篡改';

      expect(
        () => _codec.decode(
          Uint8List.fromList(utf8.encode(jsonEncode(map))),
        ),
        throwsFormatException,
      );
    });

    test('防篡改：笔画坐标被改（位翻转语义）→ 拒绝打开', () {
      final bytes = _codec.encode(_doc('hash_bitflip'));
      final map = _decodeJson(bytes);
      final strokes =
          ((map['document'] as Map<String, dynamic>)['layers'] as List)
              .first as Map<String, dynamic>;
      final points = (strokes['strokes'] as List).first
          as Map<String, dynamic>;
      // 扁平三元组 [x, y, p] 的第一个坐标 10 → 11。
      (points['points'] as List)[0] = 11;

      expect(
        () => _codec.decode(
          Uint8List.fromList(utf8.encode(jsonEncode(map))),
        ),
        throwsFormatException,
      );
    });

    test('防篡改：改了哈希本身 → 拒绝打开', () {
      final bytes = _codec.encode(_doc('hash_hash'));
      final map = _decodeJson(bytes);
      map[DocumentCodec.contentHashField] = 'f' * 64;

      expect(
        () => _codec.decode(
          Uint8List.fromList(utf8.encode(jsonEncode(map))),
        ),
        throwsFormatException,
      );
    });

    test('防篡改：拒绝的是 FormatException（StorageService 据此回退 .bak）', () {
      final bytes = _codec.encode(_doc('hash_type'));
      final map = _decodeJson(bytes);
      (map['document'] as Map<String, dynamic>)['title'] = 'x';

      expect(
        () => _codec.decode(
          Uint8List.fromList(utf8.encode(jsonEncode(map))),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('StorageService contentHash 端到端（明文模式）', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('document_hash_');
    });

    tearDown(() async {
      try {
        await deleteTempDirWithRetry(tempDir);
      } catch (_) {}
    });

    String docPath(String id) =>
        '${tempDir.path}${Platform.pathSeparator}documents'
        '${Platform.pathSeparator}$id.json';

    StorageService plaintextService() => StorageService(
      directoryProvider: () async => tempDir,
    );

    test('明文保存的文档确实带 contentHash', () async {
      final storage = plaintextService();
      await storage.save(_doc('hash_plain'));

      final map = _decodeJson(await File(docPath('hash_plain')).readAsBytes());
      expect(map[DocumentCodec.contentHashField], isA<String>());
    });

    test('主文件被语义篡改 → 回退 .bak 取回到完好那一版', () async {
      final storage = plaintextService();
      await storage.save(_doc('hash_bak', title: '原始标题'));

      // 把完好的一份放进 .bak（模拟「上一版备份」）。
      final good = await File(docPath('hash_bak')).readAsBytes();
      await File('${docPath('hash_bak')}.bak').writeAsBytes(good);

      // 主文件：JSON 仍然合法，但标题被改（contentHash 没跟着改）——
      // 这正是旧实现完全检测不到的一类损坏。
      final map = _decodeJson(good);
      (map['document'] as Map<String, dynamic>)['title'] = '被篡改的标题';
      await File(docPath('hash_bak')).writeAsBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(map))),
      );

      final loaded = await storage.load('hash_bak');

      expect(loaded, isNotNull, reason: '主文件校验和不符时必须回退 .bak');
      expect(loaded!.title, '原始标题', reason: '.bak 那一版未被篡改');
    });

    test('主文件篡改且无 .bak → 抛出（拒绝打开，不静默返回半成品）', () async {
      final storage = plaintextService();
      await storage.save(_doc('hash_no_bak', title: '原始标题'));

      final map = _decodeJson(await File(docPath('hash_no_bak')).readAsBytes());
      (map['document'] as Map<String, dynamic>)['title'] = '被篡改';
      await File(docPath('hash_no_bak')).writeAsBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(map))),
      );

      expect(
        () => storage.load('hash_no_bak'),
        throwsA(isA<FormatException>()),
        reason: '无备份可回退时必须把损坏如实抛给调用方',
      );
    });

    test('完好的主文件正常打开（校验和不是摆设，也不误伤）', () async {
      final storage = plaintextService();
      await storage.save(_doc('hash_ok', title: '完好标题'));

      final loaded = await storage.load('hash_ok');

      expect(loaded, isNotNull);
      expect(loaded!.title, '完好标题');
    });
  });
}
