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
///
/// 2026-10-15（EUI-03，用户点名抬基线）：7120 → 7127。动机不是「功能变多」，
/// 而是**把一条只写在三个入口的互斥判据补齐到十个入口**——连线模式不清出，
/// 工具条会一格不亮、元素点击会一直被当连线端点。逐条算：十个入口各 +1 行
/// `_viewModel.leaveLinkMode()`（+10），形状/手型/框选原先手写的
/// `setLinkMode(false)` + `setLinkSourceId(null)` 两行收敛成一行（−3），
/// 收口方法本体落在 `editor_viewmodel.dart`（不属本库，不计入）。
/// 抬完仍只比基线小 1 行——下一次增长要么先拆，要么再点名。
const int kBaselineTotalLines = 7127;

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

    // ── 下限也要钉（审计 TE-TST-04，2026-10-16）──
    // 这条棘轮原本**只有上限**：`total ≤ 基线`。让 `total` 变小到 0 的坏法有好几种
    // （`_countLines` 改成返回 0、主文件被读到空、part 清单解析出空集但恰好 isNotEmpty 挡住），
    // 每一种都让这条门禁**更容易绿**——棘轮类门禁的失效方向天生朝「数字变小」，
    // 所以它比一般门禁更需要一条下限。数字取实测（15 个 part / 7126 行）之下很宽的一档，
    // 只用于抓塌空，不参与「只许减不许增」的裁决。
    expect(
      parts.length,
      greaterThanOrEqualTo(10),
      reason: '只解析出 ${parts.length} 个 part（实测基线 15）⇒ part 声明正则与源码形态失配',
    );
    expect(
      total,
      greaterThanOrEqualTo(5000),
      reason:
          '整个 editor_page 库只数出 $total 行（实测基线 7126）⇒ 读盘或计数坏了。'
          '此时 `total ≤ $kBaselineTotalLines` 成立得毫无意义：那是没数到，不是没超。',
    );

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
