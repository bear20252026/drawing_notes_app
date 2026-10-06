import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/document_image_item.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/temp_dir_cleanup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('document_image_test_');
  });

  tearDown(() async {
    // 保留 async exists：删除前让出一拍，待在途图片解码句柄释放
    //（errno 32 教训，v1.17.6 lint 批回归）。带重试兜底。
    await deleteTempDirWithRetry(tempDir);
  });

  test('独立文档图片会复制为离线副本，并在保存重开后完整恢复', () async {
    final storage = StorageService(directoryProvider: () async => tempDir);
    final source = File('${tempDir.path}${Platform.pathSeparator}source.png');
    await source.writeAsBytes(_tinyPng());

    final storedPath = await storage.storeImage(source.path, 'doc_image');
    expect(storedPath, isNot(source.path));
    expect(File(storedPath).existsSync(), isTrue);
    expect(await File(storedPath).readAsBytes(), await source.readAsBytes());

    final document = DrawingDocument(
      id: 'doc_image',
      title: '图片画布',
      imageItems: [
        DocumentImageItem(
          id: 'image_1',
          x: 120,
          y: 80,
          width: 320,
          height: 180,
          zOrder: 3,
          locked: true,
          filePath: storedPath,
        ),
      ],
    );
    await storage.save(document);

    final restored = await storage.load(document.id);
    expect(restored, isNotNull);
    expect(restored!.imageItems, hasLength(1));
    final image = restored.imageItems.single;
    expect(image.id, 'image_1');
    expect(image.filePath, storedPath);
    expect(image.x, 120);
    expect(image.y, 80);
    expect(image.width, 320);
    expect(image.height, 180);
    expect(image.zOrder, 3);
    expect(image.locked, isTrue);
  });

  test('导入图片参与无限画布边界与 PNG 导出', () async {
    final source = File('${tempDir.path}${Platform.pathSeparator}image.png');
    await source.writeAsBytes(_tinyPng());
    final document = DrawingDocument(
      id: 'image_export',
      title: '图片导出',
      infinite: true,
      imageItems: [
        DocumentImageItem(
          id: 'image_export_1',
          x: -150,
          y: 220,
          width: 360,
          height: 180,
          filePath: source.path,
        ),
      ],
    );
    final controller = DrawingController(document);
    addTearDown(controller.dispose);

    final bounds = controller.contentBounds();
    expect(bounds.left, lessThanOrEqualTo(-174));
    expect(bounds.bottom, greaterThanOrEqualTo(424));
    final png = await controller.renderToPng();
    expect(png, isNotNull);
    expect(png, isNotEmpty);
  });

  test('整组图片超出缓存预算时 PNG 导出仍逐张落进产物（不静默缺图）', () async {
    // 台账 2026-10-05 AW 第 5 条：2400² RGBA ≈ 23MB，三张 ≈ 69MB > 48MiB 预算。
    // 老实现先 `ensureLoaded` 预热整组、再由渲染腿用 `documentImage()` 取图——
    // 后载入的把先载入的淘汰掉，未驻留的直接 `continue`，于是产物缺图且用户
    // 全程无感知。导出腿改成逐张「解码→绘制→立即释放」后，完整性不再依赖
    // 预算装得下整组。这条用例是那条边界的正向锁：三张都必须在产物里。
    const side = 2400;
    final spots = const <({int b, int g, int r, double x})>[
      (r: 255, g: 0, b: 0, x: 0.0),
      (r: 0, g: 255, b: 0, x: 400.0),
      (r: 0, g: 0, b: 255, x: 800.0),
    ];
    final imageItems = <DocumentImageItem>[];
    for (var index = 0; index < spots.length; index++) {
      final spot = spots[index];
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}big_$index.png',
      );
      await file.writeAsBytes(
        await _solidPngBytes(side, spot.r, spot.g, spot.b),
      );
      imageItems.add(
        DocumentImageItem(
          id: 'big_$index',
          x: spot.x,
          y: 0,
          width: 300,
          height: 300,
          zOrder: index,
          filePath: file.path,
        ),
      );
    }

    final controller = DrawingController(
      DrawingDocument(
        id: 'over_budget_export',
        title: '超预算导出',
        infinite: true,
        imageItems: imageItems,
      ),
    );
    addTearDown(controller.dispose);

    final png = await controller.renderToPng();
    expect(png, isNotNull);

    final bounds = controller.contentBounds();
    final raster = await _decodeToRgba(png!);
    addTearDown(raster.image.dispose);
    for (final spot in spots) {
      // 取样点 = 该图 dst 矩形中心换算到输出光栅像素。
      final px = ((spot.x + 150) - bounds.left).round();
      final py = (150 - bounds.top).round();
      final pixel = raster.pixelAt(px, py);
      expect(
        pixel.r,
        spot.r,
        reason:
            '导出产物在 (${spot.x}, 0) 那张图的位置必须是图本身的颜色，'
            '不能是纸面白底——白底即「静默缺图」',
      );
      expect(pixel.g, spot.g);
      expect(pixel.b, spot.b);
    }
  });

  test('图片导入拒绝不存在的源文件与非法文档 ID', () async {
    final storage = StorageService(directoryProvider: () async => tempDir);

    await expectLater(
      storage.storeImage('${tempDir.path}/missing.png', 'valid_document'),
      throwsArgumentError,
    );

    final source = File('${tempDir.path}/source.jpg');
    await source.writeAsBytes(const [1, 2, 3]);
    await expectLater(
      storage.storeImage(source.path, '../invalid'),
      throwsArgumentError,
    );
  });
}

Uint8List _tinyPng() {
  const b64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQAB'
      'h6FO1AAAAABJRU5ErkJggg==';
  return Uint8List.fromList(const Base64Codec().decode(b64));
}

/// side×side 纯色不透明 PNG 字节。走 `PictureRecorder` 光栅化而不是手搓
/// 23MB 像素缓冲——只为造出「一张正常尺寸的大图」这个事实。
Future<Uint8List> _solidPngBytes(int side, int r, int g, int b) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble()),
    ui.Paint()..color = ui.Color.fromARGB(255, r, g, b),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(side, side);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

/// 导出产物的光栅读回句柄（取样用；`image` 必须由调用方 dispose）。
class _RgbaRaster {
  _RgbaRaster(this.image, this._bytes, this.width);

  final ui.Image image;
  final ByteData _bytes;
  final int width;

  ({int b, int g, int r}) pixelAt(int x, int y) {
    final offset = (y * width + x) * 4;
    return (
      r: _bytes.getUint8(offset),
      g: _bytes.getUint8(offset + 1),
      b: _bytes.getUint8(offset + 2),
    );
  }
}

Future<_RgbaRaster> _decodeToRgba(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  codec.dispose();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return _RgbaRaster(frame.image, data!, frame.image.width);
}
