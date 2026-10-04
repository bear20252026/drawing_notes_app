// ============================================================================
// reset_disk_picker_exemption_test.dart —— 原生选择器「切后台即锁」豁免接入点
// ============================================================================
//
// 本批根治点：`ResetDiskFile.pickDirectory` 是全仓**唯一**一处原生目录选择器
// 调用，LockExemption 窗口收在它内部，于是全部下游选盘路径（文档密码页两处、
// 重置流公共步骤、设置页绑盘、笔记本绑盘、锁门「忘记密码」）一并覆盖。锁死：
//  ① 对话框在开那一段 isActive 必须为真——否则 AppLockGate 处理失焦信号会在
//     选盘途中假锁开屏，hidden 侧还清掉 KEK/会话口令；
//  ② 选择器返回 / 取消（平台回 null）/ 抛异常后豁免**一定**释放——漏 end 等于
//     给进程挂一张永久免死金牌，门从此再不因切后台加锁（本类代码最典型缺陷）；
//  ③ 豁免只圈对话框：选完之后的读盘/写盘在窗口外（需要密钥的操作照常受锁）；
//  ④ 静态门禁：目录选择器入口不得长出第二处、下游不得绕过 pickDirectory 直调
//     原生通道（那会静默丢掉 ①），openFile 站点的接入状态由债表盯住。
//
// 取径：plain test + mock 方法通道（与 editor_exporter_tiled_test 一致）。
// 不用 testWidgets：这里不需要 widget 树，而 FakeAsync 区不推进真实文件 IO。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/security/session_guard.dart'
    show LockExemption;
import 'package:drawing_notes_app/core/storage/password_reset_disk.dart';

import '../../helpers/temp_dir_cleanup.dart';

const MethodChannel _fileSelectorChannel = MethodChannel(
  'plugins.flutter.io/file_selector',
);

/// 原生目录选择器替身：在「对话框在开」那一刻采样豁免态，再按脚本回话。
///
/// 抛错路径走 [PlatformException]——mock 通道把它编成 error envelope，调用侧
/// `invokeMethod` 原样重抛（与真机对话框失败同形，不是测试自造的异常形状）。
class _FakeDirectoryPicker {
  /// 返回给 getDirectoryPath 的目录（null = 用户取消）。
  String? reply;

  /// 非 null 时选择器以该异常收场。
  PlatformException? error;

  /// 对话框在开期间读到的 LockExemption.isActive（null = 从未被调用）。
  bool? activeWhileDialogOpen;

  /// 原生调用次数。
  int calls = 0;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_fileSelectorChannel, (call) async {
          if (call.method != 'getDirectoryPath') return null;
          calls++;
          activeWhileDialogOpen = LockExemption.isActive;
          if (error != null) throw error!;
          return reply;
        });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_fileSelectorChannel, null);
  }
}

/// lib/ 下全部 .dart 文件（flutter test 以包根为工作目录）。
List<File> _libDartFiles() =>
    Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

/// 规范化成 `lib/...` 相对路径（Windows 反斜杠归一）。
String _rel(String path) => path.replaceAll('\\', '/');

/// 命中「原生选择器调用」的行号（跳过注释行，注释里提函数名不算调用）。
List<int> _pickerLines(List<String> lines, RegExp pattern) {
  final hits = <int>[];
  for (var i = 0; i < lines.length; i++) {
    final t = lines[i].trimLeft();
    if (t.startsWith('//') || t.startsWith('/*') || t.startsWith('*')) continue;
    if (pattern.hasMatch(lines[i])) hits.add(i);
  }
  return hits;
}

/// 该选择器行是否被豁免窗口圈住：向上 6 行内出现 `LockExemption.run(` 或
/// `runWithExemption(` 即认为闭包把这一行包了进去。
bool _siteExempted(List<String> lines, int index) {
  final from = index - 6 < 0 ? 0 : index - 6;
  for (var i = from; i <= index; i++) {
    final t = lines[i].trimLeft();
    if (t.startsWith('//')) continue; // 注释里的函数名不算接入
    if (t.contains('LockExemption.run(') || t.contains('runWithExemption(')) {
      return true;
    }
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late _FakeDirectoryPicker picker;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('reset_disk_picker');
    // 豁免窗口是进程级静态——前后复位，防用例串味（与门测试同纪律）。
    LockExemption.resetForTest();
    picker = _FakeDirectoryPicker();
  });

  tearDown(() {
    picker.uninstall();
    LockExemption.resetForTest();
    deleteTempDirWithRetry(tmp);
  });

  /// 装上替身，用例结束自动拆掉。
  void usePicker(_FakeDirectoryPicker p) {
    p.install();
    addTearDown(p.uninstall);
  }

  group('pickDirectory 豁免窗口（根治点行为）', () {
    test('对话框在开时豁免生效，选盘返回后立刻释放', () async {
      picker.reply = tmp.path;
      usePicker(picker);
      expect(LockExemption.isActive, isFalse, reason: '进入前不在窗口内');

      final picked = await ResetDiskFile.pickDirectory();

      expect(picked, tmp.path);
      expect(
        picker.activeWhileDialogOpen,
        isTrue,
        reason: '原生对话框期间必须处于豁免窗口（否则选盘途中假锁开屏）',
      );
      expect(
        LockExemption.isActive,
        isFalse,
        reason: '选择器一返回就须出窗口，不得把后续业务流程圈进来',
      );
      expect(picker.calls, 1);
    });

    test('取消选择（平台回 null）同样释放豁免', () async {
      picker.reply = null;
      usePicker(picker);

      expect(await ResetDiskFile.pickDirectory(), isNull);
      expect(picker.activeWhileDialogOpen, isTrue); // 取消前对话框同在窗口内
      expect(LockExemption.isActive, isFalse);
    });

    test('空串目录归一为 null（既有语义不回退）且释放豁免', () async {
      picker.reply = '';
      usePicker(picker);

      expect(await ResetDiskFile.pickDirectory(), isNull);
      expect(LockExemption.isActive, isFalse);
    });

    test('原生通道抛异常：异常透传给调用方，且豁免一定释放', () async {
      picker.error = PlatformException(code: 'dialog_failed', message: 'boom');
      usePicker(picker);

      await expectLater(
        ResetDiskFile.pickDirectory(),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'dialog_failed',
          ),
        ),
      );
      expect(
        LockExemption.isActive,
        isFalse,
        reason: '漏 end ⇒ 永久免死金牌，这是本类代码最典型的缺陷',
      );
      expect(LockExemption.remaining, Duration.zero, reason: '异常路径不得留下 TTL 残值');
    });

    test('异常后再次选盘：计数未错位，窗口照常开关', () async {
      picker.error = PlatformException(code: 'first_failed');
      usePicker(picker);
      await expectLater(
        ResetDiskFile.pickDirectory(),
        throwsA(isA<PlatformException>()),
      );
      expect(LockExemption.isActive, isFalse);

      // 第二次改回正常返回——若第一次泄漏了计数，这次结束后仍会挂着豁免。
      picker.error = null;
      picker.reply = tmp.path;
      expect(await ResetDiskFile.pickDirectory(), tmp.path);
      expect(LockExemption.isActive, isFalse);
      expect(picker.calls, 2);
    });

    test('读盘/写钥匙不在豁免窗口内（密钥操作照常受锁）', () async {
      final key = await ResetDiskFile.writeTo(tmp.path);
      expect(LockExemption.isActive, isFalse, reason: 'writeTo 本身不开窗口');

      picker.reply = tmp.path;
      usePicker(picker);
      final picked = await ResetDiskFile.pickDirectory();
      expect(LockExemption.isActive, isFalse, reason: '出窗口之后才读盘');
      expect(await ResetDiskFile.readFrom(picked!), key);
      expect(LockExemption.isActive, isFalse);
    });

    test('外层已豁免时嵌套（门/设置页既有包法）计数成对复位', () async {
      LockExemption.begin(); // 模拟调用方自己的窗口
      picker.reply = tmp.path;
      usePicker(picker);

      await ResetDiskFile.pickDirectory();
      expect(LockExemption.isActive, isTrue, reason: '内层 end 不关掉外层窗口');
      LockExemption.end();
      expect(LockExemption.isActive, isFalse);
    });
  });

  group('接入点静态门禁（防根治点被绕过）', () {
    test('全仓原生目录选择器只有一处，且自带豁免窗口', () {
      final sites = <String>[];
      for (final f in _libDartFiles()) {
        final lines = f.readAsLinesSync();
        for (final i in _pickerLines(
          lines,
          RegExp(r'\bgetDirectoryPaths?\('),
        )) {
          sites.add('${_rel(f.path)}:${i + 1}');
        }
      }
      expect(
        sites,
        hasLength(1),
        reason: '目录选择器必须只有 ResetDiskFile 一个入口；新增了就要在那里收口',
      );
      expect(
        sites.single,
        startsWith('lib/core/storage/password_reset_disk.dart:'),
      );
      final src = File('lib/core/storage/password_reset_disk.dart')
          .readAsStringSync();
      expect(src.contains('LockExemption.run('), isTrue, reason: '唯一入口须自带豁免');
    });

    test('下游选盘路径一律经由 pickDirectory（单点根治的覆盖证据）', () {
      // 本批点名要补的两处：文档密码页（事后绑盘 + 设密当场绑定）、重置流公共步骤。
      const downstream = [
        'lib/features/doc/presentation/doc_page_password.dart',
        'lib/features/security/presentation/password_reset_common.dart',
      ];
      for (final path in downstream) {
        final lines = File(path).readAsStringSync().split('\n');
        expect(
          _pickerLines(lines, RegExp(r'\bgetDirectoryPaths?\(')),
          isEmpty,
          reason: '$path 直调原生选择器会绕过豁免窗口',
        );
        final viaChokepoint = lines.where(
          (l) => l.contains('ResetDiskFile.pickDirectory('),
        );
        expect(
          viaChokepoint.length,
          greaterThan(0),
          reason: '$path 应经由带豁免的入口选盘',
        );
      }
    });

    test('openFile 站点接入状态：未接入的只允许债表里那一处', () {
      // 债表（记债而非遗忘）：editor_page_editing.dart 是 editor_page.dart 的
      // part，Dart 禁止 part 携带 import ⇒ LockExemption 在该库内不可见，须在
      // 库文件补一行 import 后收口（该文件选择器处有标记注释）。补齐后请把本
      // 表清空——门禁要求表与实态一致，不会让债静默滚存。
      const debt = <String>{
        'lib/features/drawing/presentation/editor_page_editing.dart',
      };
      final unwrapped = <String>{};
      var seen = 0;
      for (final f in _libDartFiles()) {
        final rel = _rel(f.path);
        final lines = f.readAsLinesSync();
        for (final i in _pickerLines(lines, RegExp(r'\bopenFile\('))) {
          if (lines[i].contains('PdfDocument.')) continue; // pdfx，非选择器
          seen++;
          if (!_siteExempted(lines, i)) unwrapped.add(rel);
        }
      }
      expect(seen, greaterThanOrEqualTo(4), reason: '扫描不得空转（vacuous 门禁）');
      expect(
        unwrapped,
        debt,
        reason: '出现新的未接入选择器 ⇒ 就地补 LockExemption.run；已补齐 ⇒ 从债表删',
      );
    });

    test('门禁突变自证：_siteExempted 不是恒真的摆设', () {
      const bare = [
        '    final f = await openFile(',
        '      acceptedTypeGroups: [typeGroup],',
        '    );',
      ];
      const wrapped = [
        '    final f = await LockExemption.run(',
        '      () => openFile(acceptedTypeGroups: [typeGroup]),',
        '    );',
      ];
      const guardWrapped = [
        '    final f = await _sessionGuard.runWithExemption(',
        '      () => openFile(acceptedTypeGroups: [typeGroup]),',
        '    );',
      ];
      const commentOnly = [
        '    // 将来包进 LockExemption.run(',
        '    final f = await openFile(acceptedTypeGroups: [typeGroup]),',
      ];
      expect(_siteExempted(bare, 0), isFalse, reason: '裸调用必须判为未接入');
      expect(_siteExempted(wrapped, 1), isTrue);
      expect(_siteExempted(guardWrapped, 1), isTrue);
      expect(_siteExempted(commentOnly, 1), isFalse, reason: '注释不算接入');
    });
  });
}
