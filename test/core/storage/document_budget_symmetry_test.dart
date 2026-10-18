// 批次 DN-003 回归测试（P0 数据丢失：解码静默截断 + 自动保存覆盖原件）。
//
// 缺陷回顾：`DocumentCodec` 只有**解码侧**有防御预算，超限静默截断（截笔、
// 整层丢弃、点列截短），而**编码侧一条上限都没有**。正常用户在一层画过 1 万笔
// 就能写出「自己都读不回来」的文件：重开时静默截断，`SaveScheduler` 的 5s 防抖
// 自动保存随即把截断后的内容覆盖到正式文件——真丢数据，用户全程无感。
//
// 本文件的四条验收用例：
//  1. 单层 10001 笔的文档：编码**显式失败**（绝不写出读不回的文件）；
//  2. 人为构造超限文件（直接拼 JSON 绕过编码器）：解码 report 的丢弃计数
//     **准确**，随后的保存在不完整态下**不会覆盖原件**（盘上字节仍是原始完整内容）；
//  3. 反向钉：合法规模文档（5 万点单笔、18 万点文档、恰好落满每个上限）
//     编码/解码/保存全程不受影响，report 表示完整；
//  4. 读写对称不变式：逐预算维度断言「编码器允许写出的最大值 ==
//     解码器能完整读回的最大值」，防止将来一侧再被调大。
//
// 守卫类用例按本仓纪律**双向都钉**（真超限确实被拦 / 合法文档不被误伤）。
//
// 与性能基线的关系（查实结论）：`test/performance/performance_baseline_test.dart`
// 的 B-4 用 1 万/5 万笔、B-1 用 10 万点单笔——它们**只构造内存对象做渲染/剔除
// 计时，从不落盘**（B-1 的 10 万点本身就越过 maxPointsPerStroke，属内存态合法
// 规模），故本批的编码侧上限不会打红它们；真正落盘的基线是 B-2（9000 笔 ×
// 20 点 = 18 万点）与根目录 `performance_baseline_test.dart`（1200 笔、
// 5 万点单笔），全部在预算之内，下方反向钉用例逐条复现其规模。
//
// 跑法：
//   NO_PROXY=127.0.0.1,localhost flutter test test/core/storage/document_budget_symmetry_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/layer.dart';
import 'package:drawing_notes_app/core/canvas_model/stroke.dart';
import 'package:drawing_notes_app/core/saving/save_scheduler.dart';
// 预算与解码完整性上报（document_budgets.dart）由 document_codec.dart 再导出
// （同一事实来源、少一份 core/storage 出向依赖），此处不再重复 import。
import 'package:drawing_notes_app/core/storage/document_codec.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';

import '../../helpers/temp_dir_cleanup.dart';

const DocumentCodec codec = DocumentCodec();

/// 内存文档：[layerCount] 层，每层 [strokeCount] 笔，每笔 [pointCount] 点。
DrawingDocument _document({
  required int strokeCount,
  int pointCount = 1,
  int layerCount = 1,
  String id = 'budget_doc',
}) {
  final layers = <Layer>[];
  for (var l = 0; l < layerCount; l++) {
    final layer = Layer(id: 'layer_$l', name: 'L$l');
    for (var i = 0; i < strokeCount; i++) {
      layer.strokes.add(
        Stroke(
          points: List<StrokePoint>.filled(
            pointCount,
            const StrokePoint(10, 20, 0.5),
          ),
          color: const Color(0xFF112233),
          width: 2,
          type: BrushType.pen,
        ),
      );
    }
    layers.add(layer);
  }
  return DrawingDocument(id: id, title: '预算对称', layers: layers);
}

// ---------------------------------------------------------------------------
// 直接拼 JSON 的「超限文件」构造器（绕过编码器——真实世界里这种文件来自
// 旧版本应用：那时编码侧还没有上限，写出的文件今天读不回）。
// ---------------------------------------------------------------------------

Map<String, dynamic> _rawStroke(int index, int pointCount) =>
    <String, dynamic>{
      'id': 's$index',
      // 扁平三元组格式（与 `Stroke.toJson` 一致）：n 个点 = 3n 个数值。
      'points': List<int>.filled(pointCount * 3, 7),
      'color': 0xFF112233,
      'width': 2,
      'type': 'pen',
      'opacity': 1,
      'seed': 1,
      'version': 0,
      'versionNonce': 0,
    };

Map<String, dynamic> _rawLayer(String id, List<int> strokePointCounts) =>
    <String, dynamic>{
      'id': id,
      'name': id,
      'visible': true,
      'opacity': 1,
      'strokes': <Map<String, dynamic>>[
        for (var i = 0; i < strokePointCounts.length; i++)
          _rawStroke(i, strokePointCounts[i]),
      ],
    };

List<Map<String, dynamic>> _rawShapes(int n) => <Map<String, dynamic>>[
  for (var i = 0; i < n; i++)
    <String, dynamic>{
      'id': 'sh$i',
      'shapeType': 'rect',
      'x': 1,
      'y': 1,
      'width': 10,
      'height': 10,
    },
];

List<Map<String, dynamic>> _rawImages(int n) => <Map<String, dynamic>>[
  for (var i = 0; i < n; i++)
    <String, dynamic>{
      'id': 'im$i',
      'x': 1,
      'y': 1,
      'width': 10,
      'height': 10,
      'filePath': '/managed/img$i.png',
    },
];

List<Map<String, dynamic>> _rawTexts(int n) => <Map<String, dynamic>>[
  for (var i = 0; i < n; i++)
    <String, dynamic>{
      'id': 'tx$i',
      'x': 1,
      'y': 1,
      'fontSize': 20,
      'text': 'hi$i',
    },
];

/// 把「每笔点数」列表按每层至多 [perLayer] 笔分块。
List<List<int>> _chunk(List<int> strokePointCounts, int perLayer) {
  final layers = <List<int>>[];
  for (var i = 0; i < strokePointCounts.length; i += perLayer) {
    final end = i + perLayer < strokePointCounts.length
        ? i + perLayer
        : strokePointCounts.length;
    layers.add(strokePointCounts.sublist(i, end));
  }
  return layers;
}

/// 把 [totalPoints] 摊到若干笔上，每笔至多 [perStrokeCap] 点。
List<int> _spreadPoints(int totalPoints, int perStrokeCap) {
  final counts = <int>[];
  var remaining = totalPoints;
  while (remaining > 0) {
    final inStroke = remaining > perStrokeCap ? perStrokeCap : remaining;
    counts.add(inStroke);
    remaining -= inStroke;
  }
  return counts;
}

/// 「每层的每笔点数」布局：让 [dimension] 恰好有 [size] 条，同时
/// **不越出其它维度**（否则先被别的预算拦掉，测不到目标维度）。
List<List<int>> _layoutFor(DocumentBudgetDimension dimension, int size) {
  switch (dimension) {
    case DocumentBudgetDimension.layerCount:
      return <List<int>>[for (var i = 0; i < size; i++) const <int>[1]];
    case DocumentBudgetDimension.strokesPerLayer:
      return <List<int>>[List<int>.filled(size, 1)];
    case DocumentBudgetDimension.pointsPerStroke:
      return <List<int>>[<int>[size]];
    case DocumentBudgetDimension.totalStrokes:
      return _chunk(List<int>.filled(size, 1), DocumentBudgets.maxStrokesPerLayer);
    case DocumentBudgetDimension.totalPoints:
      return _chunk(
        _spreadPoints(size, DocumentBudgets.maxPointsPerStroke),
        DocumentBudgets.maxStrokesPerLayer,
      );
    case DocumentBudgetDimension.shapeCount:
    case DocumentBudgetDimension.imageCount:
    case DocumentBudgetDimension.textCount:
      return <List<int>>[const <int>[1]];
  }
}

Map<String, dynamic> _envelopeOf({
  required String documentId,
  required List<List<int>> layout,
  int shapes = 0,
  int images = 0,
  int texts = 0,
}) => <String, dynamic>{
  'version': DocumentCodec.latestVersion,
  'document': <String, dynamic>{
    'id': documentId,
    'title': '超限文件',
    'width': 1024,
    'height': 768,
    'infinite': false,
    'paperType': 'blank',
    'folder': '',
    'layers': <Map<String, dynamic>>[
      for (var i = 0; i < layout.length; i++) _rawLayer('layer_$i', layout[i]),
    ],
    'shapes': _rawShapes(shapes),
    'imageItems': _rawImages(images),
    'textItems': _rawTexts(texts),
  },
};

/// 目标维度的「恰好 size 条」文件信封（与编码器输出同构）。
Map<String, dynamic> _envelopeFor(
  DocumentBudgetDimension dimension,
  int size,
  String documentId,
) => _envelopeOf(
  documentId: documentId,
  layout: _layoutFor(dimension, size),
  shapes: dimension == DocumentBudgetDimension.shapeCount ? size : 0,
  images: dimension == DocumentBudgetDimension.imageCount ? size : 0,
  texts: dimension == DocumentBudgetDimension.textCount ? size : 0,
);

Uint8List _bytesFor(
  DocumentBudgetDimension dimension,
  int size,
  String documentId,
) => _bytesOf(_envelopeFor(dimension, size, documentId));

Uint8List _bytesOf(Map<String, dynamic> envelope) => Uint8List.fromList(
  utf8.encode(jsonEncode(envelope)),
);

/// 指向 `documents/<id>.json`（与 StorageDirectories 的布局一致）。
Future<File> _docFile(Directory tempDir, String id) async {
  final dir = Directory('${tempDir.path}${Platform.pathSeparator}documents');
  if (!dir.existsSync()) await dir.create(recursive: true);
  return File('${dir.path}${Platform.pathSeparator}$id.json');
}

/// 预算异常匹配器：维度 + 上限 + 实际值 + 文档 id 四项都必须对得上。
Matcher _isBudgetRejection(
  DocumentBudgetDimension dimension, {
  required int actual,
  required String documentId,
}) => isA<DocumentBudgetException>()
    .having((e) => e.dimension, 'dimension', dimension)
    .having((e) => e.actual, 'actual', actual)
    .having((e) => e.limit, 'limit', dimension.limit)
    .having((e) => e.documentId, 'documentId', documentId)
    .having((e) => e.stage, 'stage', DocumentBudgetStage.encode);

Matcher _isDecodeViolation(DocumentBudgetDimension dimension, int actual) =>
    isA<DocumentBudgetException>()
        .having((e) => e.dimension, 'dimension', dimension)
        .having((e) => e.actual, 'actual', actual)
        .having((e) => e.limit, 'limit', dimension.limit)
        .having((e) => e.stage, 'stage', DocumentBudgetStage.decode);

/// 不真的等时间的定时器把手（记录退避排程与取消，绝不落下真 Timer）。
class _ManualTimer implements SaveTimerHandle {
  _ManualTimer(this.delay, this.callback);
  final Duration delay;
  final void Function() callback;
  int cancels = 0;
  @override
  void cancel() => cancels++;
}

class _ManualTimerBoard {
  final List<_ManualTimer> pending = <_ManualTimer>[];
  SaveTimerHandle create(Duration delay, void Function() callback) {
    final timer = _ManualTimer(delay, callback);
    pending.add(timer);
    return timer;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('budget_symmetry_');
  });
  tearDown(() async => deleteTempDirWithRetry(tempDir));

  StorageService makeStorage() =>
      StorageService(directoryProvider: () async => tempDir);

  // ======================================================================
  // 1. 编码侧显式失败
  // ======================================================================
  group('DN-003 编码侧预算对称拒绝', () {
    test('单层 10001 笔：编码显式失败（不是写出一个读不回来的文件）', () {
      final doc = _document(strokeCount: 10001, id: 'over_layer');

      expect(
        () => codec.encode(doc),
        throwsA(
          _isBudgetRejection(
            DocumentBudgetDimension.strokesPerLayer,
            actual: 10001,
            documentId: 'over_layer',
          ),
        ),
        reason: '过去这里会静默写下一个自己都读不回的文件',
      );
      // 快照阶段就在主线程、进入写尾队列之前失败（异常带归属维度，可诊断）。
      expect(
        () => DocumentCodec.snapshotOf(doc),
        throwsA(isA<DocumentBudgetException>()),
      );
      // 反向钉：恰好 10000 笔是合法规模，不得误伤。
      expect(
        () => codec.encode(_document(strokeCount: 10000, id: 'at_limit')),
        returnsNormally,
      );
    });

    test('存储层保存超预算文档：抛类型化异常且盘上不留半成品', () async {
      final storage = makeStorage();
      final id = 'over_save';
      final file = await _docFile(tempDir, id);

      await storage.save(_document(strokeCount: 3, id: id));
      final before = await file.readAsBytes();

      // 编码侧越界与写侧闸门都是**同步抛出**（在进入写尾队列之前，故不给
      // Future——`expect` + 闭包，而不是 `expectLater` + Future）。
      expect(
        () => storage.save(_document(strokeCount: 10001, id: id)),
        throwsA(
          _isBudgetRejection(
            DocumentBudgetDimension.strokesPerLayer,
            actual: 10001,
            documentId: id,
          ),
        ),
      );
      expect(
        await file.readAsBytes(),
        equals(before),
        reason: '被拒绝的保存不得触碰在档文件的一个字节',
      );
    });

    test('反向钉：既有落盘基线规模（18 万点 / 5 万点单笔 / 1200 笔）全放行', () {
      // 逐条对应 test/performance/performance_baseline_test.dart 的 B-2 与
      // 根目录 performance_baseline_test.dart 的两个用例——它们本来就落盘，
      // 新预算不得把它们打红。B-1/B-4 的 10 万点、5 万笔只做内存态渲染计时，
      // 不经编码路径（见文件头说明）。
      expect(
        () => codec.encode(_document(strokeCount: 9000, pointCount: 20)),
        returnsNormally,
      );
      expect(
        () => codec.encode(_document(strokeCount: 1, pointCount: 50000)),
        returnsNormally,
      );
      expect(
        () => codec.encode(_document(strokeCount: 1200, pointCount: 20)),
        returnsNormally,
      );
    });
  });

  // ======================================================================
  // 2. 解码完整性上报 + 禁止静默覆盖
  // ======================================================================
  group('DN-003 解码完整性上报', () {
    test('单层 10005 笔：report 精确报出被截断的 5 笔', () {
      final decoded = codec.decodeDetailed(
        _bytesFor(DocumentBudgetDimension.strokesPerLayer, 10005, 'rep_layer'),
      );
      final report = decoded.report;

      expect(report.documentId, 'rep_layer');
      expect(report.layersRestored, 1);
      expect(report.strokesRestored, DocumentBudgets.maxStrokesPerLayer);
      expect(report.pointsRestored, DocumentBudgets.maxStrokesPerLayer);
      expect(report.strokesDroppedByLayerBudget, 5);
      expect(report.strokesDroppedByGlobalBudget, 0);
      expect(report.strokesDroppedByBudget, 5);
      expect(report.invalidStrokesDropped, 0);
      expect(report.isBudgetTruncated, isTrue);
      expect(report.isComplete, isFalse);
      expect(
        report.budgetViolations,
        contains(
          _isDecodeViolation(DocumentBudgetDimension.strokesPerLayer, 10005),
        ),
      );
    });

    test('全局笔画预算：整层丢弃的层数/笔数/点数逐条计准', () {
      // 6 层 × 10000 笔 = 60000 笔 > maxTotalStrokes(50000)：
      // 前 5 层照常恢复，第 6 层**整层丢弃**。
      final decoded = codec.decodeDetailed(
        _bytesFor(DocumentBudgetDimension.totalStrokes, 60000, 'rep_global'),
      );
      final report = decoded.report;

      expect(report.layersRestored, 5);
      expect(report.strokesRestored, DocumentBudgets.maxTotalStrokes);
      expect(report.layersDroppedByGlobalBudget, 1);
      expect(report.strokesDroppedByGlobalBudget, 10000);
      expect(report.pointsDroppedByGlobalBudget, 10000);
      expect(report.strokesDroppedByLayerBudget, 0, reason: '单层并未越界');
      expect(report.isBudgetTruncated, isTrue);
      expect(
        report.budgetViolations.single.dimension,
        DocumentBudgetDimension.totalStrokes,
      );
      expect(report.budgetViolations.single.actual, 60000);
    });

    test('图层数/形状/图片/文字/单笔点列各自的丢弃计数', () {
      final layers = codec.decodeDetailed(
        _bytesFor(DocumentBudgetDimension.layerCount, 205, 'rep_layers'),
      ).report;
      expect(layers.layersRestored, DocumentBudgets.maxLayerCount);
      expect(layers.layersDroppedByCountBudget, 5);

      final shapes = codec.decodeDetailed(
        _bytesFor(DocumentBudgetDimension.shapeCount, 5005, 'rep_shapes'),
      ).report;
      expect(shapes.shapesRestored, DocumentBudgets.maxShapeCount);
      expect(shapes.shapesDroppedByCountBudget, 5);
      expect(shapes.objectsDroppedByBudget, 5);

      final images = codec.decodeDetailed(
        _bytesFor(DocumentBudgetDimension.imageCount, 5005, 'rep_images'),
      ).report;
      expect(images.imagesRestored, DocumentBudgets.maxImageCount);
      expect(images.imagesDroppedByCountBudget, 5);

      final texts = codec.decodeDetailed(
        _bytesFor(DocumentBudgetDimension.textCount, 5005, 'rep_texts'),
      ).report;
      expect(texts.textItemsRestored, DocumentBudgets.maxTextCount);
      expect(texts.textItemsDroppedByCountBudget, 5);

      // 单笔点列：50001 点声明 → 保留 50000、按预算丢 1。
      final points = codec.decodeDetailed(
        _bytesFor(
          DocumentBudgetDimension.pointsPerStroke,
          50001,
          'rep_points',
        ),
      ).report;
      expect(points.pointsRestored, DocumentBudgets.maxPointsPerStroke);
      expect(points.pointsDroppedByStrokeBudget, 1);
      expect(points.invalidPointsDropped, 0);
    });

    test('损坏剔除与预算截断永不混计（且损坏文档仍可保存修复）', () async {
      // 三条坏笔画（points 非列表 / 空点列 / 线宽越界）+ 一条好笔画。
      final bytes = _bytesOf(<String, dynamic>{
        'version': DocumentCodec.latestVersion,
        'document': <String, dynamic>{
          'id': 'rep_corrupt',
          'width': 1024,
          'height': 768,
          'layers': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'layer_0',
              'strokes': <Map<String, dynamic>>[
                _rawStroke(0, 2),
                <String, dynamic>{
                  'id': 'bad_a',
                  'points': 'not-a-list',
                  'color': 0xFF000000,
                  'width': 2,
                },
                <String, dynamic>{
                  'id': 'bad_b',
                  'points': <int>[],
                  'color': 0xFF000000,
                  'width': 2,
                },
                <String, dynamic>{
                  'id': 'bad_c',
                  'points': <int>[1, 1, 1],
                  'color': 0xFF000000,
                  'width': 999999,
                },
              ],
            },
          ],
        },
      });
      final report = codec.decodeDetailed(bytes).report;

      expect(report.strokesRestored, 1);
      expect(report.invalidStrokesDropped, 3);
      expect(report.strokesDroppedByBudget, 0);
      expect(report.isBudgetTruncated, isFalse);
      expect(report.isComplete, isFalse);
      expect(report.budgetViolations, isEmpty);

      // 反向钉：**只有预算截断才拦覆盖**。损坏/危险几何走的是既有「修复式
      // 回读」，保存应当成功（否则本批会把既有修复路径一并堵死）。
      final storage = makeStorage();
      final id = 'rep_corrupt';
      await (await _docFile(tempDir, id)).writeAsBytes(bytes);
      final loaded = await storage.load(id);
      expect(loaded, isNotNull);
      expect(storage.isLoadedWithBudgetTruncation(id), isFalse);
      await expectLater(storage.save(loaded!), completes);
    });
  });

  group('DN-003 禁止静默覆盖不完整文档', () {
    test('以截断态打开的文档：保存不得覆盖原件（盘上仍是原始完整内容）', () async {
      final storage = makeStorage();
      const id = 'truncated_doc';
      const strokesInFile = DocumentBudgets.maxStrokesPerLayer + 7;
      final original = _bytesFor(
        DocumentBudgetDimension.strokesPerLayer,
        strokesInFile,
        id,
      );
      final file = await _docFile(tempDir, id);
      await file.writeAsBytes(original);

      final loaded = await storage.load(id);
      expect(loaded, isNotNull);
      expect(
        loaded!.layers.single.strokes.length,
        DocumentBudgets.maxStrokesPerLayer,
      );
      expect(storage.isLoadedWithBudgetTruncation(id), isTrue);
      expect(
        storage.budgetTruncationReport(id)!.strokesDroppedByBudget,
        7,
      );

      // 同步抛出（见 StorageService.save 的契约）——用闭包断言。
      expect(
        () => storage.save(loaded),
        throwsA(
          isA<DocumentIncompleteLoadException>()
              .having((e) => e.documentId, 'documentId', id)
              .having(
                (e) => e.report.strokesDroppedByBudget,
                'report.strokesDroppedByBudget',
                7,
              ),
        ),
      );

      // 盘上字节逐字未变，且那份「更完整的原件」仍然带着全部 10007 笔。
      final after = await file.readAsBytes();
      expect(after, equals(original));
      final strokesOnDisk =
          ((jsonDecode(utf8.decode(
                    after,
                  )) as Map<String, dynamic>)['document']
              as Map<String, dynamic>)['layers'] as List;
      expect(
        (strokesOnDisk.single as Map<String, dynamic>)['strokes'] as List,
        hasLength(strokesInFile),
        reason: '原始完整内容必须仍在盘上',
      );
      expect(codec.decodeDetailed(after).report.strokesDroppedByLayerBudget, 7);

      // 显式处置（唯一的放行出口）之后才允许覆盖。
      storage.acknowledgeBudgetTruncation(id);
      expect(storage.isLoadedWithBudgetTruncation(id), isFalse);
      await expectLater(storage.save(loaded), completes);
      expect(await file.readAsBytes(), isNot(equals(original)));
    });

    test('闸门失效路径：重新以完整态打开即自动解除', () async {
      final storage = makeStorage();
      const id = 'guard_lifecycle';
      final file = await _docFile(tempDir, id);
      await file.writeAsBytes(
        _bytesFor(
          DocumentBudgetDimension.strokesPerLayer,
          DocumentBudgets.maxStrokesPerLayer + 1,
          id,
        ),
      );

      await storage.load(id);
      expect(storage.isLoadedWithBudgetTruncation(id), isTrue);

      // 盘上换成合法文件后重新打开——闸门必须自动失效，保存恢复正常。
      await file.writeAsBytes(
        _bytesFor(DocumentBudgetDimension.strokesPerLayer, 10, id),
      );
      final fresh = await storage.load(id);
      expect(storage.isLoadedWithBudgetTruncation(id), isFalse);
      await expectLater(storage.save(fresh!), completes);
    });

    test('删除失败的文档不得解除闸门', () async {
      final storage = makeStorage();
      const id = 'guard_delete';
      await (await _docFile(tempDir, id)).writeAsBytes(
        _bytesFor(
          DocumentBudgetDimension.strokesPerLayer,
          DocumentBudgets.maxStrokesPerLayer + 2,
          id,
        ),
      );
      await storage.load(id);
      expect(storage.isLoadedWithBudgetTruncation(id), isTrue);

      // 文件不存在时 delete 返回 false，闸门必须继续生效。
      expect(await storage.delete('never_loaded_doc'), isFalse);
      expect(storage.isLoadedWithBudgetTruncation(id), isTrue);

      // 真删除成功后闸门解除。
      expect(await storage.delete(id), isTrue);
      expect(storage.isLoadedWithBudgetTruncation(id), isFalse);
    });

    test('不完整态异常沿 SaveScheduler 既有可见化链路挂出，不沦为静默', () async {
      final storage = makeStorage();
      const id = 'truncated_visible';
      await (await _docFile(tempDir, id)).writeAsBytes(
        _bytesFor(
          DocumentBudgetDimension.strokesPerLayer,
          DocumentBudgets.maxStrokesPerLayer + 3,
          id,
        ),
      );
      final doc = await storage.load(id);

      final board = _ManualTimerBoard();
      var attempts = 0;
      final scheduler = SaveScheduler(
        save: () async {
          attempts++;
          await storage.save(doc!);
        },
        timerFactory: board.create,
      );

      final result = await scheduler.saveNow();

      // DN-005：闸门拒绝必须能在**返回值**上被退出点读到——只挂 notifier 的话，
      // `await saveNow()` 正常返回会被调用方读成「已落盘」，于是退出即静默丢改动。
      expect(
        result.outcome,
        SaveFlushOutcome.failedStillDirty,
        reason: '被拒绝的覆盖写不得伪装成已落盘',
      );
      expect(result.isSafeToLeave, isFalse);
      expect(attempts, greaterThanOrEqualTo(2), reason: '调度器确实重试过');
      expect(
        scheduler.saveFailure.value,
        isNotNull,
        reason: '拒绝必须走既有 saveFailure 可见化（顶栏/状态栏/snackbar）',
      );
      expect(
        scheduler.saveFailure.value!.errorKind,
        'document_incomplete_load',
        reason: '只带 `errorCode()` 推的类型代码（R50 起不再是 runtimeType），'
            '异常 message 不得外带（H-04）',
      );
      expect(
        scheduler.isDirty,
        isTrue,
        reason: '内存里的编辑不得因写侧拒绝而被当作已落盘丢弃',
      );
      expect(
        (await _docFile(tempDir, id)).readAsBytesSync(),
        isNotEmpty,
        reason: '被拒绝的两轮自动保存没能在盘上留下任何覆盖',
      );
      scheduler.dispose();
      expect(
        board.pending,
        isNotEmpty,
        reason: '退避走的是注入的定时器板（不落下真 5s Timer）',
      );
      expect(
        board.pending.single.cancels,
        1,
        reason: 'dispose 必须取消尚未到点的退避定时器',
      );
    });

    test('反向钉：完整态打开的文档自动保存照常覆盖（闸门不误伤）', () async {
      final storage = makeStorage();
      const id = 'complete_doc';
      await (await _docFile(tempDir, id)).writeAsBytes(
        _bytesFor(DocumentBudgetDimension.strokesPerLayer, 50, id),
      );
      final doc = await storage.load(id);
      expect(storage.isLoadedWithBudgetTruncation(id), isFalse);
      doc!.title = '改过了';
      await expectLater(storage.save(doc), completes);
      final reread = await storage.load(id);
      expect(reread!.title, '改过了');
      expect(storage.isLoadedWithBudgetTruncation(id), isFalse);
    });
  });

  // ======================================================================
  // 3. 反向钉：合法规模全程不受影响
  // ======================================================================
  group('DN-003 反向钉：合法文档不被误伤', () {
    test('5 万点单笔（上限边界）：编码/解码/保存全程放行且 report 完整', () async {
      final doc = _document(
        strokeCount: 1,
        pointCount: DocumentBudgets.maxPointsPerStroke,
        id: 'big_stroke',
      );
      final decoded = codec.decodeDetailed(codec.encode(doc));
      expect(
        decoded.document.layers.single.strokes.single.points.length,
        DocumentBudgets.maxPointsPerStroke,
      );
      expect(decoded.report.isComplete, isTrue);
      expect(decoded.report.budgetViolations, isEmpty);

      final storage = makeStorage();
      await expectLater(storage.save(doc), completes);
      final loaded = await storage.load('big_stroke');
      expect(
        loaded!.layers.single.strokes.single.points.length,
        DocumentBudgets.maxPointsPerStroke,
      );
      expect(storage.isLoadedWithBudgetTruncation('big_stroke'), isFalse);
    });

    test('18 万点文档（性能基线 B-2 规模）：往返完整、report 无丢弃', () {
      final decoded = codec.decodeDetailed(
        codec.encode(_document(strokeCount: 9000, pointCount: 20, id: 'b2')),
      );
      expect(decoded.report.strokesRestored, 9000);
      expect(decoded.report.pointsRestored, 180000);
      expect(decoded.report.isComplete, isTrue, reason: '既有基线不得被新预算打红');
    });

    test('既有宽容回读拒绝语义原样保留（高版本 / 非法根结构 / 非法 ID）', () {
      expect(
        () => codec.decode(
          _bytesOf(<String, dynamic>{
            'version': DocumentCodec.latestVersion + 1,
            'document': <String, dynamic>{'id': 'new'},
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => codec.decode(Uint8List.fromList(utf8.encode('[]'))),
        throwsFormatException,
      );
      expect(
        () => codec.decode(
          _bytesOf(<String, dynamic>{
            'version': 3,
            'document': <String, dynamic>{'id': '../unsafe'},
          }),
        ),
        throwsFormatException,
      );
      // 100MB 入口预检：阈值是本批明文钉住的既有语义，不得被调大来「让东西
      // 变绿」。刻意不做 `Uint8List(maxFileBytes + 1)` 的真越界物化——那要在
      // CI 上一次性申请 100MB 堆，代价大于收益；`decodeDetailed` 里
      // `bytes.length > DocumentBudgets.maxFileBytes` 这条比较由下方源码
      // 断言与常量锁共同守住。
      expect(DocumentBudgets.maxFileBytes, 100 * 1024 * 1024);
      expect(
        utf8.decode(
          codec.encode(_document(strokeCount: 2, id: 'just_under_precheck')),
        ),
        contains('"version"'),
        reason: '预检之下的正常文件照常可解（反向钉）',
      );
    });
  });

  // ======================================================================
  // 4. 读写对称不变式
  // ======================================================================
  group('DN-003 读写对称不变式', () {
    test('逐维度：编码器允许写出的最大值 == 解码器完整读回的最大值', () {
      for (final dimension in DocumentBudgetDimension.values) {
        final limit = dimension.limit;
        // ① 恰好等于上限：编码侧必须放行。
        expect(
          () => DocumentCodec.validateSnapshotForEncoding(
            _envelopeFor(dimension, limit, 'invariant'),
          ),
          returnsNormally,
          reason: '${dimension.name}：编码器不得拒绝自己声称允许的最大值',
        );
        // ② 超限 1 条：编码侧必须拒绝，且报的就是这个维度、这个上限。
        expect(
          () => DocumentCodec.validateSnapshotForEncoding(
            _envelopeFor(dimension, limit + 1, 'invariant'),
          ),
          throwsA(
            _isBudgetRejection(
              dimension,
              actual: limit + 1,
              documentId: 'invariant',
            ),
          ),
          reason: '${dimension.name}：编码器写出的东西必须读得回来',
        );
        // ③ 解码侧在恰好上限处必须完整读回（同一数字，不留 off-by-one 缝隙）。
        //    totalPoints 的 100 万点物化交给下面的专用用例——本循环为验证
        //    一条比较运算要解析 3M 个 JSON 数值，不值得在这里拖垮整个套件。
        if (dimension == DocumentBudgetDimension.totalPoints) continue;
        final atLimit = codec.decodeDetailed(
          _bytesFor(dimension, limit, 'invariant'),
        );
        expect(
          atLimit.report.isComplete,
          isTrue,
          reason: '${dimension.name}：上限内的合法内容必须一条不落地读回来',
        );
        // ④ 解码侧超限确实截断（证明这个上限是真实存在的路径，不是摆设）。
        final overLimit = codec.decodeDetailed(
          _bytesFor(dimension, limit + 1, 'invariant'),
        );
        expect(
          overLimit.report.isBudgetTruncated,
          isTrue,
          reason: '${dimension.name}：越界必须被截断——所以编码侧必须拒绝',
        );
      }
    });

    test('不变式对「两侧引用同一组常量」本身也钉死', () {
      expect(DocumentBudgetDimension.values.length, 8);
      for (final dimension in DocumentBudgetDimension.values) {
        expect(dimension.limit, greaterThan(0));
      }
      // 单一事实来源：阈值一个都不许被调大来「让东西变绿」。
      expect(DocumentBudgets.maxLayerCount, 200);
      expect(DocumentBudgets.maxStrokesPerLayer, 10000);
      expect(DocumentBudgets.maxPointsPerStroke, 50000);
      expect(DocumentBudgets.maxTotalStrokes, 50000);
      expect(DocumentBudgets.maxTotalPoints, 1000000);
      expect(DocumentBudgets.maxShapeCount, 5000);
      expect(DocumentBudgets.maxImageCount, 5000);
      expect(DocumentBudgets.maxTextCount, 5000);
    });

    test('全局点数预算边界：恰好 100 万点全数读回，越界那条起整层丢弃', () {
      // maxTotalPoints = 1,000,000：21 层 × 每层 1 笔 × 5 万点。
      // 前 20 层累计恰好 100 万点（全部保留，即「上限内完整读回」方向），
      // 第 21 层越界 ⇒ 整层丢弃（即「越界确实截断」方向）。
      final decoded = codec.decodeDetailed(
        _bytesOf(_envelopeOf(
          documentId: 'big_points',
          layout: <List<int>>[
            for (var i = 0; i < 21; i++) <int>[DocumentBudgets.maxPointsPerStroke],
          ],
        )),
      );
      final report = decoded.report;

      expect(report.pointsRestored, DocumentBudgets.maxTotalPoints);
      expect(report.layersRestored, 20);
      expect(report.layersDroppedByGlobalBudget, 1);
      expect(report.pointsDroppedByGlobalBudget, 50000);
      expect(report.isBudgetTruncated, isTrue);
      expect(
        report.budgetViolations.single.dimension,
        DocumentBudgetDimension.totalPoints,
      );
    }, timeout: const Timeout(Duration(minutes: 4)));
  });
}
