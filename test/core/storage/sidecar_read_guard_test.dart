// 侧车注册表（标签 / 收藏）的三态读取与覆盖前抢救（审计 2026-10-16：STO-004 可观测半边）。
//
// 缺陷形状：两个 store 的读都写成 `catch (_) => 空集合`，于是「文件在、但读不出来」与
// 「文件不存在」给的是**同一个答案**；而它们的写是「整体覆盖」（读全表 → 改 → 写回）。
// 一次半写 / 一次读失败之后，用户下一次加标签或收藏，就把原本还在盘上的整表**抹成
// 只剩新加的那一条**，而且没有任何痕迹。这是 §4 第 1 条（本仓头号复发形态）的第五、六格：
// SYN-D1 块文档、STO-001 保险库、STO-012 操作日志、FDC-01 富文本 spans 之后。
//
// 本批**只买两件事**，都不改产品语义（调用方继续拿到空集合、写照样成功）：
//   ① 三态分清楚 + 「读不出来」落一条可查的审计；
//   ② 整体覆盖**之前**把那份读不出来的原件**复制**成 `<文件>.corrupt-<utc>-<随机>`
//     （复制不移动：移动会拆掉后续读取与人工取证唯一的原件）。
// 「读不出来就**拒绝**覆盖」那半边是默认阻断 ⇒ 台账 §5 明列需业主点名，本批不做。
//
// 判据只有 `sidecar_read_guard.dart` 一份，标签与收藏**共用**（§4 第 2 条：不再抄第二份）。
//
// 突变自证（基线 = 本文件 10 条全绿；每条实测后还原，计数是**本文件单独跑**的 +绿 −红）：
// 突变自证（基线 = 本文件 **13 条全绿**；每条实测后还原，计数是本文件单独跑的 +绿 −红）：
//   G1 判据把 unreadable 塌成 absent   ⇒ +5 −8（三态表 + 全部抢救用例 + 两条接线 + 同名目录格）
//   G2 抢救不看盘上状态、恒复制        ⇒ +10 −3（两条反向锁 + 「已被修好」那条）
//   G3 复制改成移动（rename）          ⇒ +12 −1（**只有直接下断言那条红**，见下）
//   G4 忽略「每实例只复制一份」         ⇒ +11 −2
//   G5 复制时机挪到覆盖之后            ⇒ **未做**：`_writeTags` 里没有可安全注入的时机缝，
//        硬挪会连带动到 rename 的失败回退腿；这一面改由「写之前已被修好 ⇒ 不复制」那条用例
//        从行为侧钉住（G2 塌掉状态判据时它就是红的）。
//   G6 接线形同未接（preserve 恒空转）   ⇒ +8 −5
//   G7 拆掉「读不出来」的可见提示        ⇒ +10 −3
//   G8 拆掉 provider 失败的兜底         ⇒ +12 −1（异常会直接冒到 UI）
//
// **已知未测的一支**（别当成已覆盖）：`preserveUnreadableSidecar` 里 `file.copy` 自身失败
// ⇒ 落 `…_preserve_failed`、返回 null、不阻断写入。造它需要「文件存在、但 copy 会失败」的
// 形状：POSIX 的 chmod 000 在 Windows 上不生效；同名目录/悬空符号链接都被 `File.existsSync()`
// 判成 absent（后者我在用例里实测记录了，Windows 建链接还要特权）⇒ 两端都能确定复现的办法
// 没找到。这一支留作**待验清单**，不是绿。
//
// 三处自造的坑，记下来给下一轮别再踩：
//   · **子串遮蔽**：断言 `contains('…sidecar_unreadable')` 会被另一条审计
//     `…sidecar_unreadable_preserved` 满足——G7 第一次跑只红 1 条就是这个原因。
//     现在断言写全 `… FAIL`（提示那条 success:false，保留件那条是 OK），互不遮蔽。
//   · **突变自己把语法改坏**会伪装成结果：G7 第一版把注释写在 `);` 之前，`//` 吞掉收尾括号
//     ⇒ 整个文件编译失败，`grep -c '[E]$'` 数出 1，看着像「只红一条」，实际**一条都没跑**。
//   · **突变打错位置**会伪装成「门禁有效」：G8 第一版的正则匹配到 `preserve` 末尾那个
//     `return null`（文件里有两处），报「全绿」＝测了一个不存在的东西。
//     现在流程固定：先 grep 回显突变标记（确认**落在哪个函数、共几处**），再看输出的**末行**
//     （`All tests passed` / `Some tests failed`），不相信自己数的计数。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/storage/sidecar_read_guard.dart';
import 'package:drawing_notes_app/core/storage/tag_store.dart';
import 'package:drawing_notes_app/features/all_docs/infrastructure/favorite_store.dart';

import '../../helpers/temp_dir_cleanup.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sidecar_guard_');
    AuditLogger.clear();
  });

  tearDown(() async {
    await deleteTempDirWithRetry(root);
  });

  File put(String rel, List<int> bytes) {
    final f = File('${root.path}${Platform.pathSeparator}$rel');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(Uint8List.fromList(bytes), flush: true);
    return f;
  }

  List<String> corruptedNames() => root
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.contains('.corrupt-'))
      .toList();

  group('判据：三态（一份定义，两处共用）', () {
    test('absent / readable / unreadable 是三个不同答案，四条 unreadable 成因都得分类', () async {
      final cases = <({String rel, List<int> bytes, String key, SidecarRead want})>[
        (
          rel: 'never_written.json',
          bytes: utf8.encode('{}'),
          key: 'tags',
          want: SidecarRead.absent,
        ),
        (
          rel: 'ok_tags.json',
          bytes: utf8.encode('{"tags":[{"id":"t1","name":"甲","color":"0xFFFF0000",'
              '"createdAt":"2026-10-01T00:00:00.000Z"}]}'),
          key: 'tags',
          want: SidecarRead.readable,
        ),
        (
          rel: 'ok_favorites.json',
          bytes: utf8.encode('{"favorites":["canvas:a"]}'),
          key: 'favorites',
          want: SidecarRead.readable,
        ),
        // 半写截断：原子写被杀在 write 与 rename 之间时，盘上看到的就是这种
        (
          rel: 'truncated.json',
          bytes: utf8.encode('{"tags":[{"id":"t1","name":"甲"'),
          key: 'tags',
          want: SidecarRead.unreadable,
        ),
        // 非法 UTF-8：readAsString 走 utf8 解码，抛的是 FormatException 而非 IO 异常
        (
          rel: 'binary.json',
          bytes: Uint8List.fromList([0xFF, 0xFE, 0xC0, 0x80, 0x00, 0x90]),
          key: 'tags',
          want: SidecarRead.unreadable,
        ),
        // 顶层不是 Map（旧版本 / 别的写入者留下的形状）
        (
          rel: 'list_top.json',
          bytes: utf8.encode('["a","b"]'),
          key: 'tags',
          want: SidecarRead.unreadable,
        ),
        // 清单那一格不是 List
        (
          rel: 'not_list.json',
          bytes: utf8.encode('{"tags":{"a":1}}'),
          key: 'tags',
          want: SidecarRead.unreadable,
        ),
        // 键名不对（拿收藏文件当标签表读，或反过来）
        (
          rel: 'wrong_key.json',
          bytes: utf8.encode('{"favorites":[]}'),
          key: 'tags',
          want: SidecarRead.unreadable,
        ),
      ];
      // 分母下限先于结论：表缩水或被改成单一状态时，判据塌掉也照样「全对」。
      expect(cases.length, greaterThanOrEqualTo(7));
      for (final state in SidecarRead.values) {
        expect(
          cases.where((c) => c.want == state).length,
          greaterThanOrEqualTo(1),
          reason: '$state 这一态必须至少有一格被测到',
        );
      }
      expect(
        cases.where((c) => c.want == SidecarRead.unreadable).length,
        greaterThanOrEqualTo(5),
        reason: 'unreadable 的成因少于 5 格 ⇒ 判据的覆盖面悄悄缩了',
      );
      for (final c in cases) {
        // absent 那一格读一个**不存在**的路径，其余先落盘再读。
        if (c.want != SidecarRead.absent) put(c.rel, c.bytes);
        final path = '${root.path}${Platform.pathSeparator}'
            '${c.want == SidecarRead.absent ? 'none_${c.rel}' : c.rel}';
        expect(
          readSidecarList(File(path), c.key).state,
          c.want,
          reason: '${c.rel} 用键 ${c.key} 应判为 ${c.want}',
        );
      }
    });

    test('个别条目坏仍是 readable（条目级损坏不能升格成整表事故）', () async {
      put(
        'mixed.json',
        utf8.encode(
          '{"tags":[{"id":"t1","name":"甲","color":"0xFF000000",'
          '"createdAt":"2026-10-01T00:00:00.000Z"},{"id":"broken"}]}',
        ),
      );
      final read = readSidecarList(
        File('${root.path}${Platform.pathSeparator}mixed.json'),
        'tags',
      );
      expect(read.state, SidecarRead.readable);
      expect(read.items.length, 2, reason: '判据只管表，不管条目');
      // 条目级 fail-closed 归 store：坏条目跳过、好条目留下（这条区分不能反——
      // 若把「有坏条目」也升格成 unreadable，正常表每次读都会被记成事故并白白复制原件）。
      put(
        'all_docs_tags.json',
        utf8.encode(
          '{"tags":[{"id":"t1","name":"甲","color":"0xFF000000",'
          '"createdAt":"2026-10-01T00:00:00.000Z"},{"id":"broken"}]}',
        ),
      );
      final store = TagStore(directoryProvider: () async => root);
      expect((await store.listTags()).map((t) => t.name), ['甲']);
      expect(corruptedNames(), isEmpty, reason: '坏一条条目不该惊动原件');
      expect(
        AuditLogger.snapshot().join('\n'),
        isNot(contains('sidecar_unreadable')),
      );
    });
  });

  group('抢救：整体覆盖之前复制原件（复制不移动）', () {
    test('读不出来时复制一份 .corrupt-*，原件仍在，写入照常成功（非阻断）', () async {
      final corrupt = utf8.encode('{"tags":[{"id":"t1","name":"甲"');
      put('all_docs_tags.json', corrupt);
      final store = TagStore(directoryProvider: () async => root);
      await store.addTag('新标签');

      final kept = corruptedNames();
      expect(kept, hasLength(1), reason: 'G2：不看状态就复制 / G6：拆掉接线都会红');
      final keptFile = File('${root.path}${Platform.pathSeparator}${kept.single}');
      expect(
        keptFile.readAsBytesSync(),
        corrupt,
        reason: '保留件必须逐字节是事故当时那份原件，不是重写后的内容',
      );
      expect(
        File('${root.path}${Platform.pathSeparator}all_docs_tags.json').existsSync(),
        isTrue,
        reason: '复制而非移动：G3 改成 rename 时这里红——原件是唯一的取证依托',
      );
      final audit = AuditLogger.snapshot().join('\n');
      expect(audit, contains('tag_registry.sidecar_unreadable_preserved'));
      // 覆盖仍然发生（今天的产品语义，未变）：新表只含刚加的那一条。
      final tags = await store.listTags();
      expect(tags.map((t) => t.name), ['新标签']);
    });

    test('直接调判据：复制之后**原件必须还在原位、字节不变**（这一条先前被 store 用例漏掉）', () async {
      // 先前把「复制不移动」的断言挂在 store 的 addTag 之后，结果 G3（copy→rename）实测**照样全绿**：
      // addTag 紧接着的整体覆盖会把主文件**重新造出来**，于是 `existsSync()` 为真——断言成立的
      // 理由是错的。要钉「移动会拆掉回退腿」这件事，只能在**覆盖发生之前**、直接对判据下断言：
      // 那一刻若主文件没了，写入一旦失败（磁盘满 / 句柄占用 / 进程被杀），用户看到的
      // 就是「一个标签都没有」，而原件只躺在 .corrupt-* 里没人认得。
      final original = utf8.encode('{"tags":[{"id":"t1","name":"甲"');
      final file = put('direct_tags.json', original);
      final kept = await preserveUnreadableSidecar(
        file,
        listKey: 'tags',
        auditScope: 'direct',
        alreadyPreserved: false,
      );
      expect(kept, isNotNull, reason: '读不出来 ⇒ 该复制一份');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'G3 那一次突变证明：这个断言必须由判据自己下，不能让写入去补',
      );
      expect(file.readAsBytesSync(), original, reason: '原位那份还得逐字节是原件');
      expect(File(kept!).readAsBytesSync(), original, reason: '两份都必须是原件');
      // alreadyPreserved 为真时直接不动（每实例只复制一份）：G4 的靶子。
      expect(
        await preserveUnreadableSidecar(
          file,
          listKey: 'tags',
          auditScope: 'direct',
          alreadyPreserved: true,
        ),
        isNull,
        reason: '已复制过 ⇒ 一份都不许再造',
      );
    });

    test('命名形状：.corrupt-<utc 数字戳>-<8 位十六进制>', () async {
      put('all_docs_tags.json', utf8.encode('{"tags":[{"id":"t1","name":"甲"'));
      await TagStore(directoryProvider: () async => root).addTag('甲');
      final name = corruptedNames().single;
      expect(
        RegExp(r'^all_docs_tags\.json\.corrupt-[0-9]{14,20}-[0-9a-f]{8}$').hasMatch(name),
        isTrue,
        reason: '实际名字：$name（时间戳保证有序、随机段保证同微秒不撞名）',
      );
    });

    test('能读 / 缺席时一份都不造（反向锁：正常路径不许长垃圾）', () async {
      put(
        'all_docs_tags.json',
        utf8.encode(
          '{"tags":[{"id":"t1","name":"旧甲","color":"0xFF000000",'
          '"createdAt":"2026-10-01T00:00:00.000Z"}]}',
        ),
      );
      final readable = TagStore(directoryProvider: () async => root);
      await readable.addTag('新乙');
      expect(corruptedNames(), isEmpty, reason: 'G2：任何情况都复制 ⇒ 这里红');
      expect(
        AuditLogger.snapshot().join('\n'),
        isNot(contains('sidecar_unreadable')),
        reason: '能读的表不该被记成事故',
      );
      expect((await readable.listTags()).map((t) => t.name), ['旧甲', '新乙']);

      final absent = TagStore(directoryProvider: () async => root);
      await absent.addTag('零标签起步');
      expect(corruptedNames(), isEmpty, reason: 'G2：absent 也不许复制');
    });

    test('每实例只复制一份（否则注册表一直坏时每次写都多一份残缺副本）', () async {
      put('all_docs_tags.json', utf8.encode('{"tags":[{"id":"t1","name":"甲"'));
      final store = TagStore(directoryProvider: () async => root);
      await store.addTag('第一次');
      // 再坏一次：模拟覆盖后仍然是半写状态（第二次复制的已经是上一次的产物，无取证价值）
      put('all_docs_tags.json', utf8.encode('{"tags":[{"id":"t2","name":"乙"'));
      await store.addTag('第二次');
      expect(corruptedNames(), hasLength(1), reason: 'G4：忽略 alreadyPreserved ⇒ 2 份 ⇒ 这里红');
    });

    test('写之前原件已被别的会话修好 ⇒ 不复制（防把好消息据成事故证据）', () async {
      put('all_docs_tags.json', utf8.encode('{"tags":[{"id":"t1","name":"甲"'));
      final store = TagStore(directoryProvider: () async => root);
      // 先把判据打成 unreadable（落一条审计，_unreadableNoted 置位）
      expect(await store.listTags(), isEmpty);
      expect(AuditLogger.snapshot().join('\n'), contains('tag_registry.sidecar_unreadable FAIL'));
      // 盘上被修好了
      put(
        'all_docs_tags.json',
        utf8.encode(
          '{"tags":[{"id":"t9","name":"修好了","color":"0xFF00FF00",'
          '"createdAt":"2026-10-02T00:00:00.000Z"}]}',
        ),
      );
      await store.addTag('新添');
      expect(corruptedNames(), isEmpty, reason: 'G5：复制与否由写前的重读决定，不是缓存的判据');
      expect((await store.listTags()).map((t) => t.name), containsAll(['修好了', '新添']));
    });
    test('同名位置上顶着一个目录 ⇒ 判据答 absent，不谎报事故、不复制、不动原件', () async {
      // 这条先前写成了「应判 unreadable」，实测红给我看：`File.existsSync()` 对**目录**
      // 返回 false，所以同名目录在 File 句柄眼里就是「不在」。改断言迁就实现之前先想清楚
      // 哪个答案才是对的：这里 absent 是对的——那个目录不是注册表，把它说成「读不出来的
      // 事故原件」会让抢救去复制一个目录、并把真正的空表用户记成受害者。
      final shadow = Directory('${root.path}${Platform.pathSeparator}shadow_tags.json');
      shadow.createSync();
      expect(readSidecarList(File(shadow.path), 'tags').state, SidecarRead.absent);
      expect(
        await preserveUnreadableSidecar(
          File(shadow.path),
          listKey: 'tags',
          auditScope: 'shadow',
          alreadyPreserved: false,
        ),
        isNull,
      );
      expect(shadow.existsSync(), isTrue, reason: '任何分支都不许动原件');
      expect(corruptedNames(), isEmpty);
    });

    // ⚠ 已知**未测**的一支（别当成覆盖了）：`preserveUnreadableSidecar` 里
    // `file.copy` 抛 FileSystemException ⇒ 落 `…_preserve_failed` 审计、返回 null、不阻断写入。
    // 想造它需要一个「存在、但读得动/复制不动」的文件：POSIX 的 chmod 000 在 Windows 上不生效，
    // 悬空符号链接又会被 existsSync 判成 absent，两端都能确定复现的办法我没有找到 ⇒
    // 这一支留作**待验清单**（需业主许可的故障注入钩子，或只在 Linux runner 上跑的分片）。
  });

  group('两个 store 的真实接线（光有判据没接上等于没修）', () {
    test('标签注册表：坏表 + addTag ⇒ 原件保留、审计两条都在', () async {
      put('all_docs_tags.json', utf8.encode('{"tags":['));
      final store = TagStore(directoryProvider: () async => root);
      await store.addTag('接线验证');
      final audit = AuditLogger.snapshot().join('\n');
      expect(audit, contains('tag_registry.sidecar_unreadable FAIL'), reason: 'G7：拆掉提示 ⇒ 这里红');
      expect(audit, contains('tag_registry.sidecar_unreadable_preserved'));
      expect(corruptedNames(), hasLength(1));
      // STO-004 乙（2026-10-16）：这份原件还得**说给用户**，光进审计等于没说。
      // store 只交出事实（文件名），句子由 `AppSnack` 一处组装。
      expect(
        store.salvagedOriginalName,
        corruptedNames().single,
        reason: '交给展示层的必须是真躺在盘上那份，不能是另编的名字',
      );
    });

    test('收藏集合：同一份判据、同一条接线（DOC-12）', () async {
      final original = utf8.encode('{"favorites":["canvas:old1","blockdoc:old2"');
      put('all_docs_favorites.json', original);
      final store = FavoriteStore(directoryProvider: () async => root);
      await store.addKey('canvas:new');

      final kept = corruptedNames();
      expect(kept, hasLength(1), reason: '判据共用一份，但接线是各接各的——少一条这里就红');
      expect(
        File('${root.path}${Platform.pathSeparator}${kept.single}').readAsBytesSync(),
        original,
      );
      final audit = AuditLogger.snapshot().join('\n');
      expect(audit, contains('favorites.sidecar_unreadable FAIL'));
      expect(audit, contains('favorites.sidecar_unreadable_preserved'));
      expect(await store.loadKeys(), {'canvas:new'}, reason: '覆盖仍发生（语义未变）');
      // STO-004 乙：收藏侧同样要把这份原件的名字交给展示层。
      expect(store.salvagedOriginalName, kept.single);

      // 反向锁：同一目录里收藏正常读写时**不许再多长**垃圾（这里已有上面那 1 份保留件，
      // 所以判据是「数量不增」而不是 isEmpty——写错成 isEmpty 会永远红，别照抄）。
      final before = corruptedNames().length;
      final clean = FavoriteStore(directoryProvider: () async => root);
      await clean.addKey('canvas:a');
      await clean.toggleKey('canvas:a');
      expect(corruptedNames(), hasLength(before));
    });
  });

  group('目录提供者自己失败时不许变成新故障源（本批改判据时差点弄丢的那条容错）', () {
    test('provider 抛 ⇒ 两个 store 都按空集合返回，绝不把异常抛给 UI', () async {
      // 改动前两个 store 的整个读都包在 `catch (_) => 空集合` 里，`await _fileRef()`
      // 也在其中；把判据换成 readSidecarList 时它被挪到 try 之外，那条容错就悄悄没了
      // ——UI 会从「显示空列表」变成「抛异常」。这条用例钉住它不能没（G8 的靶子）。
      final tags = TagStore(
        directoryProvider: () async => throw StateError('path_provider 在本平台不可用'),
      );
      final favs = FavoriteStore(
        directoryProvider: () async => throw StateError('path_provider 在本平台不可用'),
      );
      expect(await tags.listTags(), isEmpty, reason: 'G8：拆掉兜底 ⇒ 这里直接抛');
      expect(await favs.loadKeys(), isEmpty, reason: 'G8：同上');
      expect(
        AuditLogger.snapshot().join('\n'),
        isNot(contains('sidecar_unreadable')),
        reason: '提供者失败不是「注册表读不出来」，不许混进同一族判据（混了会白白复制原件）',
      );
    });

    test('provider 正常时不影响任何既有行为（反向锁）', () async {
      final tags = TagStore(directoryProvider: () async => root);
      await tags.addTag('正常路径');
      expect((await tags.listTags()).map((t) => t.name), ['正常路径']);
      expect(corruptedNames(), isEmpty);
      // 反向锁：没抢救过就一个字都不许说——把门禁练成哭墙，用户会忽略真的那一次。
      expect(tags.salvagedOriginalName, isNull);
    });
  });
}
