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
///
/// 2026-11-15（AGENTS.md §9 part 导航规范）：7127 → 7144（+17）。动机**不是
/// 功能增长**，而是纯注释的可读性投资：editor_page 有 15 个 part，此前主文件
/// 只有一串裸 `part` 声明，读者无从知道哪个职责落在哪个文件。本次在主文件补
/// 一份导航目录（17 行注释，逐个 part 标注职责），零逻辑变更、零行为变化。
/// 这是「结构裁决说明」档：拆分本身没变（part 数与边界不动），补的是索引。
/// 下一次**逻辑**增长仍须先拆或再点名——注释投资不构成长期放宽的先例。
///
/// 2026-11-16（K_note 媒体独立密钥生产接线，业主批准）：7144 → 7158（+14）。
/// 动机是**安全接线的必要逻辑**，逐条算：editor_page.dart 新增 notebookId
/// 字段 + 文档注释 + 构造参数（+7）；editor_page_editing.dart 笔记页图片入库
/// 前的笔记本上下文守卫（nbId 空判 + 提示 + 传参，+6）；editor_page_overlays.dart
/// 图片 provider 传 notebookId（+1）。这是跨域密钥隔离的穿线成本，不是展示件
/// 增长——无新 UI 组件。part 数与边界不动。下一次增长仍须先拆或再点名。
///
/// 2026-11-16（全面升级重构审查，mounted 守卫补齐）：7158 → 7161（+3）。
/// 动机是**异步安全修复**，非功能增长：editor_page.dart 退出裁决的第二个
/// 异步间隙（confirmLeaveWithUnsavedChanges 确认弹窗）后此前未复查 mounted
/// 即 setState——弹窗期间页面被销毁会抛异常。补 `if (!mounted) return;`（1 行）
/// + 2 行说明注释。零逻辑分支变更、零新 UI。part 数与边界不动。这是缺陷修复
/// 成本，不构成放宽先例——下一次增长仍须先拆或再点名。
///
/// 2026-11-17（R3 手势收敛 + R1 首域，审查路线图）：7161 → 7149（-12）。
/// R3：框选/套索两处三类同构命中循环收敛进 infrastructure 纯函数
/// MixedItemHitGeometry（input -20 行）；旋转手柄保存链通知移到 onPanEnd
/// （overlays +7 行含 onPanCancel 兜底与注释）；主文件 +1 行导入。
/// R1 首域：导出方法群 persistence→actions 逐字搬移（-169/+171，含 2 行
/// 域注释与接缝清理），行数中性。棘轮随净删行下调——只紧不松。
///
/// 2026-11-17（混排拖拽域统一入撤销专项）：7149 → 7235（+86）。
/// 动机是**整域撤销缺口修复**（移动/旋转/缩放/宽度柄直改字段不入撤销，
/// 拖完既撤不回又立刻落盘），非功能增长。逐文件明细：
/// - editor_page.dart +48：_beginMixedDrag/_commitMixedDrag/_cancelMixedDrag
///   三个事务便捷入口（含注释 48 行）——overlay 手势链路统一经此登记撤销，
///   独立画布指针链路走 session 事务不经这里（防双记）。
/// - editor_page_overlays.dart +10：形状/图片/图表移动补 onPanStart/
///   onPanCancel、旋转补 onPanStart、ResizeHandles 补 onDragStart/onDragEnd
///   传参（每处 1-3 行接线）。
/// - editor_page_text_overlays.dart +6：文字移动补 onPanStart/onPanCancel、
///   宽度柄 onPanStart 补 begin / onPanEnd 补 commit。
/// - editor_page_drag_ops.dart +15：图表移动循环补齐（死手势修复，与形状
///   同口径 clamp，含 3 行注释）。
/// - editor_page_input.dart +7：独立模式单图片 pointerUp 结算分支补齐
///   （与形状分支对称，含 3 行注释）。
/// 事务本体（MixedObjectDragRecorder ~130 行）落 editor_page_object_mutation.dart
/// （独立库，不计本棘轮）；深快照恢复身份写回逻辑落 document_commands.dart
/// （application 层）。零新 UI 组件、零新 part。这是缺陷修复成本，不构成
/// 放宽先例——下一次增长仍须先拆或再点名。
const int kBaselineTotalLines = 7235;

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
