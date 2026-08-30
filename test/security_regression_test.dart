import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// 安全审计修复回归测试。
///
/// 覆盖 SECURITY_AUDIT.md 中 13 项修复中可在引擎/存储层验证的部分：
/// - H1: dispose 后异步缓存重建不崩溃（不调用已释放对象）
/// - H2: 缓存重建竞态——dirty 被重新置位时旧结果作废
/// - L3: pickColorAt/renderToPng 异常路径位图释放（正常路径仍工作）
/// - L4: dispose 幂等
/// - M1: _rebuildCacheMap 移除缓存时释放位图（经撤销/重做路径）
/// - M2: 历史栈上限 60 条
/// - M3: 删除画作同时删除缩略图
/// - M4: 删除笔记本清理页面图片副本
/// - M6: storeImage 扩展名白名单
/// - L1/L2: ID 白名单校验
void main() {
  DrawingDocument makeDoc({int w = 200, int h = 200}) =>
      DrawingDocument(id: 'reg_doc', title: '回归测试', width: w, height: h);

  group('H1: dispose 后异步缓存重建不崩溃', () {
    test('dispose 后等待重建完成不应抛出异常', () async {
      final c = DrawingController(makeDoc());
      // 触发一次重建（异步），随后立即销毁。
      c.startStroke(const Offset(10, 10));
      c.extendStroke(const Offset(50, 50));
      await c.endStroke();
      c.dispose();
      // 给异步重建留出完成时间——若修复缺失会在此处抛"已释放对象"异常。
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.isDisposed, isTrue);
    });

    test('dispose 幂等：重复调用不抛异常', () {
      final c = DrawingController(makeDoc());
      c.dispose();
      c.dispose();
      expect(c.isDisposed, isTrue);
    });
  });

  group('H2: 缓存重建竞态', () {
    test('重建期间再次修改图层：最终显示最新内容', () async {
      final c = DrawingController(makeDoc());
      // 第一笔：触发重建（异步未完成时画第二笔）。
      c.startStroke(const Offset(10, 10));
      c.extendStroke(const Offset(20, 20));
      await c.endStroke();
      // 立即画第二笔——两次重建可能并发。
      c.startStroke(const Offset(100, 100));
      c.extendStroke(const Offset(110, 110));
      await c.endStroke();

      // 等所有重建完成。
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(c.document.layers.first.strokes.length, 2, reason: '两笔都应保留');
      expect(c.paintViews.first.image, isNotNull);
    });
  });

  group('M2: 历史栈上限', () {
    test('超过 60 条时丢弃最旧记录', () async {
      final c = DrawingController(makeDoc());
      for (var i = 0; i < 70; i++) {
        c.startStroke(Offset(i * 1.0, 10));
        c.extendStroke(Offset(i * 1.0 + 5, 10));
        await c.endStroke();
      }
      // 历史内部长度不可直接访问，但 canUndo 受上限约束：
      // 全部撤销后只能撤销到最近 60 条之前的边界。
      var undoCount = 0;
      while (c.canUndo) {
        c.undo();
        undoCount++;
      }
      expect(undoCount, lessThanOrEqualTo(60), reason: '历史最多保留 60 条');
    });
  });

  group('L1/L2: ID 白名单校验', () {
    test('合法 ID 通过校验', () {
      expect(StorageService.isValidId('doc_123'), isTrue);
      expect(StorageService.isValidId('nb_abc_9'), isTrue);
      expect(NotebookStorage.isValidId('page_1'), isTrue);
    });

    test('非法 ID（路径遍历字符）被拒绝', () {
      expect(StorageService.isValidId('../etc/passwd'), isFalse);
      expect(StorageService.isValidId('a/b'), isFalse);
      expect(StorageService.isValidId('a\\b'), isFalse);
      expect(StorageService.isValidId('a b'), isFalse);
      expect(NotebookStorage.isValidId('..\\..\\x'), isFalse);
    });
  });

  group('M3: 删除画作同步删除缩略图', () {
    late Directory tempDir;
    late StorageService storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('reg_storage_');
      storage = StorageService(directoryProvider: () async => tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('删除文档后缩略图文件一并移除', () async {
      final doc = DrawingDocument(id: 'del_thumb', title: 't');
      await storage.save(doc);
      await storage.saveThumbnail('del_thumb', _tinyPng());
      expect(await storage.thumbnailPath('del_thumb'), isNotNull);

      await storage.delete('del_thumb');
      expect(
        await storage.thumbnailPath('del_thumb'),
        isNull,
        reason: '缩略图应随文档删除',
      );
    });
  });

  group('M4: 删除笔记本清理图片副本', () {
    late Directory tempDir;
    late NotebookStorage storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('reg_nb_');
      storage = NotebookStorage(directoryProvider: () async => tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('删除笔记本时清理其页面引用的图片文件', () async {
      final nb = Notebook(id: 'nb_del', title: '待删');
      // 构造一个真实图片副本文件。
      final imgPath = await storage.storeImage(
        await _makeSourceImage(tempDir),
        'pg_1',
      );
      expect(File(imgPath).existsSync(), isTrue);

      nb.pages.add(
        NotebookPage(
          id: 'pg_1',
          title: '页',
          document: DrawingDocument(id: 'd1', title: '页'),
        ),
      );
      nb.pages.first.imageItems.add(
        PageImageItem(id: 'img_1', x: 0, y: 0, filePath: imgPath),
      );
      await storage.save(nb);

      await storage.delete('nb_del');
      expect(File(imgPath).existsSync(), isFalse, reason: '图片副本应被清理');
      expect(await storage.load('nb_del'), isNull);
    });
  });

  group('M6: storeImage 扩展名白名单', () {
    late Directory tempDir;
    late NotebookStorage storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('reg_ext_');
      storage = NotebookStorage(directoryProvider: () async => tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('未知扩展名回退为 png', () async {
      final src = await _makeSourceImage(tempDir, name: 'evil.exe');
      final target = await storage.storeImage(src, 'pg_x');
      expect(target.endsWith('.png'), isTrue, reason: '非白名单扩展名回退 png');
    });

    test('合法扩展名保留', () async {
      final src = await _makeSourceImage(tempDir, name: 'photo.jpeg');
      final target = await storage.storeImage(src, 'pg_y');
      expect(target.endsWith('.jpeg'), isTrue);
    });

    test('非法 pageId 被拒绝', () async {
      final src = await _makeSourceImage(tempDir);
      expect(() => storage.storeImage(src, '../evil'), throwsArgumentError);
    });
  });

  group('M7: 图片离线副本失败路径清理', () {
    late Directory tempDir;
    late StorageService storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('reg_storage_image_');
      storage = StorageService(directoryProvider: () async => tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('不存在的图片源被拒绝且不会创建媒体目录', () async {
      final missing = '${tempDir.path}${Platform.pathSeparator}missing.jpg';
      await expectLater(
        storage.storeImage(missing, 'doc_image'),
        throwsArgumentError,
      );
      expect(
        Directory(
          '${tempDir.path}${Platform.pathSeparator}document_images',
        ).existsSync(),
        isFalse,
      );
    });
  });

  group('L3: 导出/取色正常路径仍工作', () {
    test('renderToPng 返回合法 PNG 且位图正确释放（正常路径）', () async {
      final c = DrawingController(makeDoc(w: 64, h: 64));
      c.startStroke(const Offset(10, 10));
      c.extendStroke(const Offset(50, 50));
      await c.endStroke();
      final png = await c.renderToPng();
      expect(png, isNotNull);
      expect(png![0], 0x89);
      expect(png[1], 0x50);
    });

    test('pickColorAt 正常取色', () async {
      final c = DrawingController(makeDoc(w: 64, h: 64));
      c.color = const Color(0xFFFF0000);
      c.brushSize = 20;
      c.startStroke(const Offset(20, 20));
      c.extendStroke(const Offset(40, 40));
      await c.endStroke();
      for (var i = 0; i < 50 && c.paintViews.first.image == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final color = await c.pickColorAt(const Offset(30, 30));
      expect(color, isNotNull);
      expect(color!.a, greaterThan(0));
    });
  });

  group('M1: 撤销/重做后缓存正确重建（位图不泄漏路径）', () {
    test('撤销删除图层后缓存恢复且可正常绘制', () async {
      final c = DrawingController(makeDoc());
      c.addLayer();
      c.addLayer();
      final layerId = c.document.layers[2].id;

      c.removeLayer(2);
      c.undo();
      // 撤销后图层恢复，缓存应重建为可绘制状态。
      expect(c.document.layers.length, 3);
      c.currentLayerIndex = 2;
      c.startStroke(const Offset(10, 10));
      c.extendStroke(const Offset(30, 30));
      await c.endStroke();
      for (var i = 0; i < 50 && c.paintViews[2].image == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(c.paintViews[2].image, isNotNull);
      expect(c.document.layers[2].id, layerId);
    });
  });
}

/// 构造一个最小的源图片文件（内容不校验，仅用于路径/复制测试）。
Future<String> _makeSourceImage(
  Directory dir, {
  String name = 'src.png',
}) async {
  final f = File('${dir.path}/$name');
  await f.writeAsBytes([1, 2, 3, 4]);
  return f.path;
}

/// 最小 1x1 透明 PNG（用于缩略图写入测试）。
Uint8List _tinyPng() {
  const b64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQAB'
      'h6FO1AAAAABJRU5ErkJggg==';
  return Uint8List.fromList(const Base64Codec().decode(b64));
}
