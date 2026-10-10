// P3-3（审计 2026-10-05）：editor_page 库级行数棘轮。
//
// 为什么需要：editor_page.dart + 其 part 文件构成一个**逻辑库**，linecheck
// 的 500/1000 行双档对单文件生效，part 拆分后每个 part 都远低于阈值——
// 库级总量（当前按 part 口径实测 7120 行）对行数门禁**完全不可见**。本棘轮
// 把库级总量钉在命名基线上：只许减不许增；确需增长时，必须有意识地抬高
// [kBaselineTotalLines] 并在 commit message 写明动机（与 D-14 触控棘轮 310
// 同一哲学：诚实基线 + 反向锁）。
//
// part 集合从 editor_page.dart 的 `part` 声明自动解析——新增 part 自动纳入
// 分母，不存在「加 part 绕过棘轮」的口子。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 当前库级总量实测（2026-10-10，按 part 声明解析）。**只许改小**；改大必须
/// 随附拆分排期或结构裁决说明，并在 commit message 里单独交代。
/// 注意口径：`editor_page_*.dart` 通配比本基线多 273 行——那是
/// editor_page_object_mutation.dart（独立库，非 part），不计入本棘轮；
/// 它归 linecheck 单文件门禁管。
const int kBaselineTotalLines = 7120;

int _countLines(File f) => f.readAsLinesSync().length;

void main() {
  test('P3-3：editor_page 库（主文件+parts）总行数 ≤ 棘轮基线', () {
    final dir = Directory('lib/features/drawing/presentation');
    expect(dir.existsSync(), isTrue, reason: 'presentation 目录缺失——测试须在仓库根运行');

    final mainFile = File(
      '${dir.path}${Platform.pathSeparator}editor_page.dart',
    );
    expect(mainFile.existsSync(), isTrue, reason: 'editor_page.dart 不存在');

    var total = _countLines(mainFile);
    final parts = <String>[];
    final partDecl = RegExp(r"^part\s+'([^']+)';", multiLine: true);
    for (final m in partDecl.allMatches(mainFile.readAsStringSync())) {
      final partFile = File('${dir.path}${Platform.pathSeparator}${m.group(1)}');
      expect(partFile.existsSync(), isTrue,
          reason: 'part 声明了不存在的文件：${m.group(1)}');
      parts.add(m.group(1)!);
      total += _countLines(partFile);
    }
    expect(parts, isNotEmpty, reason: 'part 解析落空——正则与源码形态失配，先修本测试');

    expect(
      total,
      lessThanOrEqualTo(kBaselineTotalLines),
      reason:
          'editor_page 库总行数 $total 超过棘轮基线 $kBaselineTotalLines'
          '（parts: ${parts.length} 个）。part 拆分使 linecheck 单文件门禁对'
          '库级总量失明，本棘轮是唯一守门人；确需增长请抬高基线并在 commit '
          'message 写明动机（新增展示件优先落 components/dialogs 子目录，'
          '不进本库）。',
    );
  });
}
