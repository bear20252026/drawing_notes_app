// ============================================================================
// save_location_exemption_test.dart —— 原生「另存为」对话框的「切后台即锁」豁免
// ============================================================================
//
// 上一批留下的两处未完成接入，本批全部闭合：
//  ① openFile（图片选择器）站点 editor_page_editing.dart —— 本文件是
//     editor_page.dart 的 part，Dart 禁止 part 携带 import，故 LockExemption 在
//     **库本体**引入后于 part 内可见；该站点的接入状态由
//     reset_disk_picker_exemption_test.dart 的 openFile 门禁（债表已清空）盯住。
//  ② getSaveLocation（原生存盘对话框）全仓 14 处直调：drawing 侧 11 处收进
//     **单一封装** `EditorExporter._pickSaveLocation`（单点根治，同
//     ResetDiskFile.pickDirectory 的路子），另 3 处就地圈住——设置页「导出诊断
//     信息」、设置页「备份全部数据」、笔记本页「整本导出 PDF」。
//
// 锁死四件事：
//  ① 对话框在开那一段 [LockExemption.isActive] 必须为真——否则 AppLockGate 处理
//     inactive/hidden 会在选位置途中假锁开屏，hidden 侧还清掉 KEK/会话口令；
//  ② 正常返回 / 取消（平台回 null）/ 空路径 / 通道抛 PlatformException 四路
//     豁免**一定**释放（remaining==0）——漏 end 等于挂一张永久免死金牌；
//  ③ 窗口只圈那一次对话框调用：按位置渲染/写盘一律在窗口外，需要密钥的操作
//     照常受锁（导出器写完文件后 isActive 仍为假即为其证）；
//  ④ 静态门禁：全仓 `getSaveLocation(` 直调恰为 4 处且全部被圈住；
//     EditorExporter 内恰 1 处（封装本体）且 11 个导出点位全部经由该封装。
//
// 取径：①②③用 plain test + mock 方法通道（与 editor_exporter_tiled_test 一致，
// 真实落盘到临时目录）；④ 的 UI 点位用 testWidgets 只走**取消**路径（FakeAsync
// 区不推进真实文件 IO，故不让它落盘）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/canvas_model/document.dart';
import 'package:drawing_notes_app/core/security/app_lock_service.dart';
import 'package:drawing_notes_app/core/security/session_guard.dart'
    show LockExemption;
import 'package:drawing_notes_app/features/drawing/application/drawing_controller.dart';
import 'package:drawing_notes_app/features/drawing/application/editor_exporter.dart';
import 'package:drawing_notes_app/features/notes/presentation/settings_page.dart';

import '../../helpers/temp_dir_cleanup.dart';

const MethodChannel _fileSelectorChannel = MethodChannel(
  'plugins.flutter.io/file_selector',
);

/// 原生存盘对话框替身：在「对话框在开」那一刻采样豁免态，再按脚本回话。
///
/// 抛错路径走 [PlatformException]——mock 通道把它编成 error envelope，调用侧
/// `invokeMethod` 原样重抛（与真机对话框失败同形，不是测试自造的异常形状）。
class _FakeSaveDialog {
  /// 返回给 getSavePath 的路径（null = 用户取消，'' = 平台回了空串）。
  String? reply;

  /// 非 null 时对话框以该异常收场。
  PlatformException? error;

  /// 对话框在开期间读到的 [LockExemption.isActive]（null = 从未被调用）。
  bool? activeWhileDialogOpen;

  /// 原生调用次数。
  int calls = 0;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_fileSelectorChannel, (call) async {
          if (call.method != 'getSavePath') return null;
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

/// 该调用行是否被豁免窗口圈住：向上 6 行内出现 `LockExemption.run(` 或
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
  late _FakeSaveDialog dialog;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('save_location_exemption');
    // 豁免窗口是进程级静态——前后复位，防用例串味（与门测试同纪律）。
    LockExemption.resetForTest();
    dialog = _FakeSaveDialog();
  });

  tearDown(() {
    dialog.uninstall();
    LockExemption.resetForTest();
    deleteTempDirWithRetry(tmp);
  });

  void useDialog(_FakeSaveDialog d) {
    d.install();
    addTearDown(d.uninstall);
  }

  /// 生产等价的最小导出对象（独立画布，无分页笔记页）。
  EditorExporter jsonExporter(List<String> snacks) {
    final document = DrawingDocument(
      id: 'save_exempt',
      title: '存盘豁免',
      width: 400,
      height: 300,
    );
    final controller = DrawingController(document);
    addTearDown(controller.dispose);
    return EditorExporter(
      controller: controller,
      pageProvider: () => null,
      showSnack: snacks.add,
    );
  }

  List<File> writtenFiles() =>
      tmp.listSync(recursive: true).whereType<File>().toList();

  group('EditorExporter 存盘封装（11 个点位的单点根治行为）', () {
    test('对话框在开时豁免生效；返回后释放，写盘在窗口外', () async {
      dialog.reply = '${tmp.path}${Platform.pathSeparator}out.json';
      useDialog(dialog);
      expect(LockExemption.isActive, isFalse, reason: '进入前不在窗口内');

      await jsonExporter(<String>[]).exportJson();

      expect(
        dialog.activeWhileDialogOpen,
        isTrue,
        reason: '原生存盘对话框期间必须处于豁免窗口（否则选位置途中假锁开屏）',
      );
      expect(LockExemption.isActive, isFalse, reason: '对话框一返回就须出窗口，写盘/弹框不得圈进来');
      expect(writtenFiles(), hasLength(1), reason: '位置在窗口外被真实写盘');
      expect(LockExemption.remaining, Duration.zero);
      expect(dialog.calls, 1);
    });

    test('取消选择（平台回 null）：不写盘且豁免释放', () async {
      dialog.reply = null;
      useDialog(dialog);

      final snacks = <String>[];
      await jsonExporter(snacks).exportJson();

      expect(dialog.activeWhileDialogOpen, isTrue); // 取消前对话框同在窗口内
      expect(writtenFiles(), isEmpty, reason: '取消即中止，不产生文件');
      expect(snacks, isEmpty, reason: '用户主动取消不发失败提示');
      expect(LockExemption.isActive, isFalse);
      expect(LockExemption.remaining, Duration.zero);
    });

    test('平台回空串：写盘失败被兜住，豁免仍释放', () async {
      dialog.reply = '';
      useDialog(dialog);

      final snacks = <String>[];
      await jsonExporter(snacks).exportJson();

      expect(writtenFiles(), isEmpty);
      expect(snacks, hasLength(1), reason: '空路径 ⇒ File(\'\') 抛错走失败提示');
      expect(LockExemption.isActive, isFalse, reason: '异常路径不得把豁免留在台上');
      expect(LockExemption.remaining, Duration.zero);
    });

    test('原生通道抛异常：豁免一定释放（漏 end = 永久免死金牌）', () async {
      dialog.error = PlatformException(
        code: 'dialog_failed',
        message: 'save dialog crashed',
      );
      useDialog(dialog);

      final snacks = <String>[];
      await jsonExporter(snacks).exportJson();

      expect(snacks, hasLength(1), reason: '异常由导出器 catch 兜住并提示');
      expect(
        LockExemption.isActive,
        isFalse,
        reason: 'run 的 finally 必须配对复位，本类代码最典型的缺陷即在此',
      );
      expect(LockExemption.remaining, Duration.zero, reason: '不留 TTL 残值');
    });

    test('异常后再导出：计数未错位，窗口照常开关', () async {
      dialog.error = PlatformException(code: 'first_failed');
      useDialog(dialog);
      await jsonExporter(<String>[]).exportJson();
      expect(LockExemption.isActive, isFalse);

      // 第二次改回正常返回——若第一次泄漏了计数，这次结束后仍会挂着豁免。
      dialog.error = null;
      dialog.reply = '${tmp.path}${Platform.pathSeparator}again.json';
      await jsonExporter(<String>[]).exportJson();
      expect(LockExemption.isActive, isFalse);
      expect(dialog.calls, 2);
      expect(writtenFiles(), hasLength(1));
    });
  });

  group('内联点位行为（设置页「导出诊断信息」真实 UI 触发）', () {
    testWidgets('取消存盘对话框：豁免只按住对话框那一段，取消即释放', (tester) async {
      SharedPreferences.setMockInitialValues({});
      // 只走取消路径：FakeAsync 区不推进真实文件 IO，落盘留给上面的 plain test。
      dialog.reply = null;
      dialog.install();
      addTearDown(dialog.uninstall);

      await tester.pumpWidget(
        MaterialApp(home: SettingsPage(appLockService: AppLockService())),
      );
      final tile = find.ancestor(
        of: find.text('导出诊断信息'),
        matching: find.byType(ListTile),
      );
      expect(tile, findsOneWidget);
      await tester.ensureVisible(tile);
      await tester.pump();

      expect(LockExemption.isActive, isFalse, reason: '点开前不在窗口内');
      await tester.tap(tile, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        dialog.activeWhileDialogOpen,
        isTrue,
        reason: '设置页存盘对话框那一次调用必须被圈进豁免窗口',
      );
      expect(LockExemption.isActive, isFalse, reason: '取消即出窗口——报告写盘不得吃豁免');
      expect(LockExemption.remaining, Duration.zero);
      expect(dialog.calls, 1);
    });
  });

  group('接入点静态门禁（防封装被绕过、防点位重新长出）', () {
    test('全仓 getSaveLocation 直调恰为 4 处，且每一处都在豁免窗口内', () {
      final sites = <String>[];
      final unwrapped = <String>[];
      for (final f in _libDartFiles()) {
        final rel = _rel(f.path);
        final lines = f.readAsLinesSync();
        for (final i in _pickerLines(lines, RegExp(r'\bgetSaveLocation\('))) {
          sites.add('$rel:${i + 1}');
          if (!_siteExempted(lines, i)) unwrapped.add('$rel:${i + 1}');
        }
      }
      expect(
        sites,
        hasLength(4),
        reason:
            '实测点位：EditorExporter 封装 1 处（覆盖 11 个导出路径）+ '
            '设置页 2 处 + 笔记本整本导出 1 处；新增点位须就地收口',
      );
      expect(unwrapped, isEmpty, reason: '任何一处裸调都会在选位置途中假锁开屏（并清 KEK）');
    });

    test('EditorExporter 单点根治：内层恰 1 处直调，11 个路径全部经由封装', () {
      const path = 'lib/features/drawing/application/editor_exporter.dart';
      final lines = File(path).readAsStringSync().split('\n');
      expect(
        _pickerLines(lines, RegExp(r'\bgetSaveLocation\(')),
        hasLength(1),
        reason: '存盘对话框入口在本类内只允许 _pickSaveLocation 一处',
      );
      // 封装本体自带豁免。
      expect(
        _siteExempted(
          lines,
          _pickerLines(lines, RegExp(r'\bgetSaveLocation\(')).single,
        ),
        isTrue,
      );
      // 1 def + 11 调用 = 12 行命中 `_pickSaveLocation(`。
      final via = _pickerLines(lines, RegExp(r'\b_pickSaveLocation\('));
      expect(
        via,
        hasLength(12),
        reason:
            '封装定义 1 处 + 11 个导出点位（PNG/PDF/整本/分页/纸面/SVG/RTF/'
            'MD/PPTX/JSON）各 1 处；少于 12 即有点位绕过封装裸调',
      );
      expect(
        lines.where((l) => l.contains('LockExemption.run(')),
        hasLength(1),
        reason: '豁免只写在封装本体一处，调用点不得各自再包一层',
      );
    });

    test('其余 3 处内联站点所在库文件须能看到 LockExemption', () {
      // part 文件不能带 import ⇒ 豁免可用性取决于库本体的 import 是否还在。
      const hosts = [
        'lib/features/notes/presentation/settings_page.dart',
        'lib/features/notes/presentation/notebook_view_page.dart',
        'lib/features/drawing/presentation/editor_page.dart',
      ];
      for (final path in hosts) {
        final src = File(path).readAsStringSync();
        expect(
          src.contains("core/security/session_guard.dart'"),
          isTrue,
          reason: '$path 缺 session_guard import ⇒ part/本文件的豁免接入失效',
        );
      }
      // notebook_view_page_manage 是 part，自身不得携带 import（Dart 禁止）。
      final part = File(
        'lib/features/notes/presentation/notebook_view_page_manage.dart',
      ).readAsStringSync();
      expect(
        RegExp(r'^import ', multiLine: true).hasMatch(part),
        isFalse,
        reason: 'part 文件里出现 import 会直接编译失败（non_part_of_directive…）',
      );
    });

    test('门禁突变自证：_siteExempted 不是恒真的摆设', () {
      const bare = [
        '      final location = await getSaveLocation(',
        "        suggestedName: 'a.pdf',",
        '      );',
      ];
      const wrapped = [
        '      final location = await LockExemption.run(',
        '        () => getSaveLocation(suggestedName: \'a.pdf\'),',
        '      );',
      ];
      const guardWrapped = [
        '      final location = await _sessionGuard.runWithExemption(',
        '        () => getSaveLocation(suggestedName: \'a.pdf\'),',
        '      );',
      ];
      const commentOnly = [
        '      // 将来包进 LockExemption.run(',
        '      final location = await getSaveLocation(suggestedName: \'a.pdf\'),',
      ];
      expect(_siteExempted(bare, 0), isFalse, reason: '裸调用必须判为未接入');
      expect(_siteExempted(wrapped, 1), isTrue);
      expect(_siteExempted(guardWrapped, 1), isTrue);
      expect(_siteExempted(commentOnly, 1), isFalse, reason: '注释不算接入');
    });
  });
}
