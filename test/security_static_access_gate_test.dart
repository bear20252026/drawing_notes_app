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

void main() {
  test('C-06：features/shared 层零安全服务 `.instance` 直取', () {
    final offenders = <String>[];
    var total = 0;

    for (final dir in const ['lib/features', 'lib/shared']) {
      for (final entity in Directory(dir).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final rel = entity.path.replaceAll(r'\', '/');
        final relToLib = rel.substring(rel.indexOf('lib/'));
        if (_exempt.containsKey(relToLib)) continue;

        final code = maskDartLexically(entity.readAsStringSync());
        for (final m in _pattern.allMatches(code)) {
          total++;
          final line = code.substring(0, m.start).split('\n').length;
          offenders.add('$relToLib:$line');
        }
      }
    }

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
          '命中 ${offenders.length} 处 / 共 $total 处：\n'
          '${offenders.take(30).join('\n')}',
    );
  });
}
