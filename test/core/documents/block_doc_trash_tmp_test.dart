// 由 Claude 团队生成 | Drawing Notes App

/// 块文档回收站那条腿的**裸 `.tmp`** 必须在失败路径被自己清掉（R52，第五轮采集 F-01）。
///
/// 为什么单独钉这一条：全仓那套孤儿清扫（`core/storage/stale_tmp_cleanup.dart`）的判据
/// **只认带本地生成器 id 的形状**，而这条腿写的两枚临时文件是裸的
/// （`<回收站文件>.tmp` 与 `<回收站文件>.meta.tmp`）⇒ 清扫故意不碰它们；
/// `listTrash`/`purgeExpiredTrash` 又只认 `.json` ⇒ 也没人看得见。
/// 于是「谁来清它们」这个问题只有唯一一个答案：**这条腿自己的失败路径**。
/// 我写 R41 那条注释时就是这个说法（「它们的清理归各自那条腿的失败路径」），
/// 但当时这条腿**根本没有失败路径**——两枚 tmp 的 `writeAsString` + `rename` 裸在外面，
/// 磁盘满或被杀软占用时就留下一枚装着删除时间、甚至装着整篇正文的明文副本。
/// 本文件两半各自把这个说法钉成机器事实：① 真造一次失败（把 `.meta.json` 那个位置
/// 预先做成目录，Windows/POSIX 上 rename 过去都会失败），看残不留；
/// ② 源码级判据：每条裸 tmp 都必须有对应的 `_discardTemp`，且能被突变抓到。
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc_store.dart';

void main() {
  late Directory tempDir;
  late NoteBlockDocStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('blockdoc_trash_tmp_');
    store = NoteBlockDocStore(directoryProvider: () async => tempDir);
  });
  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> put(String id, String title) => store.saveDocument(
    NoteBlockDoc(
      id: id,
      title: title,
      body: const [],
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    ),
  );

  List<File> tempsOnDisk() => tempDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.tmp'))
      .toList();

  test('前置：正常删除不留任何 .tmp（这条不红不代表下面那条有意义）', () async {
    await put('t1', '将被删除');
    expect(tempsOnDisk(), isEmpty);
    await store.deleteDocument('t1');
    expect(tempsOnDisk(), isEmpty, reason: '成功路径的 rename 会把 tmp 换走，不留副本');
  });

  test('meta 侧车换入失败 ⇒ 抛出，且**不留下装着删除时间的明文 tmp**', () async {
    await put('t2', '删除时侧车写不进');
    // 回收站落点是 `<数据根>/blockdocs_trash/<id>.json`，侧车是它后面加 `.meta.json`
    // （见 `_trashPathFor`）。把侧车的**目标位置**预先做成一个目录：`rename` 到目录上
    // 在 Windows 与 POSIX 都会失败 ⇒ 不用往生产代码里塞故障钩子就能造出这一格。
    Directory(
      '${tempDir.path}${Platform.pathSeparator}blockdocs_trash',
    ).createSync(recursive: true);
    Directory(
      '${tempDir.path}${Platform.pathSeparator}blockdocs_trash'
      '${Platform.pathSeparator}t2.json.meta.json',
    ).createSync();

    await expectLater(store.deleteDocument('t2'), throwsA(anything));
    expect(
      tempsOnDisk(),
      isEmpty,
      reason: '清扫判据故意不收裸 .tmp ⇒ 这条腿不留失败路径就是永久残留（明文侧车）',
    );
  });

  group('源码级判据：每条裸 tmp 都要有自己的失败路径', () {
    const target = 'lib/core/documents/note_block_doc_store_trash.dart';
    final discardCall = RegExp(r'_discardTemp\((\w+)\)');

    test('抽取本身要扫得到东西（空集不算通过）', () {
      final decls = tmpDecls(File(target).readAsStringSync());
      // 实测 2026-10-18：这条腿有 2 枚裸 tmp（meta 侧车 + 回退用的整篇副本）。
      expect(decls.length, 2, reason: '不是 2 就说明抽取或这条腿的形状变了：$decls');
    });

    test('每一枚都有对应的 _discardTemp', () {
      final src = File(target).readAsLinesSync();
      final declared = tmpDecls(File(target).readAsStringSync());
      final discarded = <String>{};
      for (final line in src) {
        // 显式判空，不用 `case final m`：变量模式连 null 都匹配，
        // 那时 `m.group(1)` 会在没命中的行上直接抛（本仓踩过）。
        final m = discardCall.firstMatch(line);
        if (m != null) discarded.add(m.group(1)!);
      }
      for (final name in declared) {
        expect(
          discarded,
          contains(name),
          reason: '$name 写废之后没有任何人回收它 ⇒ 明文残留在回收站目录里',
        );
      }
    });

    test('判据自证：删掉 catch 里的 _discardTemp 就红', () {
      const withoutGuard = "  final tmp = File('\$x.tmp');\n  await tmp.writeAsString('');\n";
      expect(tmpDecls(withoutGuard), ['tmp']);
      expect(
        RegExp(r'_discardTemp\(\w+\)').hasMatch(withoutGuard),
        isFalse,
        reason: '这条不红就等于判据只在真文件上成立，换个形状就瞎',
      );
    });
  });
}

/// 一个源文本里所有「裸 tmp 声明」的变量名。
List<String> tmpDecls(String src) => [
  for (final m in RegExp(r"final (\w+) = File\('[^']*\.tmp'\);").allMatches(src))
    m.group(1)!,
];
