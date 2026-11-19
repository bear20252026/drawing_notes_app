// R2（架构审查 2026-11-16 路线图）：破千 part 库的库级行数棘轮。
// H-4（第二轮审计 2026-11-17）扩到 12 库：原 7 库 + doc_editor 2747 /
// notebook_view_page 2108 / home_page 1928 / doc_page 1528 / all_docs_page 1402。
// app_lock_gate 基线 1048→1053（H-1 豁免落锁清密钥安全修复 +5）；
// drawing_controller 基线 1380→1409（P1 架构收口：公开 commitGroup/
// rollbackGroup 事务关组入口 +29，复用图层样板语义，含注释）。
// notebook_storage 基线 1466→1472（M-3 续写 DEK 零化 +6）→1502（M-1 密封
// 判定直读主文件 +30：isEncryptedNotebook 从 3 行 load 委托改 33 行直读+
// fail-closed 三分支，含注释）→1543（P3 密钥作用域 +41：_KeyScope 类+
// _currentKeyScope+storeImage 世代闸+save 锁定 fail-closed，含注释）。
// 抬升均为安全修复成本，三处交代：本注释 / CHANGELOG / commit message。
//
// 背景：单文件行数门禁（500 warn / 1000 error）对 part 拆分后的**库总量**
// 失明——主文件都不超限，库合计却破千。此前仅 editor_page 有库级棘轮
// （editor_page_line_ratchet_test.dart），其余 7 个破千库无人守门，继续
// 膨胀不会有任何门禁报警。本测试把这 7 个库的现状钉成基线：**只许减不许增**。
//
// 基线取 2026-11-16 实测（master 590b956f）：
//   note_block_doc_store 1600（2 parts）/ notebook_storage 1466（3 parts）/
//   sync_service 1389（4 parts）/ drawing_controller 1380（4 parts）/
//   app_data_root 1259（1 part）/ webdav_sync_settings_page 1052（1 part）/
//   app_lock_gate 1048（1 part）。
//
// 纪律（与 editor_page 棘轮同款）：
// - 确需增长：抬高对应基线并在 commit message 写明动机（结构裁决说明）；
// - 降行成功：同步下调基线（棘轮只紧不松）；
// - 每库配塌空下限（TE-TST-04 口径）：计数坏掉时「≤ 基线」会假绿，
//   下限抓「没数到」而非「没超」。
// - 库整体拆小/删除：从本表移除该库条目并在 commit 写明去向。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

class _LibRatchet {
  const _LibRatchet(this.name, this.mainPath, this.baseline, this.minParts, this.floor);
  final String name;
  final String mainPath;
  final int baseline;
  final int minParts;
  final int floor;
}

const List<_LibRatchet> _kLibRatchets = [
  _LibRatchet('note_block_doc_store', 'lib/core/documents/note_block_doc_store.dart', 1600, 2, 1200),
  _LibRatchet('notebook_storage', 'lib/features/notes/infrastructure/notebook_storage.dart', 1543, 3, 1100),
  _LibRatchet('sync_service', 'lib/core/sync/sync_service.dart', 1389, 4, 1000),
  _LibRatchet('drawing_controller', 'lib/features/drawing/application/drawing_controller.dart', 1409, 4, 1000),
  _LibRatchet('app_data_root', 'lib/core/storage/app_data_root.dart', 1259, 1, 900),
  _LibRatchet('webdav_sync_settings_page', 'lib/features/notes/presentation/webdav_sync_settings_page.dart', 1052, 1, 800),
  _LibRatchet('app_lock_gate', 'lib/core/security/app_lock_gate.dart', 1053, 1, 800),
  // H-4（第二轮审计 2026-11-17）：5 个破千库漏出棘轮——独立复算发现
  // 上轮「8 库破千」本身漏数。钉现状只减不许增；doc_editor 2747 是全仓
  // 最大泥球，列入下一轮重构候选。
  _LibRatchet('doc_editor', 'lib/features/doc/presentation/doc_editor.dart', 2747, 8, 2000),
  _LibRatchet('notebook_view_page', 'lib/features/notes/presentation/notebook_view_page.dart', 2108, 3, 1600),
  _LibRatchet('home_page', 'lib/features/notes/presentation/home_page.dart', 1928, 5, 1400),
  _LibRatchet('doc_page', 'lib/features/doc/presentation/doc_page.dart', 1528, 5, 1100),
  _LibRatchet('all_docs_page', 'lib/features/all_docs/presentation/all_docs_page.dart', 1402, 2, 1000),
];

int _countLines(File f) => f.readAsLinesSync().length;

void main() {
  test('R2 分母：12 个破千库全部在册（防台账静默缩水）', () {
    expect(_kLibRatchets.length, 12);
  });

  for (final lib in _kLibRatchets) {
    test('R2：${lib.name} 库总行数 ≤ ${lib.baseline}（只许减不许增）', () {
      final mainFile = File(lib.mainPath);
      expect(mainFile.existsSync(), isTrue,
          reason: '${lib.name} 主文件不存在——若库已拆小/删除，请从台账移除并写明去向');
      final dir = mainFile.parent.path;

      var total = _countLines(mainFile);
      final parts = <String>[];
      final partDecl = RegExp(r"^part\s+'([^']+)';", multiLine: true);
      for (final m in partDecl.allMatches(mainFile.readAsStringSync())) {
        final partFile = File('$dir${Platform.pathSeparator}${m.group(1)}');
        expect(partFile.existsSync(), isTrue,
            reason: '${lib.name} part 声明了不存在的文件：${m.group(1)}');
        parts.add(m.group(1)!);
        total += _countLines(partFile);
      }
      // 塌空下限：part 解析与总行数都须落在实测之下很宽的一档。
      expect(parts.length, greaterThanOrEqualTo(lib.minParts),
          reason: '${lib.name} 只解析出 ${parts.length} 个 part（基线 ${lib.minParts}）⇒ 正则失配');
      expect(total, greaterThanOrEqualTo(lib.floor),
          reason: '${lib.name} 只数出 $total 行（下限 ${lib.floor}）⇒ 读盘或计数坏了，'
              '此时「≤ 基线」成立得毫无意义：那是没数到，不是没超。');

      expect(total, lessThanOrEqualTo(lib.baseline),
          reason: '${lib.name} 库总行数 $total 超过棘轮基线 ${lib.baseline}'
              '（parts: ${parts.length}）。单文件门禁对库总量失明，本棘轮是守门人；'
              '确需增长请抬高基线并在 commit message 写明动机；降行成功请同步下调。');
    });
  }
}