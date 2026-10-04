// C-06（审计 2026-09-27）静态可达性门禁：三个安全服务在 features/shared
// 层零 `.instance` 直取。
//
// 背景：审计实测「VaultService / KekSessionCache / MediaCryptoService 三个
// 安全服务带 static 单例、全局可达，13 文件直取（含 shared 层渲染管线）」
// ——修法「收敛组合根注入」：features/shared 消费方一律构造注入（widget
// 构造参数 / application 与 infrastructure 类字段），实例由组合根装配
// （lib/app/app_services.dart 持有、lib/app/app_shell.dart 传线；编辑器链
// 经 EditorPageBuilder.mediaCrypto；缺省导出器在 default_editor_page_
// builder 组装）。
//
// 范围裁决：只扫 lib/features/** 与 lib/shared/**。
// - core/** 不限：三个服务是解锁生命周期作用域的会话单例，core 内部互调
//   （encryption_service / app_lock_* / vault_key_service / sync_cipher /
//   media_crypto_service 自身的 KEK 派生）属实现细节，按 C-06 裁决保留
//   静态语义、不注入（裁决注释已落三个服务文件的 static 段落）；
// - app/** 不限：app 层是组合根——全局实例在此装配后向下传线，这正是
//   「收敛」后的唯一合法触达点（AppServices 缺省持有 / app.dart 注入
//   NotebookStorage / default_editor_page_builder 缺省导出器）。
//
// 为什么用静态扫描而不是逐个 widget 测试：消费点分散在页面路由、编辑器
// 渲染管线与存储层，逐个搭桩既脆又漏——扫描一次性锁死「新增直取即红」，
// 与 focus_ring_coverage_test / architecture_test 同一门禁思路。
//
// 扫描前先做**等长遮蔽**（注释与字符串换成空格、保留换行）：本批次落
// 进三个服务文件与若干消费方的 C-06 裁决注释里写到了 `Xxx.instance` 字样，
// 不遮蔽会被当成真实调用（门禁首跑即假红）。
//
// 遮蔽器已于 P1 修正（审计 2026-10-04）抽到 `test/helpers/dart_lexical_mask.dart`
// 的 `maskDartLexically`，与 V-12（focus_ring_coverage_test）共用同一份实现：
// 原先两处各自复制的状态机不认 `${...}` 插值里的嵌套引号（本文件旧注释
// 「含转义与三引号」的说法与实现不符），一处嵌套引号即让字符串态错位、
// 把其后的纯代码整段抹成空格，命中落在错位区间里就直接失明放行。词法
// 细节与等长契约见该文件头注释；词法回归见 dart_lexical_mask_test.dart。
//
// 分母加固（2026-10-04，测试侧）：本门禁原先只有 `expect(offenders,
// isEmpty)`，若遮蔽器/正则失明或扫描到 0 个文件就恒绿。注意旧实现的 `total`
// 与 `offenders.add` 处在同一个循环体（原 68-71 行）、无条件同增，故
// `total` 恒等于 `offenders.length`——合规运行时必为 0，给它加
// `expect(total, greaterThan(0))` 是**永远为假**（假红）而不是牙齿。本文件的
// 真分母是「被扫描的文件数」：现以 `scannedFiles` 显式计数并设下限
// [_minScannedFiles]，另加三条反向锁用例（真代码必须被抓到 / 注释字样必须
// 不被计数 / 嵌套引号不得遮蔽后续真代码），证明判定链路本身是活的。
//
// 豁免：当前为空。若将来确需在 features/shared 直取（如深管线拿不到组合
// 根实例），把「相对 lib/ 的 posix 路径 → 理由」加进 [_exempt] 并在该文件
// 落裁决注释——不要为了让门禁变绿而删断言。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/dart_lexical_mask.dart';

/// 豁免表（相对 lib/ 的 posix 路径 → 豁免理由）。当前为空。
const Map<String, String> _exempt = {};

/// 命中模式：三个安全服务的 static 单例直取。
/// `\b` 防前缀类名粘连；带 import 前缀（`as xxx`）不影响——类名本身不变。
final RegExp _pattern = RegExp(
  r'\b(VaultService|KekSessionCache|MediaCryptoService)\.instance\b',
);

/// 被扫描文件数下限（2026-10-04 测试侧加固：封堵「分母可为 0 而恒绿」）。
///
/// 依据：实测 2026-10-04 `lib/features` 195 个 + `lib/shared` 22 个 =
/// **217** 个 .dart 文件进入扫描。取 **120**（≈55%）——本门禁扫的是两大
/// 业务层的全部文件，正常重构（合并/拆分若干文件、下线一两个页面）不可能
/// 把这两层一起砍掉四成以上；反过来，本条门禁真正的病灶——目录名写错、
/// 路径分隔符不符、`listSync` 结果被异常吞掉、遮蔽器把整段代码抹成空格
/// ——都会让计数塌到 0 或个位数，而不是「少几个」。同批 `architecture_test`
/// 的 `Metrics.martin('domain/**')` 匹配零文件（commit 96261cc）就是这类
/// 病灶：恒绿的门禁比没有门禁更危险。
const int _minScannedFiles = 120;

/// 对**遮蔽后**的代码文本求命中行号（与主循环同一份判定逻辑）。
///
/// 抽出来的目的只有一个：让反向锁能把「人造样本」喂给与真实扫描**完全相同**
/// 的路径，而不是另写一遍正则——另写的副本测不出主路径失明。
List<int> _hitLines(String maskedCode) => [
  for (final m in _pattern.allMatches(maskedCode))
    maskedCode.substring(0, m.start).split('\n').length,
];

/// 反向锁样本 A：真代码里的直取——必须被看见（证明正则/遮蔽器/行号计算
/// 这条链路是活的，而不是「扫不到任何东西所以永远绿」）。
const String _sampleRealHit = r'''
class EditorPage {
  void load() {
    VaultService.instance.unlock();
  }
}
''';

/// 反向锁样本 B：只出现在注释/字符串里的字样——必须**不**被计数。
/// 证明遮蔽器确实在遮蔽（若遮蔽器整体失效，裁决注释里的 `Xxx.instance`
/// 字样会让门禁假红，历史上首跑即栽过）。
const String _sampleMaskedOnly = r'''
// 裁决注释：此处曾直取 VaultService.instance，已改构造注入。
class EditorPage {
  String get hint => 'VaultService.instance 只是文案，不是调用';
}
/* 块注释里也有 MediaCryptoService.instance */
''';

/// 反向锁样本 C：**历史病灶复现**。插值里的嵌套引号曾把旧版状态机的字符串态
/// 骗跑偏，导致其后的纯代码被整段抹成空格、命中被失明放行（P1 修复缘起，
/// 见 helpers/dart_lexical_mask.dart 头注释与 lib/features/notes/
/// presentation/conflict_resolution_dialog.dart:92）。
/// 现遮蔽器必须仍在第 4 行（真代码）取到唯一命中。
const String _sampleNestedQuoteTrap = r'''
class ConflictDialog {
  String f(String n) => 'conflict ${"nested " + n} tail';
  // 注释里的 VaultService.instance 不算
  void load() => VaultService.instance.unlock();
}
''';

void main() {
  test('C-06：features/shared 层零安全服务 `.instance` 直取', () {
    final offenders = <String>[];
    var scannedFiles = 0;

    for (final dir in const ['lib/features', 'lib/shared']) {
      for (final entity in Directory(dir).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final rel = entity.path.replaceAll(r'\', '/');
        final relToLib = rel.substring(rel.indexOf('lib/'));
        if (_exempt.containsKey(relToLib)) continue;

        final code = maskDartLexically(entity.readAsStringSync());
        scannedFiles++;
        for (final line in _hitLines(code)) {
          offenders.add('$relToLib:$line');
        }
      }
    }

    // 分母下限必须先于结论断言：扫描面塌掉时直接报「门禁失明」，
    // 不要让「零命中」被误读成「零违规」。
    expect(
      scannedFiles,
      greaterThanOrEqualTo(_minScannedFiles),
      reason:
          'C-06 门禁扫描面异常：只扫到 $scannedFiles 个 .dart 文件（下限 '
          '$_minScannedFiles，实测 2026-10-04 为 217 = lib/features 195 + '
          'lib/shared 22）。这说明扫描根目录/后缀/豁免表或遮蔽器出了问题——'
          '此时「零命中」是失明而非合规，本条门禁已失去裁决力，必须修扫描'
          '口径，绝不能改成放宽下限。',
    );

    expect(
      offenders,
      isEmpty,
      reason:
          'C-06（审计 2026-09-27）：以下 features/shared 代码直取了安全服务 '
          'static 单例（VaultService / KekSessionCache / MediaCryptoService '
          '的 `.instance`）——全局可达、绕过组合根，测试无法隔离，会话密钥'
          '生命周期失控。\n'
          '修法：构造注入——widget 加构造参数、application/infrastructure 类'
          '加字段，实例由组合根装配（lib/app/app_services.dart 持有、'
          'lib/app/app_shell.dart 传线；编辑器链经 EditorPageBuilder.'
          'mediaCrypto；参照本批 search_page / notebook_view_page / '
          'encrypted_file_image / notebook_pdf_exporter 的既有改法）。\n'
          '豁免流程：确需豁免时把「相对 lib/ 的 posix 路径 → 理由」写进本文件 '
          '[_exempt] 豁免表，并在该文件落裁决注释（含替代方案评估）；'
          '不许为了变绿删断言、也不许豁免表进空理由。\n'
          '命中 ${offenders.length} 处 / 本次扫描 $scannedFiles 个文件：\n'
          '${offenders.take(30).join('\n')}',
    );
  });

  // 反向锁（2026-10-04 加固）：本门禁原先只有 `expect(offenders, isEmpty)`，
  // 遮蔽器或正则一旦失明就恒绿。以下用例证明「同一条判定链路确实能抓到
  // 直取」，并且两个**相反方向**都成立：
  // - 真代码里的字样必须被计数（否则门禁是瞎的）；
  // - 注释/字符串里的字样必须不被计数（否则首跑即假红、且说明遮蔽器已失效）。
  // 样本全部走内存字符串、不落盘，不改变 lib/ 的任何内容。
  test('C-06 反向锁：判定链路能抓到真代码里的 `.instance` 直取', () {
    final hits = _hitLines(maskDartLexically(_sampleRealHit));
    expect(
      hits,
      hasLength(1),
      reason:
          '反向锁失效：样本里的真代码 `VaultService.instance.unlock();` 未被'
          '计数——遮蔽器或 _pattern 已失明，主用例的「零命中」不再等于合规。',
    );
    // 等长遮蔽契约：行号与原文一一对应。注意 Dart 规范——三引号字符串
    // 紧跟开引号的**第一个换行不计入内容**，故样本里 `class` 就是第 1 行、
    // 直取调用是第 3 行。
    expect(hits.single, 3, reason: '行号漂移说明遮蔽不再是等长替换');
  });

  test('C-06 反向锁：注释/字符串里的字样不得被计数（遮蔽器确实在遮蔽）', () {
    expect(
      _hitLines(maskDartLexically(_sampleMaskedOnly)),
      isEmpty,
      reason:
          '裁决注释与字符串文案里的 `.instance` 字样被当成真实调用——'
          '遮蔽器失效会让门禁在任何人写一句说明注释时假红。',
    );
  });

  test('C-06 反向锁：嵌套引号插值之后的真代码仍被看见（历史病灶）', () {
    final hits = _hitLines(maskDartLexically(_sampleNestedQuoteTrap));
    expect(
      hits,
      hasLength(1),
      reason:
          '历史病灶复现：插值里的嵌套引号一旦让字符串状态机错位，其后的纯代码'
          '会被整段抹成空格，落在错位区间里的 `.instance` 直取就被失明放行'
          '（P1 修复缘起）。计数归零即遮蔽器退化。',
    );
    expect(hits.single, 4, reason: '应命中第 4 行的真代码调用，而非注释行 3');
    // （三引号后紧跟的首个换行不计入内容，故 `class` 为第 1 行。）
  });
}
