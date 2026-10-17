import 'dart:io';

import 'package:drawing_notes_app/core/utils/single_instance.dart';
import 'package:flutter_test/flutter_test.dart';

/// ASM-02 单实例检测（`lib/core/utils/single_instance.dart`）。
///
/// 这批用例钉的是**两条相反方向**的断言（本仓做安全语义改动必守的口径）：
/// ① 检测要能说出事实（三种状态各自可达、互不冒充）；
/// ② 检测**永远不许阻止启动**（任何输入都不抛、不 hang、不返回「别起来」）。
/// 少了 ① 就是一句空话，少了 ② 会把「应用打不开」那条历史投诉重新请回来。
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('single_instance_test');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  File lockIn(Directory dir) =>
      File('${dir.path}${Platform.pathSeparator}app.lock');

  /// 预置一个锁文件，内容就是 [body]。
  File seedLock(String body) {
    final f = lockIn(tmp)..writeAsStringSync(body);
    return f;
  }

  test('干净启动：拿到锁，锁里写的是本进程 PID', () async {
    final lock = SingleInstanceLock(
      lockFile: lockIn(tmp),
      isProcessAlive: (_) async => false,
    );
    expect(await lock.acquire(currentPid: 4242), SingleInstanceStatus.acquired);
    expect(lock.holdsLock, isTrue);
    expect(lockIn(tmp).readAsStringSync(), '4242');
  });

  test('陈旧锁（记录的 PID 已不存活）：回收后照常拿锁', () async {
    seedLock('9999');
    final lock = SingleInstanceLock(
      lockFile: lockIn(tmp),
      isProcessAlive: (pid) async {
        expect(pid, 9999);
        return false;
      },
    );
    expect(await lock.acquire(currentPid: 1111), SingleInstanceStatus.acquired);
    expect(lockIn(tmp).readAsStringSync(), '1111');
  });

  test('活跃锁（PID 确认存活）：报 alreadyRunning，且**不许动别人的锁文件**', () async {
    final seeded = seedLock('8888');
    final lock = SingleInstanceLock(
      lockFile: lockIn(tmp),
      isProcessAlive: (_) async => true,
    );
    expect(
      await lock.acquire(currentPid: 1111),
      SingleInstanceStatus.alreadyRunning,
    );
    expect(lock.holdsLock, isFalse);
    expect(seeded.readAsStringSync(), '8888');
  });

  test('探测失败 ≠ 有另一个实例：报 undetectable，保守不清锁', () async {
    // 旧实现把「判不了」折进 alive=true，于是对用户谎报「有另一个实例在跑」。
    final seeded = seedLock('7777');
    final lock = SingleInstanceLock(
      lockFile: lockIn(tmp),
      isProcessAlive: (_) async => null,
    );
    expect(
      await lock.acquire(currentPid: 1111),
      SingleInstanceStatus.undetectable,
    );
    expect(seeded.existsSync(), isTrue, reason: '判不了就不删别人可能正在用的锁');
    expect(seeded.readAsStringSync(), '7777');
  });

  test('锁内容为空或垃圾（别人刚 create 还没写 PID）：undetectable，不删、不谎报', () async {
    final empty = seedLock('');
    final emptyLock = SingleInstanceLock(
      lockFile: lockIn(tmp),
      isProcessAlive: (_) async => true,
    );
    expect(
      await emptyLock.acquire(currentPid: 1111),
      SingleInstanceStatus.undetectable,
    );
    expect(empty.existsSync(), isTrue);

    seedLock('not-a-pid');
    final junkLock = SingleInstanceLock(
      lockFile: lockIn(tmp),
      isProcessAlive: (_) async => true,
    );
    expect(
      await junkLock.acquire(currentPid: 1111),
      SingleInstanceStatus.undetectable,
    );
    expect(lockIn(tmp).readAsStringSync(), 'not-a-pid');
  });

  test('锁目录都不存在（IO 异常）：不抛、undetectable——**这就是「绝不阻断启动」**', () async {
    final missingDir = Directory('${tmp.path}${Platform.pathSeparator}nope');
    final lock = SingleInstanceLock(
      lockFile: File('${missingDir.path}${Platform.pathSeparator}app.lock'),
      isProcessAlive: (_) async => false,
    );
    expect(
      await lock.acquire(currentPid: 1111),
      SingleInstanceStatus.undetectable,
    );
    expect(lock.holdsLock, isFalse);
  });

  test('release 之后同一实例可重新拿锁（锁文件确实被交回）', () async {
    final lock = SingleInstanceLock(
      lockFile: lockIn(tmp),
      isProcessAlive: (_) async => false,
    );
    expect(await lock.acquire(currentPid: 2222), SingleInstanceStatus.acquired);
    await lock.release();
    expect(lock.holdsLock, isFalse);
    expect(lockIn(tmp).existsSync(), isFalse);
    expect(await lock.acquire(currentPid: 3333), SingleInstanceStatus.acquired);
  });

  test('三态各自可达：任何一态不可达就说明有一句话是编的', () async {
    final observed = <SingleInstanceStatus>{};

    final fresh = SingleInstanceLock(
      lockFile: lockIn(tmp),
      isProcessAlive: (_) async => false,
    );
    observed.add(await fresh.acquire(currentPid: 1));

    seedLock('8888');
    final busy = SingleInstanceLock(
      lockFile: lockIn(tmp),
      isProcessAlive: (_) async => true,
    );
    observed.add(await busy.acquire(currentPid: 2));

    final blind = SingleInstanceLock(
      lockFile: File(
        '${tmp.path}${Platform.pathSeparator}missing${Platform.pathSeparator}app.lock',
      ),
      isProcessAlive: (_) async => false,
    );
    observed.add(await blind.acquire(currentPid: 3));

    expect(observed, SingleInstanceStatus.values.toSet());
  });
}
