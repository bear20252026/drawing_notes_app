// 独立画布文字块的落盘往返（交接文档核心价值 #2：保存→重开内容必须一致）。
//
// 独立画布模式下文字工具写入 `document.textItems`
// （`editor_page_actions.dart:460` 注释即「独立画布模式回退到
// document.textItems」，绘制端见 `editor_page_canvas_surface.dart:24`），
// 但 `DocumentCodec.snapshotOf`/解码两侧都没有 `textItems` 这一项——
// 本文件把「打了字、存了盘、重开字还在」这条链路的真实结果核一遍。

import 'dart:convert';
import 'dart:io';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/canvas_model/text_item.dart';
import 'package:drawing_notes_app/core/storage/storage_service.dart';
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/temp_dir_cleanup.dart';

void main() {
  late Directory tempDir;
  late StorageService repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('canvas_text_roundtrip_');
    repo = StorageService(directoryProvider: () async => tempDir);
  });
  tearDown(() async => deleteTempDirWithRetry(tempDir));

  test('画布文字块保存重开后逐字段保留', () async {
    final c = DrawingController(
      DrawingDocument(id: 'text_doc', title: '文字', width: 240, height: 200),
    );
    c.document.textItems.add(
      PageTextItem(
        id: 't1',
        x: 20,
        y: 30,
        text: '待办清单',
        fontSize: 28,
        bold: true,
        align: TextAlignType.center,
      ),
    );
    final path = await repo.save(c.document);
    c.dispose();

    // 磁盘形态里必须带着文字项，否则后面一切都不可能成立。
    final onDisk = jsonDecode(await File(path).readAsString()) as Map;
    final document = onDisk['document'] as Map;
    expect(
      document.containsKey('textItems'),
      isTrue,
      reason: '落盘 JSON 必须包含 textItems，否则画布文字永远不可能重开还原',
    );

    final reloaded = await repo.load('text_doc');
    expect(reloaded, isNotNull);
    expect(
      reloaded!.textItems,
      hasLength(1),
      reason: '用户打上去的字不得静默消失',
    );
    final item = reloaded.textItems.single;
    expect(item.id, 't1');
    expect(item.text, '待办清单');
    expect(item.x, 20);
    expect(item.y, 30);
    expect(item.fontSize, 28);
    expect(item.bold, isTrue);
    expect(item.align, TextAlignType.center);
  });

  test('便利贴与待办项的文字属性也随文档往返', () async {
    final c = DrawingController(
      DrawingDocument(id: 'text_sticky', title: '标签', width: 240, height: 200),
    );
    c.document.textItems.addAll([
      PageTextItem(id: 's1', x: 10, y: 10, text: '标签', isSticky: true),
      PageTextItem(id: 'd1', x: 10, y: 60, text: '买牛奶', isTodo: true),
    ]);
    await repo.save(c.document);
    c.dispose();

    final reloaded = await repo.load('text_sticky');
    expect(reloaded!.textItems, hasLength(2));
    expect(reloaded.textItems.first.isSticky, isTrue);
    expect(reloaded.textItems.last.isTodo, isTrue);
  });
}
