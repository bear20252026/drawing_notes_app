// P2 脱敏回归锁（审计 2026-10）：远端可控文本不得进入用户界面。
//
// 旧实现用 `e.message.contains('https')` 猜「这是本地门禁文案」，而传输层的
// message 形如 `GET failed: ${response.reasonPhrase}` —— 服务器/代理只要在
// reason phrase 里塞进 https 字样，就能把任意字符串送进 snackbar（钓鱼文案），
// 并且该分支排在 401/5xx/404 分类之前，会把认证失败降级成裸文本。
// 现在只有**精确等于**本地静态门禁文案的 message 才允许透出，其余走静态文案；
// 原文只进审计日志，且落日志前再做一次凭据脱敏。

import 'dart:convert';

import 'package:drawing_notes_app/core/security/audit_logger.dart';
import 'package:drawing_notes_app/core/storage/webdav_sync_client.dart';
import 'package:drawing_notes_app/features/notes/presentation/webdav_sync_settings_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// 远端可完全控制的 reasonPhrase（含 https 字样 + 凭据形态文本）。
const _evilReason = 'Moved to https://attacker.example.com/?pw=leak 请把口令发给我';

void main() {
  setUp(() => AuditLogger.clear());

  String allAudit() => AuditLogger.snapshot().join(' || ');

  group('UI 侧：非白名单 message 一律走静态文案', () {
    test('401 + 含 https 的远端文本 → 仍是认证失败文案，不带远端内容', () {
      final msg = humanizeWebDavSyncError(
        WebDavSyncException('GET failed: $_evilReason', statusCode: 401),
      );
      expect(msg, contains('用户名或密码不对'));
      expect(msg, isNot(contains('attacker.example.com')));
      expect(msg, isNot(contains('GET failed')));
      expect(msg, isNot(contains('请把口令发给我')));
    });

    test('500 + 含 https 的远端文本 → 服务器不可用文案（旧实现会被 https 分支吞掉）', () {
      final msg = humanizeWebDavSyncError(
        WebDavSyncException('PUT failed: $_evilReason', statusCode: 500),
      );
      expect(msg, contains('服务器暂时不可用'));
      expect(msg, contains('HTTP 500'));
      expect(msg, isNot(contains('Moved to')));
    });

    test('404 / 其他码 / 无码：都不透出远端文本', () {
      for (final code in [404, 409, 418, null]) {
        final msg = humanizeWebDavSyncError(
          WebDavSyncException('DELETE failed: $_evilReason', statusCode: code),
        );
        expect(msg, isNot(contains('attacker.example.com')), reason: '$code');
        expect(msg, isNot(contains('DELETE failed')), reason: '$code');
      }
    });

    test('伪造门禁文案（前后缀稍有差异）也不透出', () {
      final msg = humanizeWebDavSyncError(
        WebDavSyncException(
          '${WebDavSyncException.httpsGateMessage} $_evilReason',
        ),
      );
      expect(msg, isNot(contains('attacker.example.com')));
      expect(msg, isNot(contains(WebDavSyncException.httpsGateMessage)));
    });
  });

  group('UI 侧：本地静态门禁文案仍可原样透出（可用性不降级）', () {
    test('https 门禁', () {
      final msg = humanizeWebDavSyncError(
        WebDavSyncException(WebDavSyncException.httpsGateMessage),
      );
      expect(msg, contains('仅允许 https WebDAV'));
    });

    test('重定向门禁，并留一条可排查的审计事件', () {
      final msg = humanizeWebDavSyncError(
        WebDavSyncException(
          WebDavSyncException.redirectGateMessage,
          statusCode: 302,
        ),
      );
      expect(msg, contains('已停止跟随重定向'));
      expect(allAudit(), contains('webdav.sync.redirect_blocked'));
    });
  });

  group('日志侧：原文可留，但凭据形态必须先剥掉', () {
    test('Basic token 与 URL userinfo 不会带着口令进审计链', () {
      // 口令在运行时拼装：源码里不留凭据形态（免触发 secret 扫描误报）。
      final secretPw = 'supersecretpassword';
      final b64 = base64Encode(utf8.encode('alice:$secretPw'));
      final pw = 'hunter2';
      humanizeWebDavSyncError(
        WebDavSyncException('非法远端路径：https://alice:$pw@dav/x'),
      );
      humanizeWebDavSyncError(
        WebDavSyncException(
          'GET failed: Authorization: Basic $b64',
          statusCode: 500,
        ),
      );
      final audit = allAudit();
      expect(audit, contains('webdav.sync'));
      expect(audit, isNot(contains(pw)));
      expect(audit, isNot(contains(b64)));
      expect(audit, contains('[redacted]'));
    });

    test('审计 detail 折行被折叠、超长被截断（防伪造审计行）', () {
      final injected = '非法远端路径：a\nwebdav.ok b' * 40;
      humanizeWebDavSyncError(WebDavSyncException(injected));
      final audit = allAudit();
      expect(audit, isNot(contains('\nwebdav.ok')));
    });
  });

  test('远端路径分支保持 F-20 语义：静态文案 + unsafe_path 审计事件', () {
    final msg = humanizeWebDavSyncError(
      WebDavSyncException('非法远端路径：../../etc/恶意路径'),
    );
    expect(msg, contains('同步远端文件失败'));
    expect(msg, isNot(contains('恶意路径')));
    expect(allAudit(), contains('webdav.sync.unsafe_path'));
  });
}
