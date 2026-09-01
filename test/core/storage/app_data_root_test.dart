// app_data_root_test.dart —— 统一数据根迁移测试（存储收口 2026-09-02）
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/storage/app_data_root.dart';

void main() {
  late Directory tempDocs;
  late Directory tempSupport;

  setUp(() async {
    tempDocs = await Directory.systemTemp.createTemp('adr_docs_');
    tempSupport = await Directory.systemTemp.createTemp('adr_supp_');
  });

  tearDown(() async {
    if (await tempDocs.exists()) await tempDocs.delete(recursive: true);
    if (await tempSupport.exists()) await tempSupport.delete(recursive: true);
  });

  AppDataRoot build() => AppDataRoot(
        documentsDirProvider: () async => tempDocs,
        supportDirProvider: () async => tempSupport,
      );

  Directory legacy(String name) => Directory(
        '${tempDocs.path}${Platform.pathSeparator}$name',
      );

  File legacyFile(String name) => File(
        '${tempDocs.path}${Platform.pathSeparator}$name',
      );

  test('无旧数据时：root() 直接创建统一根目录', () async {
    final root = await build().root();
    expect(root.path, contains(AppDataRoot.defaultRootName));
    expect(await root.exists(), isTrue);
    expect(
      root.path.startsWith(tempDocs.path),
      isTrue,
      reason: '根目录必须位于注入的系统文档目录之下',
    );
  });

  test('旧业务子目录整体迁入统一根目录', () async {
    final src = legacy('notebooks');
    await src.create(recursive: true);
    await File('${src.path}${Platform.pathSeparator}nb_1.json')
        .writeAsString('{}');

    final root = await build().root();
    final migrated = Directory('${root.path}${Platform.pathSeparator}notebooks');
    expect(await migrated.exists(), isTrue);
    expect(await File('${migrated.path}${Platform.pathSeparator}nb_1.json')
        .exists(), isTrue);
    // 搬移后旧位置不再保留（move 语义）。
    expect(await src.exists(), isFalse);
  });

  test('旧散文件迁入统一根目录', () async {
    await legacyFile('schedule_events.json').writeAsString('[]');

    final root = await build().root();
    expect(
      await File(
        '${root.path}${Platform.pathSeparator}schedule_events.json',
      ).exists(),
      isTrue,
    );
    expect(await legacyFile('schedule_events.json').exists(), isFalse);
  });

  test('旧密钥文件迁入根目录 security/', () async {
    await File(
      '${tempSupport.path}${Platform.pathSeparator}vault.key.json',
    ).writeAsString('{}');
    await File(
      '${tempSupport.path}${Platform.pathSeparator}app_lock_guard.key',
    ).writeAsString('key');

    final root = await build().root();
    final sec = Directory('${root.path}${Platform.pathSeparator}security');
    expect(
      await File('${sec.path}${Platform.pathSeparator}vault.key.json').exists(),
      isTrue,
    );
    expect(
      await File(
        '${sec.path}${Platform.pathSeparator}app_lock_guard.key',
      ).exists(),
      isTrue,
    );
    // 支持目录里不再残留密钥。
    expect(
      await File(
        '${tempSupport.path}${Platform.pathSeparator}vault.key.json',
      ).exists(),
      isFalse,
    );
  });

  test('目标已存在时不覆盖（保守策略，绝不丢数据）', () async {
    // 预置：旧目录 Documents/documents 与新根目录下的同名目录同时存在。
    final oldSrc = legacy('documents');
    await oldSrc.create(recursive: true);
    await File('${oldSrc.path}${Platform.pathSeparator}old.json')
        .writeAsString('old');
    final preDst = Directory(
      '${tempDocs.path}${Platform.pathSeparator}'
      '${AppDataRoot.defaultRootName}${Platform.pathSeparator}documents',
    );
    await preDst.create(recursive: true);
    await File('${preDst.path}${Platform.pathSeparator}new.json')
        .writeAsString('new');

    // 迁移执行：目标已存在 → 跳过，源保留在原位。
    final root = await build().root();
    final dst = Directory('${root.path}${Platform.pathSeparator}documents');
    expect(
      await File('${dst.path}${Platform.pathSeparator}new.json').exists(),
      isTrue,
      reason: '目标内容原样保留',
    );
    expect(
      await File('${dst.path}${Platform.pathSeparator}old.json').exists(),
      isFalse,
      reason: '目标已存在时不合并/不覆盖',
    );
    expect(await oldSrc.exists(), isTrue, reason: '源未被动过');
  });

  test('root() 幂等：多次调用返回同一路径', () async {
    final svc = build();
    final a = await svc.root();
    final b = await svc.root();
    expect(a.path, b.path);
  });
}
