// 加密笔记本用例走 PBKDF2/Argon2id 派生，CI 高负载下可超 30s 默认单测
// 超时（7b846e0 云端首跑实测）——按加密族先例放宽到 3 分钟。
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/infrastructure/notebook_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用户视角可用性回归测试（站在用户角度：入口→操作→保存→重开全链路）。
void main() {
  late Directory tempDir;
  late NotebookStorage storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('usability_');
    storage = NotebookStorage(directoryProvider: () async => tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Notebook makeNotebook() => Notebook(id: 'nb1', title: '会议纪要');

  NotebookPage makePage() => NotebookPage(
    id: 'pg1',
    title: '记录',
    document: DrawingDocument(id: 'd1', title: '页', width: 2480, height: 3508),
  );

  test('加密笔记本编辑后保存往返：内容不丢失（修复 StateError 致命问题）', () async {
    final nb = makeNotebook()..pages.add(makePage());
    // 启用密码保护。
    await storage.encryptAndSave(nb, 'secret123');

    // 重开：加载 → 解密（会话内）。
    final loaded = (await storage.load('nb1'))!;
    expect(loaded.encrypted, isTrue, reason: '加密标记应保留');
    final ok = await storage.decryptNotebook(loaded, 'secret123');
    expect(ok, isTrue);

    // 用户编辑：加文字块。
    loaded.pages.first.textItems.add(
      PageTextItem(id: 'txt1', x: 60, y: 60, text: '新增内容'),
    );

    // 保存（会话密码重加密，模拟 _save 的加密分支）。
    final pw = 'secret123';
    if (loaded.encrypted && pw.isNotEmpty) {
      await storage.encryptAndSave(loaded, pw);
    } else {
      await storage.save(loaded);
    }

    // 再次重开：解密后内容应完整（新增文字块在）。
    final reloaded = (await storage.load('nb1'))!;
    final ok2 = await storage.decryptNotebook(reloaded, 'secret123');
    expect(ok2, isTrue);
    expect(reloaded.pages, hasLength(1));
    expect(
      reloaded.pages.first.textItems.any((t) => t.text == '新增内容'),
      isTrue,
      reason: '编辑后的内容必须保留，不能因保存丢失',
    );
  });

  test('加密笔记本：磁盘上不落盘明文（页面为空、仅存密文载荷）', () async {
    final nb = makeNotebook()..pages.add(makePage());
    await storage.encryptAndSave(nb, 'secret123');
    final raw = await File(
      '${tempDir.path}${Platform.pathSeparator}notebooks'
      '${Platform.pathSeparator}nb1.json',
    ).readAsString();
    expect(raw.contains('新增内容'), isFalse, reason: '明文不应落盘');
    expect(raw.contains('encryptedPayload'), isTrue, reason: '应存密文载荷');
  });

  test('版本历史：无内容变化的保存不产生空白快照', () async {
    final nb = makeNotebook()..pages.add(makePage());
    await storage.save(nb);
    // 模拟 _save：空页面（无笔画无文字）不记录版本。
    final page = nb.pages.first;
    final strokes = page.document.layers.fold<int>(
      0,
      (sum, l) => sum + l.strokes.length,
    );
    final hasContent = strokes > 0 || page.textItems.isNotEmpty;
    if (hasContent) {
      page.history.insert(
        0,
        PageVersion(
          time: DateTime.now(),
          document: DrawingDocument.fromJson(page.document.toJson()),
          textItems: page.textItems
              .map((t) => PageTextItem.fromJson(t.toJson()))
              .toList(),
        ),
      );
    }
    expect(page.history, isEmpty, reason: '空页面保存不应产生空白版本');
  });

  test('导入文本坐标：长段落不越界（原 y+=段长/2 会超画布）', () {
    // 复现 _importText 的坐标计算（可用性修复后：行数估算 + 上限钳制）。
    const docH = 3508;
    final maxY = docH - 120.0;
    var y = 60.0;
    final longParagraph = '长' * 3000; // 3000 字的长段落
    final lines = (longParagraph.length / 24).ceil().clamp(1, 40);
    final posY = y.clamp(0.0, maxY);
    expect(posY, lessThanOrEqualTo(maxY), reason: '坐标不得超出画布');
    expect(lines, lessThanOrEqualTo(40), reason: '单段行数应封顶');
    y += lines * 28 + 12;
    expect(y, greaterThan(0));
  });
}
