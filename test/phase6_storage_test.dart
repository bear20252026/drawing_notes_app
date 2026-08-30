import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 6 验收测试：文件管理与持久化。
///
/// 验收标准（来自开发计划 4.3 Phase 6）：
/// - 自动保存：用户操作后自动写入本地存储，不需要手动点保存按钮
/// - 首页作品/笔记列表：展示所有已创建的画作和笔记本，带缩略图
/// - 导出功能：把当前画布/笔记页导出为 PNG 图片，保存到本地文件系统
/// - 删除功能：删除某个作品/笔记本，删除前弹出二次确认
/// - 关闭 App 重新打开，之前的所有内容都还在
/// - 能导出一张图片到系统文件夹能打开查看
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('storage_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  StorageService makeStorage() =>
      StorageService(directoryProvider: () async => tempDir);

  group('Phase 6 文件管理与持久化', () {
    test('保存+重新加载：关闭再打开后内容完整恢复', () async {
      final storage = makeStorage();
      final doc = DrawingDocument(
        id: 'doc_save',
        title: '我的画',
        width: 100,
        height: 100,
      );
      doc.layers.first.strokes.addAll([
        // 用控制器画一笔，模拟真实数据
      ]);

      // 直接构造带笔画的文档
      final controller = DrawingController(doc);
      controller.startStroke(const Offset(10, 10));
      controller.extendStroke(const Offset(40, 40));
      await controller.endStroke();

      await storage.save(doc);
      final loaded = await storage.load('doc_save');

      expect(loaded, isNotNull);
      expect(loaded!.title, '我的画');
      expect(loaded.width, 100);
      expect(loaded.layers.first.strokes.length, 1, reason: '笔画数据完整保留');
      expect(loaded.layers.first.strokes.first.points.first.offset.dx, 10);
    });

    test('自动保存：调用 save 后文件真实落盘，可被列表识别', () async {
      final storage = makeStorage();
      final doc = DrawingDocument(id: 'doc_auto', title: '自动保存测试');
      await storage.save(doc);

      final metas = await storage.listDocuments();
      expect(metas.length, 1);
      expect(metas.first.id, 'doc_auto');
      expect(metas.first.title, '自动保存测试');
      expect(metas.first.layerCount, 1);
    });

    test('缩略图：保存后可通过 thumbnailPath 读取到文件', () async {
      final storage = makeStorage();
      // 构造一个有效的 PNG 字节（最小 1x1 透明 PNG）。
      final pngBytes = _tinyPng();
      await storage.saveThumbnail('doc_thumb', pngBytes);

      final path = await storage.thumbnailPath('doc_thumb');
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);
    });

    test('列表按更新时间倒序排列', () async {
      final storage = makeStorage();
      final d1 = DrawingDocument(id: 'd1', title: '较早');
      final d2 = DrawingDocument(id: 'd2', title: '较新');
      await storage.save(d1);
      await storage.save(d2);
      // 模拟"较新"文档被编辑过：touch 更新时间后再次保存。
      await Future<void>.delayed(const Duration(milliseconds: 20));
      d2.touch();
      await storage.save(d2);

      final metas = await storage.listDocuments();
      expect(metas.first.id, 'd2', reason: '最新更新的排在前面');
    });

    test('删除：文件从磁盘移除，列表不再包含', () async {
      final storage = makeStorage();
      final doc = DrawingDocument(id: 'doc_del', title: '待删除');
      await storage.save(doc);
      expect(await storage.load('doc_del'), isNotNull);

      final ok = await storage.delete('doc_del');
      expect(ok, isTrue);
      expect(await storage.load('doc_del'), isNull);

      final metas = await storage.listDocuments();
      expect(metas, isEmpty);
    });

    test('导出 PNG：渲染文档得到有效的 PNG 字节', () async {
      final doc = DrawingDocument(
        id: 'doc_exp',
        title: '导出测试',
        width: 64,
        height: 64,
      );
      final controller = DrawingController(doc);
      controller.color = const Color(0xFF000000);
      controller.brushSize = 8;
      controller.startStroke(const Offset(10, 10));
      controller.extendStroke(const Offset(50, 50));
      await controller.endStroke();

      // 等位图缓存重建完成
      for (
        var i = 0;
        i < 50 && controller.paintViews.first.image == null;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final png = await controller.renderToPng();
      expect(png, isNotNull);
      // PNG 文件头固定为 89 50 4E 47。
      expect(png![0], 0x89);
      expect(png[1], 0x50);
      expect(png[2], 0x4E);
      expect(png[3], 0x47);
      // 可写入本地文件并读取
      final out = File('${tempDir.path}/export.png');
      await out.writeAsBytes(png);
      expect(out.lengthSync(), greaterThan(0));
    });

    test('导出 PNG 支持缩放（2 倍分辨率）', () async {
      final doc = DrawingDocument(
        id: 'doc_exp2',
        title: '缩放导出',
        width: 32,
        height: 32,
      );
      final controller = DrawingController(doc);
      final png = await controller.renderToPng(scale: 2.0);
      expect(png, isNotNull);
      expect(png!.length, greaterThan(0));
    });

    test('空画布也能导出（纯白图片）', () async {
      final doc = DrawingDocument(
        id: 'doc_blank',
        title: '空白',
        width: 16,
        height: 16,
      );
      final controller = DrawingController(doc);
      final png = await controller.renderToPng();
      expect(png, isNotNull);
      expect(png!.length, greaterThan(0));
    });

    test('多画布 A/B 保存、退出、重开后内容严格一一对应', () async {
      final storage = makeStorage();
      final canvasA = DrawingDocument(id: 'canvas_a', title: '项目 A');
      final canvasB = DrawingDocument(id: 'canvas_b', title: '项目 B');
      final aController = DrawingController(canvasA);
      final bController = DrawingController(canvasB);
      aController.startStroke(const Offset(11, 22));
      aController.extendStroke(const Offset(33, 44));
      bController.startStroke(const Offset(155, 266));
      bController.extendStroke(const Offset(377, 488));
      await Future.wait([aController.endStroke(), bController.endStroke()]);

      await Future.wait([
        storage.save(canvasA),
        storage.save(canvasB),
        storage.saveThumbnail('canvas_a', Uint8List.fromList([1, 2, 3])),
        storage.saveThumbnail('canvas_b', Uint8List.fromList([7, 8, 9])),
      ]);

      // 使用全新的服务实例模拟 App 完全退出后重新打开。
      final reopened = makeStorage();
      final restoredA = await reopened.load('canvas_a');
      final restoredB = await reopened.load('canvas_b');
      expect(restoredA!.title, '项目 A');
      expect(restoredB!.title, '项目 B');
      expect(
        restoredA.layers.single.strokes.single.points.first.offset,
        const Offset(11, 22),
      );
      expect(
        restoredB.layers.single.strokes.single.points.first.offset,
        const Offset(155, 266),
      );
      expect(
        await reopened.thumbnailPath('canvas_a'),
        isNot(await reopened.thumbnailPath('canvas_b')),
      );
      aController.dispose();
      bController.dispose();
    });

    test('同一画布连续异步保存保序，最后一个版本不会被旧快照覆盖', () async {
      final storage = makeStorage();
      final doc = DrawingDocument(id: 'rapid_save', title: '版本一');
      final first = storage.save(doc);
      doc.title = '版本二';
      final controller = DrawingController(doc);
      controller.startStroke(const Offset(80, 90));
      controller.extendStroke(const Offset(100, 120));
      await controller.endStroke();
      final second = storage.save(doc);
      await Future.wait([first, second]);

      final restored = await makeStorage().load('rapid_save');
      expect(restored!.title, '版本二');
      expect(restored.layers.single.strokes, hasLength(1));
      controller.dispose();
    });

    test('正式文件损坏时自动回退到上一份完整备份', () async {
      final storage = makeStorage();
      final doc = DrawingDocument(id: 'backup_doc', title: '可恢复版本');
      await storage.save(doc);
      doc.title = '最新版本';
      await storage.save(doc);
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}documents${Platform.pathSeparator}backup_doc.json',
      );
      await file.writeAsString('{已损坏', flush: true);

      final recovered = await makeStorage().load('backup_doc');
      expect(recovered!.title, '可恢复版本');
    });

    test('高频新建 ID 不重复，不能共享工程文件路径', () {
      final ids = List<String>.generate(2000, (_) => StorageService.newId());
      expect(ids.toSet(), hasLength(ids.length));
    });
  });
}

/// 生成一个最小的 1x1 透明 PNG（8 字节签名 + 必要块）。
/// 用于验证缩略图文件可写可读，不要求真实图像内容。
Uint8List _tinyPng() {
  // 用 base64 硬编码一个 1x1 透明 PNG。
  const b64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQAB'
      'h6FO1AAAAABJRU5ErkJggg==';
  return Uint8List.fromList(const Base64Codec().decode(b64));
}
