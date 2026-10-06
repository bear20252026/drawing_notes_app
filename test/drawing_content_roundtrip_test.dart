// 交接文档（2026-10-05）第二优先：真实落盘的用户流程回归。
//
// 为什么另开这份：`integration_test/feature_test.dart` 里的用例名声称覆盖
// 绘制 / 撤销 / 重做 / 图层 / 保存，但断言实际只到「界面没抛异常」，而且它的
// 存储目录是 `directoryProvider: () async => throw UnimplementedError()`
// （feature_test.dart:42）——「画完的内容真的落盘、关掉重开还在」这条链路
// 此前一条断言都没有。本文件用真实临时目录把每一步的**内容**核一遍：
// `toJson` 就是落盘形态，比较它 = 比较磁盘上的内容。
//
// 设备端集成测试（入口 + 完整交互）是这条链路的下一段，不在本文件口径内。

import 'dart:convert';
import 'dart:io';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/storage/repository.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/temp_dir_cleanup.dart';

/// 内容指纹：用户可见的数据字段全取，逐层逐笔到每个点。
///
/// 不含 `updatedAt`——它按设计在每次变更时递增（`touch()`），把它算进
/// 「撤销后应等于撤销前」这类断言里只会得到假红。时间戳的往返另有专门断言。
String contentOf(DrawingDocument d) => jsonEncode({
  'id': d.id,
  'title': d.title,
  'width': d.width,
  'height': d.height,
  'infinite': d.infinite,
  'paperType': d.paperType.name,
  'folder': d.folder,
  'createdAt': d.createdAt.toIso8601String(),
  'layers': d.layers.map((l) => l.toJson()).toList(),
  'shapes': d.shapes.map((s) => s.toJson()).toList(),
  'imageItems': d.imageItems.map((i) => i.toJson()).toList(),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DocumentRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('drawing_roundtrip_');
    repo = StorageService(directoryProvider: () async => tempDir);
  });
  tearDown(() async => deleteTempDirWithRetry(tempDir));

  DrawingController newController(String id) => DrawingController(
    DrawingDocument(id: id, title: '往返', width: 240, height: 200),
  );

  /// 走真实输入链路画一笔（起点 → 两段延伸 → 结算），不直接往图层塞数据。
  Future<void> draw(DrawingController c, double x) async {
    c.startStroke(Offset(x, 40));
    c.extendStroke(Offset(x + 12, 52));
    c.extendStroke(Offset(x + 24, 64));
    await c.endStroke();
  }

  List<Offset> pointsOf(DrawingDocument d, int layer, int stroke) => [
    for (final p in d.layers[layer].strokes[stroke].points) p.offset,
  ];

  test('绘制→撤销→重做：每一步核对真实内容，而不是「没抛异常」', () async {
    final c = newController('draw_undo');
    addTearDown(c.dispose);

    await draw(c, 10);
    expect(c.document.layers.first.strokes.length, 1);
    expect(pointsOf(c.document, 0, 0).first, const Offset(10, 40));
    final oneStroke = contentOf(c.document);

    await draw(c, 100);
    expect(c.document.layers.first.strokes.length, 2);
    final twoStrokes = contentOf(c.document);

    c.undo();
    expect(
      contentOf(c.document),
      oneStroke,
      reason: '撤销后必须逐点回到只有一笔的内容',
    );

    c.undo();
    expect(c.document.layers.first.strokes, isEmpty);
    expect(c.canRedo, isTrue);

    c.redo();
    expect(contentOf(c.document), oneStroke);
    c.redo();
    expect(
      contentOf(c.document),
      twoStrokes,
      reason: '重做必须逐点恢复，不是只把笔画数量补回去',
    );
    expect(c.canRedo, isFalse, reason: '已重做到顶，不该还有可重做的尾巴');
  });

  test('保存→关闭控制器→重新读取：磁盘内容逐字段等于关闭前', () async {
    final c = newController('roundtrip');
    await draw(c, 10);
    c.addLayer(name: '第二层');
    await draw(c, 100); // addLayer 自动选中新层
    final beforeSave = contentOf(c.document);
    final c0CreatedAt = c.document.createdAt.toIso8601String();
    final c0UpdatedAt = c.document.updatedAt.toIso8601String();
    final firstStroke = c.document.layers.first.strokes.first;
    final c0Seed = firstStroke.seed;
    final c0Version = firstStroke.version;
    final c0VersionNonce = firstStroke.versionNonce;

    final path = await repo.save(c.document);
    c.markSaved();
    expect(File(path).existsSync(), isTrue, reason: 'save 必须真的产出磁盘文件');
    expect(File(path).lengthSync(), greaterThan(0));
    c.dispose();

    final reloaded = await repo.load('roundtrip');
    expect(reloaded, isNotNull);
    expect(contentOf(reloaded!), beforeSave);
    // 时间戳：createdAt 必须原样回来，updatedAt 必须是落盘那一刻的值
    //（备份与同步按更新时间排序，重开后说谎就是排序说谎）。
    expect(reloaded.createdAt.toIso8601String(), c0CreatedAt);
    expect(reloaded.updatedAt.toIso8601String(), c0UpdatedAt);
    // 手绘抖动种子与元素版本必须原样回来：丢了 seed 会让同一条笔画在重开后
    // 换一套抖动（用户看到的「画面自己变了」），丢了 version 会让协作冲突检测失效。
    expect(
      reloaded.layers.first.strokes.first.seed,
      c0Seed,
      reason: '笔画 seed 必须随文档往返，重开后质感与抖动不得改变',
    );
    expect(reloaded.layers.first.strokes.first.version, c0Version);
    expect(reloaded.layers.first.strokes.first.versionNonce, c0VersionNonce);

    final reopened = DrawingController(reloaded);
    addTearDown(reopened.dispose);
    expect(reopened.document.layers.map((l) => l.name).toList(), ['', '第二层']);
    expect(reopened.document.layers[0].strokes.length, 1);
    expect(reopened.document.layers[1].strokes.length, 1);
    expect(pointsOf(reopened.document, 1, 0).first, const Offset(100, 40));
    expect(
      reopened.isDirty,
      isFalse,
      reason: '刚重开的文档不该被判成未保存（否则关闭时会多写一次盘）',
    );
    expect(
      reopened.canUndo,
      isFalse,
      reason: '重开不得带着上一世的撤销栈',
    );
  });

  test('撤销后保存：落盘的是撤销后的内容，被撤销的笔画不得复活', () async {
    final c = newController('undo_then_save');
    await draw(c, 10);
    await draw(c, 100);
    c.undo();
    final afterUndo = contentOf(c.document);

    await repo.save(c.document);
    c.dispose();

    final reloaded = await repo.load('undo_then_save');
    final afterUndoReload = reloaded!;
    expect(contentOf(afterUndoReload), afterUndo);
    expect(afterUndoReload.layers.first.strokes.length, 1);
  });

  test('图层新建与排序：一次排序一条撤销条目，且排序结果真的落盘', () async {
    final c = newController('layers');
    c.addLayer(name: 'A');
    c.addLayer(name: 'B');
    c.addLayer(name: 'C');
    expect(c.document.layers.length, 4);
    final original = c.document.layers.map((l) => l.name).toList();

    final bottomId = c.document.layers.first.id;
    c.currentLayerIndex = 0;
    final entriesBefore = c.historyService.entryCount;
    c.layerService.reorderLayer(bottomId, c.document.layers.length - 1);

    final ordered = c.document.layers.map((l) => l.name).toList();
    expect(ordered, [...original.sublist(1), original.first]);
    expect(
      c.historyService.entryCount,
      entriesBefore + 1,
      reason: '一次拖拽排序必须且只能产生一条撤销条目',
    );

    c.undo();
    expect(c.document.layers.map((l) => l.name).toList(), original);
    c.redo();
    expect(c.document.layers.map((l) => l.name).toList(), ordered);

    final orderedContent = contentOf(c.document);
    await repo.save(c.document);
    c.dispose();

    final reloaded = await repo.load('layers');
    expect(
      contentOf(reloaded!),
      orderedContent,
      reason: '图层顺序是用户手工整理的结果，必须随文档持久化',
    );
    expect(reloaded.layers.map((l) => l.name).toList(), ordered);
  });

  test('落盘文件确实是文档本体：外部直接读 JSON 也能还原出笔画', () async {
    final c = newController('raw_json');
    await draw(c, 30);
    final path = await repo.save(c.document);
    c.dispose();

    // 磁盘形态 = DocumentCodec.snapshotOf：{version, document:{...}}，
    // 且笔画点是扁平三元组 [x, y, pressure, ...]（Stroke._encodePoints）。
    final onDisk = jsonDecode(await File(path).readAsString());
    final document = (onDisk as Map)['document'] as Map;
    expect(document['id'], 'raw_json');
    final layers = document['layers'] as List;
    final strokes = (layers.first as Map)['strokes'] as List;
    expect(strokes, hasLength(1));
    final points = (strokes.first as Map)['points'] as List;
    expect(points[0], 30);
    expect(points[1], 40);
    expect(points.length, greaterThanOrEqualTo(9)); // 三个点 × [x,y,p]
  });
}
