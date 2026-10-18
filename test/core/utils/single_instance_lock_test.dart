import 'dart:io';

import 'package:drawing_notes_app/core/utils/single_instance.dart';
import 'package:flutter_test/flutter_test.dart';

/// ASM-02 单实例检测（`lib/core/utils/single_instance.dart`）。
///
/// 这批用例钉的是**两条相反方向**的断言（本仓做安全语义改动必守的口径）：
/// ① 检测要能说出事实（四格状态各自可达、互不冒充）；
/// ② 检测**永远不许阻止启动**（任何输入都不抛、不 hang、不返回「别起来」）。
/// 少了 ① 就是一句空话，少了 ② 会把「应用打不开」那条历史投诉重新请回来。
///
/// R51 加的是「同根判定」这一半：锁文件路径是应用全局的，光看它在不在会把
/// 「两个实例各开各的数据根」也判成同一个实例 ⇒ 那一格必须**不出声**。
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('single_instance_test');
    instanceStatusAtLaunch = null;
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  const rootA = '/data/rootA';
  const rootB = '/data/rootB';

  File lockIn(Directory dir) =>
      File('${dir.path}${Platform.pathSeparator}app.lock');

  /// 预置一个锁文件：PID [pid]，数据根 [root]（null = 老格式，只写 PID 一行）。
  File seedLock(int pid, {String? root}) {
    final body = root == null ? '$pid' : '$pid\n$root';
    return lockIn(tmp)..writeAsStringSync(body);
  }

  SingleInstanceLock lockWith({required bool Function(int pid) alive}) =>
      SingleInstanceLock(
        lockFile: lockIn(tmp),
        isProcessAlive: (pid) async => alive(pid),
      );

  test('干净启动：拿到锁，锁里写的是「本进程 PID + 本实例数据根」两行', () async {
    final lock = lockWith(alive: (_) => false);
    expect(
      await lock.acquire(currentPid: 4242, dataRootKey: rootA),
      SingleInstanceStatus.acquired,
    );
    expect(lock.holdsLock, isTrue);
    expect(lockIn(tmp).readAsStringSync(), '4242\n$rootA');
    expect(await lock.recordedDataRoot(), rootA);
  });

  test('陈旧锁（记录的 PID 已不存活）：回收后照常拿锁', () async {
    seedLock(9999, root: rootB);
    final lock = lockWith(alive: (pid) {
      expect(pid, 9999);
      return false;
    });
    expect(
      await lock.acquire(currentPid: 1111, dataRootKey: rootA),
      SingleInstanceStatus.acquired,
    );
    expect(lockIn(tmp).readAsStringSync(), '1111\n$rootA');
  });

  group('同根判定（R51 的那一半）', () {
    test('活跃锁 + 同一个数据根 ⇒ sameDataRootRunning，且**不许动别人的锁文件**', () async {
      final seeded = seedLock(8888, root: rootA);
      final lock = lockWith(alive: (_) => true);
      expect(
        await lock.acquire(currentPid: 1111, dataRootKey: rootA),
        SingleInstanceStatus.sameDataRootRunning,
      );
      expect(lock.holdsLock, isFalse);
      expect(seeded.readAsStringSync(), '8888\n$rootA');
    });

    test('活跃锁 + **另一个**数据根 ⇒ otherDataRoot（各写各的，不构成冲突）', () async {
      seedLock(8888, root: rootB);
      final lock = lockWith(alive: (_) => true);
      expect(
        await lock.acquire(currentPid: 1111, dataRootKey: rootA),
        SingleInstanceStatus.otherDataRoot,
        reason: '这一格决定要不要对用户开口，判错方向就是谎报',
      );
    });

    test('老格式锁（只有 PID 一行，没有根）⇒ undetectable：不猜也不提醒', () async {
      final seeded = seedLock(8888);
      final lock = lockWith(alive: (_) => true);
      expect(
        await lock.acquire(currentPid: 1111, dataRootKey: rootA),
        SingleInstanceStatus.undetectable,
      );
      expect(
        seeded.existsSync(),
        isTrue,
        reason: '判不出根不等于「锁是我的」——不许顺手删别人活着的锁',
      );
    });

    test('自己传空根 = 自愿放弃同根判定 ⇒ 只会 undetectable，不会谎报同根', () async {
      seedLock(8888, root: rootA);
      final lock = lockWith(alive: (_) => true);
      expect(
        await lock.acquire(currentPid: 1111, dataRootKey: ''),
        SingleInstanceStatus.undetectable,
      );
    });

    test('路径归一化：分隔符、尾部斜杠、Windows 大小写都不该判成两个根', () {
      expect(isSameDataRootPath(rootA, rootA), isTrue);
      expect(isSameDataRootPath('/data/rootA/', '/data/rootA'), isTrue);
      expect(isSameDataRootPath('/data/rootA', '\\data\\rootA'), isTrue);
      expect(
        isSameDataRootPath(r'C:\Users\X\绘图笔记数据', r'c:\users\x\绘图笔记数据'),
        Platform.isWindows,
        reason: '只有 Windows 的路径才大小写不敏感；POSIX 上这两个就是两个目录',
      );
      expect(isSameDataRootPath(rootA, rootB), isFalse);
      expect(isSameDataRootPath('', rootA), isFalse);
      expect(isSameDataRootPath(rootA, ''), isFalse);
    });
  });

  test('探测失败 ≠ 有另一个实例：报 undetectable，保守不清锁', () async {
    // 旧实现把「判不了」折进 alive=true，于是对用户谎报「有另一个实例在跑」。
    final seeded = seedLock(7777, root: rootA);
    final lock = SingleInstanceLock(
      lockFile: lockIn(tmp),
      isProcessAlive: (_) async => null,
    );
    expect(
      await lock.acquire(currentPid: 1111, dataRootKey: rootA),
      SingleInstanceStatus.undetectable,
    );
    expect(seeded.existsSync(), isTrue, reason: '判不了就不删别人可能正在用的锁');
    expect(seeded.readAsStringSync(), '7777\n$rootA');
  });

  test('锁内容为空或垃圾（别人刚 create 还没写 PID）：undetectable，不删、不谎报', () async {
    final emptyFile = lockIn(tmp)..writeAsStringSync('');
    final emptyLock = lockWith(alive: (_) => true);
    expect(
      await emptyLock.acquire(currentPid: 1111, dataRootKey: rootA),
      SingleInstanceStatus.undetectable,
    );
    expect(emptyFile.existsSync(), isTrue);

    lockIn(tmp).writeAsStringSync('not-a-pid\n$rootA');
    final junkLock = lockWith(alive: (_) => true);
    expect(
      await junkLock.acquire(currentPid: 1111, dataRootKey: rootA),
      SingleInstanceStatus.undetectable,
    );
    expect(lockIn(tmp).readAsStringSync(), 'not-a-pid\n$rootA');
  });

  test('锁目录都不存在（IO 异常）：不抛、undetectable——**这就是「绝不阻断启动」**', () async {
    final missingDir = Directory('${tmp.path}${Platform.pathSeparator}nope');
    final lock = SingleInstanceLock(
      lockFile: File('${missingDir.path}${Platform.pathSeparator}app.lock'),
      isProcessAlive: (_) async => false,
    );
    expect(
      await lock.acquire(currentPid: 1111, dataRootKey: rootA),
      SingleInstanceStatus.undetectable,
    );
    expect(lock.holdsLock, isFalse);
  });

  test('release 之后同一实例可重新拿锁（锁文件确实被交回）', () async {
    final lock = lockWith(alive: (_) => false);
    expect(
      await lock.acquire(currentPid: 2222, dataRootKey: rootA),
      SingleInstanceStatus.acquired,
    );
    await lock.release();
    expect(lock.holdsLock, isFalse);
    expect(lockIn(tmp).existsSync(), isFalse);
    expect(
      await lock.acquire(currentPid: 3333, dataRootKey: rootA),
      SingleInstanceStatus.acquired,
    );
  });

  test('四态各自可达：任何一态不可达就说明有一句话是编的', () async {
    final observed = <SingleInstanceStatus>{};

    final fresh = lockWith(alive: (_) => false);
    observed.add(await fresh.acquire(currentPid: 1, dataRootKey: rootA));

    seedLock(8888, root: rootA);
    final busy = lockWith(alive: (_) => true);
    observed.add(await busy.acquire(currentPid: 2, dataRootKey: rootA));

    seedLock(8888, root: rootB);
    final other = lockWith(alive: (_) => true);
    observed.add(await other.acquire(currentPid: 3, dataRootKey: rootA));

    final blind = SingleInstanceLock(
      lockFile: File(
        '${tmp.path}${Platform.pathSeparator}missing${Platform.pathSeparator}app.lock',
      ),
      isProcessAlive: (_) async => false,
    );
    observed.add(await blind.acquire(currentPid: 4, dataRootKey: rootA));

    expect(observed, SingleInstanceStatus.values.toSet());
  });

  group('启动事实的写入面（instanceStatusAtLaunch）', () {
    /// 任何形式的「写它」：`= `、`??=`；`==` 与 `??` 读法不算。
    final write = RegExp(r'\binstanceStatusAtLaunch\s*(\?\?)?=[^=]');

    test('lib/ 里只有一个赋值点，而且就在 main.dart', () {
      final writes = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          // 注释里提到这个名字不算写它（trap 56 那一族）。
          if (line.trimLeft().startsWith('//')) continue;
          if (write.hasMatch(line)) {
            writes.add('${entity.path.replaceAll(r'\', '/')}:${i + 1}');
          }
        }
      }
      expect(
        writes,
        hasLength(1),
        reason: '这条「启动后不再变」的事实若被 UI 或存储层随手写，就成了第二个真相：$writes',
      );
      expect(
        writes.single,
        startsWith('lib/main.dart:'),
        reason: '唯一合法的写入点是启动序列里取锁之后：$writes',
      );
    });

    test('判据自证：读它、比它、注释里写它都不算赋值；`??=` 算', () {
      String? firstWrite(String source) {
        for (final line in source.split('\n')) {
          if (line.trimLeft().startsWith('//')) continue;
          if (write.hasMatch(line)) return line.trim();
        }
        return null;
      }

      expect(firstWrite('  instanceStatusAtLaunch = status;'), isNotNull);
      expect(
        firstWrite('  instanceStatusAtLaunch ??= status;'),
        isNotNull,
        reason: '`??=` 也是写；漏了它，「只许 main.dart 写一次」就能被随手绕过',
      );
      expect(firstWrite('  if (instanceStatusAtLaunch == status) {}'), isNull);
      expect(firstWrite('  final s = instanceStatusAtLaunch;'), isNull);
      expect(firstWrite('  // instanceStatusAtLaunch = status;'), isNull);
    });
  });
}
