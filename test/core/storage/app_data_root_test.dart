// app_data_root_test.dart —— 统一数据根迁移测试（存储收口 + S-02 方案 B）
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir_cleanup.dart';

import 'package:drawing_notes_app/core/storage/app_data_root.dart';

void main() {
  group('S-02（审计 2026-09-27）：云同步 Known Folder 检测', () {
    test('OneDrive KFM 路径特征命中（含大小写/组织后缀变体）', () {
      expect(
        AppDataRoot.isCloudSyncedKnownFolderPath(
          r'C:\Users\a\OneDrive\Documents',
        ),
        isTrue,
      );
      expect(
        AppDataRoot.isCloudSyncedKnownFolderPath(
          r'C:\Users\a\onedrive - contoso\Documents',
        ),
        isTrue,
      );
    });

    test('常规本地路径不命中', () {
      expect(
        AppDataRoot.isCloudSyncedKnownFolderPath(r'C:\Users\a\Documents'),
        isFalse,
      );
      expect(
        AppDataRoot.isCloudSyncedKnownFolderPath('/home/a/Documents'),
        isFalse,
      );
      // 路径段内含 onedrive 子串亦命中（保守策略：宁可多警不漏警）。
      expect(
        AppDataRoot.isCloudSyncedKnownFolderPath(
          r'C:\Users\a\Documents\OneDriveBackup',
        ),
        isTrue,
      );
    });
  });

  late Directory tempDocs;
  late Directory tempSupport;

  setUp(() async {
    tempDocs = await Directory.systemTemp.createTemp('adr_docs_');
    tempSupport = await Directory.systemTemp.createTemp('adr_supp_');
  });

  tearDown(() async {
    await deleteTempDirWithRetry(tempDocs);
    await deleteTempDirWithRetry(tempSupport);
  });

  AppDataRoot build() => AppDataRoot(
    documentsDirProvider: () async => tempDocs,
    supportDirProvider: () async => tempSupport,
  );

  Directory legacy(String name) =>
      Directory('${tempDocs.path}${Platform.pathSeparator}$name');

  File legacyFile(String name) =>
      File('${tempDocs.path}${Platform.pathSeparator}$name');

  test('S-02 方案 B：无旧数据时 root() 位于 ApplicationSupport', () async {
    final root = await build().root();
    expect(root.path, contains(AppDataRoot.defaultRootName));
    expect(root.existsSync(), isTrue);
    expect(
      root.path.startsWith(tempSupport.path),
      isTrue,
      reason: '根目录必须位于注入的 ApplicationSupport 之下（S-02 B）',
    );
    expect(
      root.path.startsWith(tempDocs.path),
      isFalse,
      reason: '数据根不得再落在 Documents Known Folder',
    );
  });

  test('S-02 方案 B：Documents/绘图笔记数据/ 整树迁入 ApplicationSupport', () async {
    final oldRoot = legacy(AppDataRoot.defaultRootName);
    final blockdocs = Directory(
      '${oldRoot.path}${Platform.pathSeparator}blockdocs',
    );
    await blockdocs.create(recursive: true);
    await File('${blockdocs.path}${Platform.pathSeparator}d1.json')
        .writeAsString('{}');
    await File('${oldRoot.path}${Platform.pathSeparator}schedule_events.json')
        .writeAsString('[]');

    final root = await build().root();
    expect(root.path.startsWith(tempSupport.path), isTrue);
    expect(
      File(
        '${root.path}${Platform.pathSeparator}blockdocs'
        '${Platform.pathSeparator}d1.json',
      ).existsSync(),
      isTrue,
      reason: '旧 Documents 根内容必须整体迁入新根',
    );
    expect(
      File('${root.path}${Platform.pathSeparator}schedule_events.json')
          .existsSync(),
      isTrue,
    );
    expect(oldRoot.existsSync(), isFalse, reason: 'move 语义：旧根不再保留');
  });

  test('旧业务子目录整体迁入统一根目录', () async {
    final src = legacy('notebooks');
    await src.create(recursive: true);
    await File('${src.path}${Platform.pathSeparator}nb_1.json')
        .writeAsString('{}');

    final root = await build().root();
    final migrated = Directory(
      '${root.path}${Platform.pathSeparator}notebooks',
    );
    expect(migrated.existsSync(), isTrue);
    expect(
      File('${migrated.path}${Platform.pathSeparator}nb_1.json').existsSync(),
      isTrue,
    );
    // 搬移后旧位置不再保留（move 语义）。
    expect(src.existsSync(), isFalse);
  });

  test('旧散文件迁入统一根目录', () async {
    await legacyFile('schedule_events.json').writeAsString('[]');

    final root = await build().root();
    expect(
      File('${root.path}${Platform.pathSeparator}schedule_events.json')
          .existsSync(),
      isTrue,
    );
    expect(legacyFile('schedule_events.json').existsSync(), isFalse);
  });

  test('旧密钥文件迁入根目录 security/', () async {
    await File('${tempSupport.path}${Platform.pathSeparator}vault.key.json')
        .writeAsString('{}');
    await File('${tempSupport.path}${Platform.pathSeparator}app_lock_guard.key')
        .writeAsString('key');

    final root = await build().root();
    final sec = Directory('${root.path}${Platform.pathSeparator}security');
    expect(
      File('${sec.path}${Platform.pathSeparator}vault.key.json').existsSync(),
      isTrue,
    );
    expect(
      File('${sec.path}${Platform.pathSeparator}app_lock_guard.key')
          .existsSync(),
      isTrue,
    );
    // 支持目录里不再残留密钥。
    expect(
      File('${tempSupport.path}${Platform.pathSeparator}vault.key.json')
          .existsSync(),
      isFalse,
    );
  });

  test('目标已存在时不覆盖（保守策略，绝不丢数据）', () async {
    // 预置：旧目录 Documents/documents 与新根（ApplicationSupport）下的
    // 同名目录同时存在。
    final oldSrc = legacy('documents');
    await oldSrc.create(recursive: true);
    await File('${oldSrc.path}${Platform.pathSeparator}old.json')
        .writeAsString('old');
    final preDst = Directory(
      '${tempSupport.path}${Platform.pathSeparator}'
      '${AppDataRoot.defaultRootName}${Platform.pathSeparator}documents',
    );
    await preDst.create(recursive: true);
    await File('${preDst.path}${Platform.pathSeparator}new.json')
        .writeAsString('new');

    // 迁移执行：目标已存在 → 跳过，源保留在原位。
    final root = await build().root();
    final dst = Directory('${root.path}${Platform.pathSeparator}documents');
    expect(
      File('${dst.path}${Platform.pathSeparator}new.json').existsSync(),
      isTrue,
      reason: '目标内容原样保留',
    );
    expect(
      File('${dst.path}${Platform.pathSeparator}old.json').existsSync(),
      isFalse,
      reason: '目标已存在时不合并/不覆盖',
    );
    expect(oldSrc.existsSync(), isTrue, reason: '源未被动过');
  });

  test('root() 幂等：多次调用返回同一路径', () async {
    final svc = build();
    final a = await svc.root();
    final b = await svc.root();
    expect(a.path, b.path);
  });

  test('dataParentDirectory 返回根的父目录（备份标记定位）', () async {
    final svc = build();
    final root = await svc.root();
    final parent = await svc.dataParentDirectory();
    expect(parent.path, root.parent.path);
  });

  // 构建期数据根隔离口（2026-10-08）：真机集成测试跑在真实 profile 上，
  // 会在用户可见的数据根里造测试文档。隔离口让这类验证改指临时目录。
  group('数据根隔离口 DRAWING_NOTES_DATA_ROOT', () {
    test('未设置 / 纯空白 ⇒ 不生效（生产与单测默认走真实根）', () {
      expect(
        AppDataRoot.effectiveTestDataRoot('', debug: true),
        isNull,
        reason: 'define 未给值时绝不能改变行为',
      );
      expect(
        AppDataRoot.effectiveTestDataRoot('   ', debug: true),
        isNull,
        reason: '空白值按未设置处理，避免把数据根指到 "" 这种歧义路径',
      );
    });

    test('非 debug 构建一律忽略（生产兜底：误带 define 也不受影响）', () {
      expect(
        AppDataRoot.effectiveTestDataRoot('/tmp/x', debug: false),
        isNull,
        reason: 'release/profile 即使带 define 也必须走真实根',
      );
    });

    test('debug + 有值 ⇒ 生效，且首尾空白被裁掉', () {
      expect(
        AppDataRoot.effectiveTestDataRoot('  /tmp/adr_iso  ', debug: true),
        '/tmp/adr_iso',
      );
    });

    test('本测试构建里隔离口处于关闭态 ⇒ 上面所有迁移断言走的是真实路径', () {
      // 反向锁：如果哪天有人给 `flutter test` 默认加上这个 define，
      // 本文件其余用例（验证旧位置迁移）就会静默失效——这条会先红。
      expect(AppDataRoot.usesTestDataRoot, isFalse);
    });

    testWidgets('生效时根路径就是 define 值本身，且不追加 rootName 子目录', (tester) async {
      // `String.fromEnvironment` 是编译期常量，单测里无法注入，
      // 因此这里验的是「生效分支返回 Directory(override)」这条拼接语义：
      // 用同样的入参走纯函数，再与 rootName 拼接规则对比。
      final isolated = AppDataRoot.effectiveTestDataRoot(
        '/tmp/adr_iso',
        debug: true,
      );
      expect(isolated, '/tmp/adr_iso');
      expect(
        isolated!.contains(AppDataRoot.defaultRootName),
        isFalse,
        reason: 'define 值就是根本身；追加子目录会让测试断言无法预知落点',
      );
    });
  });
}
