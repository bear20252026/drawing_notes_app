// 由 Claude 团队生成 | Drawing Notes App

/// R51：「同数据根的第二个实例」要说给用户看，但**永远不阻断启动**。
///
/// 两条相反方向的断言一起钉（本仓做这类改动必守的口径，见 single_instance 文件头）：
///  ① 只有 `sameDataRootRunning` 这一格出声——其余三格（含 null）出声就是谎报；
///  ② 启动序列里取锁之后**不许有任何 return**——旧写法「已有实例就退出」正是
///     用户投诉「应用打不开」的根因，这条一断就要被 CI 拦住而不是等人肉想起来。
library;

import 'dart:io';

import 'package:flutter/material.dart' as m;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/app/app_shell.dart' show showInstanceNotice;
import 'package:drawing_notes_app/core/utils/single_instance.dart';
import 'package:drawing_notes_app/l10n/app_localizations.dart';

void main() {
  tearDown(() => instanceStatusAtLaunch = null);

  /// 造一个有 `ScaffoldMessenger` 宿主的壳，按 [status] 调一次判据。
  ///
  /// 走 post-frame 而不是在 `Builder` 里直接调：`showSnackBar` 会触发 messenger 的
  /// setState，在 build 期间调用是框架禁止的——生产里 AppShell 也是同一个时机，
  /// 这里必须照抄，否则测的是另一条路径。
  Future<void> pumpWith(WidgetTester tester, SingleInstanceStatus? status) async {
    await tester.pumpWidget(
      m.MaterialApp(
        locale: const m.Locale('en'),
        localizationsDelegates: [
          // 不挂 AppLocalizations.delegate 的话 `l10n` 是 null，用例就会测到**兜底文案**
          // 而不是真文案——那条断言（措辞必须留「可能」）会因此测错东西。
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: const [m.Locale('en'), m.Locale('zh')],
        home: m.Scaffold(
          body: m.Builder(
            builder: (context) {
              m.WidgetsBinding.instance.addPostFrameCallback(
                (_) => showInstanceNotice(context, status),
              );
              return const m.Text('body');
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('出声面：四格 + null', () {
    testWidgets('sameDataRootRunning ⇒ 提示出现，措辞带「可能」（PID 复用是固有误差）', (tester) async {
      await pumpWith(tester, SingleInstanceStatus.sameDataRootRunning);
      final snack = tester.widget<m.SnackBar>(find.byType(m.SnackBar));
      final text = ((snack.content as m.Text).data) ?? '';
      expect(text, isNotEmpty);
      expect(text.toLowerCase(), contains('may'));
      expect(
        snack.duration,
        const Duration(seconds: 8),
        reason: '这条要够时间读完，但它是提示不是闸门——不许做成需要用户确认才继续',
      );
    });

    testWidgets('其余三格与 null 都不出声', (tester) async {
      for (final status in <SingleInstanceStatus?>[
        SingleInstanceStatus.acquired,
        SingleInstanceStatus.otherDataRoot,
        SingleInstanceStatus.undetectable,
        null,
      ]) {
        await pumpWith(tester, status);
        expect(
          find.byType(m.SnackBar),
          findsNothing,
          reason: '$status 出声就是把「我不知道」或「各写各的」说成「有人在动你这份数据」',
        );
      }
    });
  });

  group('接线与「不阻断」判据', () {
    test('AppShell 真的在 post-frame 里接了这条提示', () {
      final lines = codeLines('lib/app/app_shell.dart');
      expect(
        lines.any((l) => l.contains('showInstanceNotice(context, instanceStatusAtLaunch)')),
        isTrue,
        reason: '拆成公开函数之后如果没人调它，上面那些用例照样全绿（trap 58）',
      );
      expect(
        lines.any((l) => l.contains('addPostFrameCallback')),
        isTrue,
        reason: 'initState 里直接 show 找不到宿主 ScaffoldMessenger',
      );
    });

    test('main.dart 取锁之后没有任何 return——「绝不阻断启动」是判据不是承诺', () {
      final lines = codeLines('lib/main.dart');
      final at = lines.indexWhere(
        (l) => l.contains('await _acquireSingleInstance()'),
      );
      expect(at, greaterThanOrEqualTo(0), reason: '取锁调用点不见了（改名/挪走 ⇒ 这条判据要看住的东西就没了）');
      // 取锁之后到 runApp 之间就是这个判据的射程：这一段里出现 return 即阻断。
      final until = lines.indexWhere((l) => l.contains('runApp('), at);
      expect(until, greaterThan(at), reason: '找不到 runApp，射程判不出来');
      final blocking = [
        for (var i = at; i <= until; i++)
          if (_blockingReturn.hasMatch(lines[i])) lines[i],
      ];
      expect(
        blocking,
        isEmpty,
        reason: '检测到第二个实例就不启动 ⇒ 这正是「应用打不开」那条历史投诉的形状',
      );
    });

    test('判据自证：把「不阻断」改成阻断，上面那条会红', () {
      String? blockingLine(List<String> lines) {
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains('await _acquireSingleInstance()')) {
            for (var j = i; j < lines.length; j++) {
              if (_blockingReturn.hasMatch(lines[j])) return lines[j];
              if (lines[j].contains('runApp(')) break;
            }
          }
        }
        return null;
      }

      expect(
        blockingLine(const <String>[
          '  final s = await _acquireSingleInstance();',
          '  if (s != SingleInstanceStatus.acquired) return;',
          '  runApp(const ProviderScope(child: DrawingNotesApp()));',
        ]),
        isNotNull,
        reason: '一行式阻断抓不到 ⇒ 判据是空的（第一版就漏在这儿）',
      );
      expect(
        blockingLine(const <String>[
          '  final s = await _acquireSingleInstance();',
          '  if (s != SingleInstanceStatus.acquired) {',
          '    return;',
          '  }',
          '  runApp(const ProviderScope(child: DrawingNotesApp()));',
        ]),
        isNotNull,
        reason: '独立成行的 return（旧那条注释撒谎的原形状）也要抓到',
      );
      expect(
        blockingLine(const <String>[
          '  final s = await _acquireSingleInstance();',
          '  if (s != SingleInstanceStatus.acquired) { log(s); }',
          '  runApp(const ProviderScope(child: DrawingNotesApp()));',
        ]),
        isNull,
      );
    });
  });
}

/// 「这一句会让第二个实例不再启动」的形状：任何位置的 `return`（含 `if (x) return;` 这种
/// 一行式）。第一版写成「行首 return」，只认独立成行的那种 ⇒ 一行式阻断直接漏过去，
/// 是 `判据自证` 那一格把它抓出来的（所以自证里两种形状都要有）。
final RegExp _blockingReturn = RegExp(r'\breturn\b');

/// 读源码文件并丢掉注释行（判据只看语句，注释里提到同名东西不算——trap 56）。
List<String> codeLines(String path) => File(path)
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .toList();
