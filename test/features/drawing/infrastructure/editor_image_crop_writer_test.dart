import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:drawing_notes_app/features/drawing/infrastructure/editor_image_crop.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/temp_dir_cleanup.dart';

/// 裁剪写回管线（[EditorImageCropWriter]）——修复 2（审计 2026-10-04）：
/// 覆盖唯一原图前逐字保留 `.bak` 可恢复副本，异常路径不留半成品。
///
/// 用 plain [test] + 真实 binding（非 testWidgets 的 fake-async 区——后者
/// 不推进引擎栅格回调，会挂死 picture.toImage / instantiateImageCodec）。
/// 最小合法纯色 PNG（明文路径即可验证 `.bak` 语义，无需解锁保险库）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('editor_image_crop_writer');
  });

  tearDown(() {
    // T-13 回退（2026-10-04 测试侧加固）：原先裸 `deleteSync` 在本仓 Windows
    // 机器上会撞句柄锁——真实栅格化写盘收尾时仍可能持文件句柄，立即递归删除
    // 抛 PathAccessException（errno 32）造成 flaky。改用全仓 55 个文件共用的
    // 带退避重试 helper；语义不变（目录已不在即返回，真泄漏仍抛）。
    if (dir.existsSync()) return deleteTempDirWithRetry(dir);
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

  Iterable<File> tmpLeftovers() =>
      dir.listSync().whereType<File>().where((f) => f.path.endsWith('.tmp'));

  test('裁剪写回后原图逐字保留为 .bak（可恢复）', () async {
    final original = await renderPng(4);
    final file = writeFile('img.png', original);

    final outcome = await const EditorImageCropWriter().writeCrop(
      file: file,
      cropRect: const Rect.fromLTWH(0, 0, 2, 2),
      imageBounds: const Rect.fromLTWH(0, 0, 4, 4),
    );
    expect(outcome, EditorImageCropWriteOutcome.success);

    final bak = File('${file.path}.bak');
    expect(bak.existsSync(), isTrue, reason: '覆盖前留原图副本');
    expect(
      bak.readAsBytesSync(),
      original,
      reason: '副本 = 裁剪前原图逐字，把 .bak 改回原名即恢复（基名一致 AAD 亦成立）',
    );
    // 在档文件已被裁剪结果覆盖（与原图不同——此处 4x4 → 2x2）。
    expect(file.readAsBytesSync(), isNot(original));
    // 无半成品 .tmp 残留。
    expect(tmpLeftovers(), isEmpty);
  });

  test('原图缺失：返回 sourceMissing 且不创建 .bak/.tmp', () async {
    final file = File('${dir.path}${Platform.pathSeparator}missing.png');

    final outcome = await const EditorImageCropWriter().writeCrop(
      file: file,
      cropRect: const Rect.fromLTWH(0, 0, 2, 2),
      imageBounds: const Rect.fromLTWH(0, 0, 4, 4),
    );

    expect(outcome, EditorImageCropWriteOutcome.sourceMissing);
    expect(dir.listSync(), isEmpty);
  });

  test('解码失败（非法图像）：抛出且在档文件完好、无半成品', () async {
    final junk = Uint8List.fromList(utf8.encode('not an image'));
    final file = writeFile('broken.png', junk);

    await expectLater(
      const EditorImageCropWriter().writeCrop(
        file: file,
        cropRect: const Rect.fromLTWH(0, 0, 2, 2),
        imageBounds: const Rect.fromLTWH(0, 0, 4, 4),
      ),
      throwsA(anything),
    );

    // 备份/写入发生在解码之后：异常路径不动在档文件、不留 .bak/.tmp。
    expect(file.readAsBytesSync(), junk);
    expect(File('${file.path}.bak').existsSync(), isFalse);
    expect(tmpLeftovers(), isEmpty);
  });
}
