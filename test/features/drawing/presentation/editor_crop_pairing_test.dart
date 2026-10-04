import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:drawing_notes_app/core/canvas_model/page_image_item.dart';
import 'package:drawing_notes_app/features/drawing/infrastructure/editor_image_crop.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// 裁剪「文档几何 ↔ 磁盘字节」成对更新回归锁（修复 3，审计 2026-10-04）。
///
/// 被锁定的缺陷（原 editor_page.dart:490-506）：`await` 写盘之后才
/// `if (!mounted) return`、再改 img.x/y/width/height ⇒ 写盘 await 期间退出
/// 编辑页时磁盘只剩裁剪后像素、文档仍记裁剪前矩形（图片被永久拉伸错位）；
/// 另外 5s 防抖自动保存可能在写盘落定前取用文档快照，同样造成两边不同向。
///
/// 用 plain [test] + 真实 binding（非 testWidgets 的 fake-async 区——后者不
/// 推进引擎栅格回调，会挂死 picture.toImage / instantiateImageCodec），
/// 与 editor_image_crop_writer_test.dart 同一取径。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('editor_crop_pairing');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  // 渲染 size×size 纯色 PNG（确定性产物，作在档原图夹具）。
  Future<Uint8List> renderPng(int size) async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      Paint()..color = const Color(0xFF3366CC),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final data = await image.toByteData(format: ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  File writeFile(String name, List<int> bytes) {
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    file.writeAsBytesSync(bytes, flush: true);
    return file;
  }

  Future<Size> decodedSizeOf(File file) async {
    final codec = await instantiateImageCodec(await file.readAsBytes());
    final frame = await codec.getNextFrame();
    final size = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    frame.image.dispose();
    codec.dispose();
    return size;
  }

  Iterable<File> tmpLeftovers() =>
      dir.listSync().whereType<File>().where((f) => f.path.endsWith('.tmp'));

  const sourceRect = Rect.fromLTWH(0, 0, 8, 8);
  const cropRect = Rect.fromLTWH(0, 0, 4, 4);

  test('成对提交（真实写盘成功）：文档矩形与磁盘字节都是裁剪后，.bak 保留原图', () async {
    final original = await renderPng(8);
    final file = writeFile('img.png', original);
    final host = _CropPageHost(
      PageImageItem(
        id: 'im1',
        x: 0,
        y: 0,
        filePath: file.path,
        width: 8,
        height: 8,
      ),
    );

    final result = await host.confirm(
      cropRect,
      file,
      const EditorImageCropWriter(),
    );

    expect(result, EditorCropCommitResult.committed);
    // 文档几何 = 裁剪后矩形……
    expect(host.rect, cropRect);
    // ……磁盘字节 = 裁剪后像素（4x4，非原图 8x8）：两边同向，不会被拉伸错位。
    expect(await decodedSizeOf(file), const Size(4, 4));
    expect(file.readAsBytesSync(), isNot(original));
    // 修复 2 未回退：覆盖前逐字保留原图副本（文档/字节万一不同向仍可救）。
    expect(File('${file.path}.bak').readAsBytesSync(), original);
    expect(tmpLeftovers(), isEmpty);
    // 正常路径行为：裁剪交互收口一次、几何更新两次（提交 + 无回滚则仅一次）。
    expect(host.cropEnded, 1);
    expect(host.applied, <Rect>[cropRect]);
    expect(host.errors, isEmpty);
    expect(host.gate, isNull, reason: '落定后解除快照闸门');
  });

  test('写盘 await 期间页面卸载：文档矩形仍落到裁剪后，与磁盘字节同向', () async {
    final original = await renderPng(8);
    final file = writeFile('img.png', original);
    final host = _CropPageHost(
      PageImageItem(
        id: 'im1',
        x: 0,
        y: 0,
        filePath: file.path,
        width: 8,
        height: 8,
      ),
    );
    // 旧缺陷触发点：写盘飞行中退出编辑页（mounted=false）。
    final hold = Completer<void>();
    final running = host.confirm(
      cropRect,
      file,
      _HoldingCropWriter(inner: const EditorImageCropWriter(), hold: hold),
    );
    await pump();
    host.mounted = false; // 页面卸载
    hold.complete();
    final result = await running;

    expect(result, EditorCropCommitResult.committed);
    // 几何更新不再被 `if (!mounted) return` 挡掉（内存对象不需要 context）。
    expect(host.rect, cropRect);
    expect(await decodedSizeOf(file), const Size(4, 4));
    // UI 反馈仍受 mounted 守卫：卸载后不重绘、不抛 setState after dispose。
    expect(host.repaints, 1, reason: '仅提交前的那次重绘');
  });

  test('写盘异常：文档矩形回滚为裁剪前，磁盘字节逐字未变（两边都回旧值）', () async {
    final junk = Uint8List.fromList(utf8.encode('not an image'));
    final file = writeFile('broken.png', junk);
    final host = _CropPageHost(
      PageImageItem(
        id: 'im1',
        x: 0,
        y: 0,
        filePath: file.path,
        width: 8,
        height: 8,
      ),
    );

    final result = await host.confirm(
      cropRect,
      file,
      const EditorImageCropWriter(),
    );

    expect(result, EditorCropCommitResult.failed);
    expect(host.rect, sourceRect, reason: '几何回滚，不留单边新值');
    expect(host.applied, <Rect>[cropRect, sourceRect]);
    expect(file.readAsBytesSync(), junk, reason: '原子写在解码失败前不动在档文件');
    expect(File('${file.path}.bak').existsSync(), isFalse);
    expect(tmpLeftovers(), isEmpty);
    expect(host.cropEnded, isZero, reason: '失败时留在裁剪态可重试（沿用旧行为）');
    expect(host.errors, hasLength(1), reason: '异常只进脱敏上报（R-02）');
    expect(host.gate, isNull);
  });

  test('非成功结果码同样成对回滚：sourceMissing 时文档与磁盘都保持裁剪前', () async {
    final missing = File('${dir.path}${Platform.pathSeparator}gone.png');
    final host = _CropPageHost(
      PageImageItem(
        id: 'im1',
        x: 0,
        y: 0,
        filePath: missing.path,
        width: 8,
        height: 8,
      ),
    );

    final result = await host.confirm(
      cropRect,
      missing,
      const EditorImageCropWriter(),
    );

    expect(result, EditorCropCommitResult.sourceMissing);
    expect(host.rect, sourceRect);
    expect(missing.existsSync(), isFalse);
    expect(dir.listSync(), isEmpty);
  });

  test('自动保存快照被闸门挡住：成功路径取到的快照就是裁剪后矩形', () async {
    final host = _CropPageHost(
      PageImageItem(
        id: 'im1',
        x: 0,
        y: 0,
        filePath: 'a.png',
        width: 8,
        height: 8,
      ),
    );
    final hold = Completer<EditorImageCropWriteOutcome>();
    final running = host.confirmWith(cropRect, (crop, bounds) => hold.future);
    await pump();
    // 写盘飞行中：自动保存链此刻要落盘（5s 防抖到点 / 退出兜底 flush）。
    final snapshotTaken = host.captureSnapshot();
    hold.complete(EditorImageCropWriteOutcome.success);
    final result = await running;
    await snapshotTaken;

    expect(result, EditorCropCommitResult.committed);
    expect(host.snapshots, <Rect>[cropRect], reason: '快照在写盘落定后才编码');
    expect(host.dirtyMarks, 1);
  });

  test('自动保存快照被闸门挡住：失败路径取到的快照是回滚后的裁剪前矩形', () async {
    final host = _CropPageHost(
      PageImageItem(
        id: 'im1',
        x: 0,
        y: 0,
        filePath: 'a.png',
        width: 8,
        height: 8,
      ),
    );
    final hold = Completer<EditorImageCropWriteOutcome>();
    final running = host.confirmWith(cropRect, (crop, bounds) => hold.future);
    await pump();
    final snapshotTaken = host.captureSnapshot();
    host.mounted = false; // 写盘期间退出页面（兜底 flush 此刻已在闸门后等待）
    hold.complete(EditorImageCropWriteOutcome.encodeFailed);
    final result = await running;
    await snapshotTaken;

    expect(result, EditorCropCommitResult.encodeFailed);
    expect(host.snapshots, <Rect>[sourceRect]);
    expect(host.rect, sourceRect);
    expect(host.dirtyMarks, 2, reason: '提交 + 回滚各标脏一次，最后一写胜出');
  });
}

/// 等待若干微任务/事件轮次，让未 await 的异步链推进（本文件的时序探针）。
Future<void> pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// 页面侧替身：复刻 `_EditorPagePersistence._confirmCrop` 四个回调的语义
/// （改文档对象 + 失效位图 + 标脏 / 收口裁剪交互 / 快照闸门 / 脱敏上报），
/// `mounted=false` 时只少一次重绘——与真实页面一致。
class _CropPageHost {
  _CropPageHost(this.image);

  final PageImageItem image;
  bool mounted = true;

  /// applyRect 依次收到的矩形（提交 = 裁剪后；失败再补一次 = 裁剪前）。
  final List<Rect> applied = <Rect>[];

  /// 闸门放行后「编码文档快照」读到的矩形（模拟 _persistArtwork）。
  final List<Rect> snapshots = <Rect>[];

  /// 脱敏上报（R-02/H-04 口径：只给错误类型）。
  final List<Object> errors = <Object>[];

  int cropEnded = 0;
  int repaints = 0;
  int dirtyMarks = 0;
  Future<void>? gate;

  Rect get rect => Rect.fromLTWH(image.x, image.y, image.width, image.height);

  /// 真实写盘器路径（与 _confirmCrop 的 writeToDisk 闭包一致）。
  Future<EditorCropCommitResult> confirm(
    Rect crop,
    File file,
    EditorImageCropWriter writer,
  ) => confirmWith(
    crop,
    (c, bounds) =>
        writer.writeCrop(file: file, cropRect: c, imageBounds: bounds),
  );

  Future<EditorCropCommitResult> confirmWith(
    Rect crop,
    Future<EditorImageCropWriteOutcome> Function(Rect crop, Rect bounds)
    writeToDisk,
  ) {
    return commitCropPairing(
      sourceBounds: rect,
      cropRect: crop,
      writeToDisk: writeToDisk,
      applyRect: (target) {
        applied.add(target);
        image
          ..x = target.left
          ..y = target.top
          ..width = target.width
          ..height = target.height;
        dirtyMarks++;
        if (mounted) repaints++;
      },
      endCrop: () {
        cropEnded++;
        if (mounted) repaints++;
      },
      writeGate: (inFlight) => gate = inFlight,
      reportError: errors.add,
    );
  }

  /// 模拟自动保存：读闸门 → 等它放行 → 才编码文档快照。
  Future<void> captureSnapshot() async {
    final inFlight = gate;
    if (inFlight != null) await inFlight;
    snapshots.add(rect);
  }
}

/// 在写盘前挂起（模拟「写盘 await 期间页面被卸载」的时序窗口）。
class _HoldingCropWriter implements EditorImageCropWriter {
  const _HoldingCropWriter({required this.inner, required this.hold});

  final EditorImageCropWriter inner;
  final Completer<void> hold;

  @override
  Future<EditorImageCropWriteOutcome> writeCrop({
    required File file,
    required Rect cropRect,
    required Rect imageBounds,
  }) async {
    await hold.future;
    return inner.writeCrop(
      file: file,
      cropRect: cropRect,
      imageBounds: imageBounds,
    );
  }
}
