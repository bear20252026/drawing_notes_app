import 'dart:io';
import 'dart:typed_data';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/document_image_item.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/temp_dir_cleanup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'document_asset_lifecycle_',
    );
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tempDir);
  });

  DrawingDocument documentWithImage(String id, String path) => DrawingDocument(
    id: id,
    title: id,
    imageItems: [
      DocumentImageItem(
        id: '${id}_image',
        x: 10,
        y: 20,
        width: 100,
        height: 60,
        filePath: path,
      ),
    ],
  );

  test('删除文档会回收其唯一引用的受管离线图片和备份', () async {
    final storage = StorageService(directoryProvider: () async => tempDir);
    final source = File('${tempDir.path}${Platform.pathSeparator}source.png');
    await source.writeAsBytes(const <int>[1, 2, 3, 4]);
    final storedPath = await storage.storeImage(source.path, 'asset_owner');
    await storage.save(documentWithImage('asset_owner', storedPath));
    await storage.save(documentWithImage('asset_owner', storedPath));

    expect(File(storedPath).existsSync(), isTrue);
    expect(
      File(
        '${tempDir.path}${Platform.pathSeparator}documents${Platform.pathSeparator}asset_owner.json.bak',
      ).existsSync(),
      isTrue,
    );

    expect(await storage.delete('asset_owner'), isTrue);
    expect(File(storedPath).existsSync(), isFalse);
    expect(source.existsSync(), isTrue);
    expect(
      File(
        '${tempDir.path}${Platform.pathSeparator}documents${Platform.pathSeparator}asset_owner.json.bak',
      ).existsSync(),
      isFalse,
    );
  });

  test('删除文档不会回收仍被其他文档引用的受管图片', () async {
    final storage = StorageService(directoryProvider: () async => tempDir);
    final source = File('${tempDir.path}${Platform.pathSeparator}source.jpg');
    await source.writeAsBytes(const <int>[5, 6, 7]);
    final storedPath = await storage.storeImage(source.path, 'first_doc');
    await storage.save(documentWithImage('first_doc', storedPath));
    await storage.save(documentWithImage('second_doc', storedPath));

    expect(await storage.delete('first_doc'), isTrue);
    expect(File(storedPath).existsSync(), isTrue);
    expect(await storage.delete('second_doc'), isTrue);
    expect(File(storedPath).existsSync(), isFalse);
  });

  test('只剩 .bak 的另一篇文档仍引用这张图：不得被当孤儿回收', () async {
    // 关键在**交叉引用**：候选集只来自被删那篇自己，所以只有「这张图同时被
    // 另一篇引用」时回收才会威胁到它。另一篇正文没了、只剩侧车时，`load`
    // 依然能把它读出来——以前引用扫描只认 `.json`，看不见它 ⇒ 图被真删，
    // 画布还在、图没了。
    final storage = StorageService(directoryProvider: () async => tempDir);
    String docPath(String id) =>
        '${tempDir.path}${Platform.pathSeparator}documents'
        '${Platform.pathSeparator}$id.json';

    final srcShared = File('${tempDir.path}${Platform.pathSeparator}shared.png');
    await srcShared.writeAsBytes(const <int>[11, 12, 13]);
    final shared = await storage.storeImage(srcShared.path, 'ghost_doc');
    final srcSolo = File('${tempDir.path}${Platform.pathSeparator}solo.png');
    await srcSolo.writeAsBytes(const <int>[21, 22]);
    final solo = await storage.storeImage(srcSolo.path, 'dead_doc');

    await storage.save(documentWithImage('ghost_doc', shared));
    await storage.save(documentWithImage('ghost_doc', shared));
    File(docPath('ghost_doc')).deleteSync(); // 模拟 rename 期崩溃的残留
    expect(File(docPath('ghost_doc')).existsSync(), isFalse);
    expect(
      File('${docPath('ghost_doc')}.bak').existsSync(),
      isTrue,
      reason: '前置条件：ghost_doc 只剩侧车，但 load 还能把它读出来',
    );
    expect(await storage.load('ghost_doc'), isNotNull);

    // dead_doc 同时引用 shared（与 ghost_doc 交叉）与 solo（只有自己引用）。
    await storage.save(
      DrawingDocument(
        id: 'dead_doc',
        title: 'dead_doc',
        imageItems: [
          DocumentImageItem(
            id: 'd_i1',
            x: 0,
            y: 0,
            width: 10,
            height: 10,
            filePath: shared,
          ),
          DocumentImageItem(
            id: 'd_i2',
            x: 0,
            y: 0,
            width: 10,
            height: 10,
            filePath: solo,
          ),
        ],
      ),
    );

    expect(await storage.delete('dead_doc'), isTrue);

    expect(
      File(shared).existsSync(),
      isTrue,
      reason: '侧车里那一篇仍在用这张图——回收看不见它就是误删',
    );
    expect(
      File(solo).existsSync(),
      isFalse,
      reason: '反向锁：真正没人引用的一张照样回收，兜底不能变成只增不减',
    );
  });

  test('正文还在时，上一版侧车的引用不算数（否则删掉的引用被永久供起来）', () async {
    // `keep.json.bak` 是上一版，当年引用过 img；现在 `keep.json` 已经不再引用它。
    // 若把侧车也算引用，这张图就**永远**删不掉——每一次成功保存都会留下上一版，
    // 于是「回收」退化为只增不减。第二趟只在正文缺失时启用。
    final storage = StorageService(directoryProvider: () async => tempDir);
    final src = File('${tempDir.path}${Platform.pathSeparator}old_ref.png');
    await src.writeAsBytes(const <int>[7, 7, 7]);
    final img = await storage.storeImage(src.path, 'keep');

    await storage.save(documentWithImage('keep', img)); // v1：引用 img
    await storage.save(
      DrawingDocument(id: 'keep', title: 'keep'),
    ); // v2：不再引用 ⇒ 正文=v2，侧车=v1
    await storage.save(documentWithImage('doomed', img));

    expect(await storage.delete('doomed'), isTrue);
    expect(
      File(img).existsSync(),
      isFalse,
      reason: '当前正文不引用它 ⇒ 该回收；只看「只剩侧车」那一格',
    );
  });

  test('删除文档绝不删除外部图片路径', () async {
    final storage = StorageService(directoryProvider: () async => tempDir);
    final external = File(
      '${tempDir.path}${Platform.pathSeparator}external_user_photo.webp',
    );
    await external.writeAsBytes(Uint8List.fromList(const <int>[8, 9, 10]));
    await storage.save(documentWithImage('external_path', external.path));

    expect(await storage.delete('external_path'), isTrue);
    expect(external.existsSync(), isTrue);
  });
}
