// R1：WebDAV 同步错误文案人话映射——用户界面不出现裸异常对象。
import 'dart:async';
import 'dart:io';

import 'package:drawing_notes_app/core/storage/webdav_sync_client.dart';
import 'package:drawing_notes_app/features/notes/presentation/webdav_sync_settings_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('humanizeWebDavSyncError', () {
    test('null → 未知错误', () {
      expect(humanizeWebDavSyncError(null), contains('未知错误'));
    });

    test('String → 原样透传（重试上限等策略文案）', () {
      expect(humanizeWebDavSyncError('达到最大重试次数'), contains('达到最大重试次数'));
    });

    test('WebDavSyncException 401/403 → 认证失败人话', () {
      final msg = humanizeWebDavSyncError(
        WebDavSyncException('GET failed: Unauthorized', statusCode: 401),
      );
      expect(msg, contains('用户名或密码不对'));
      expect(msg, isNot(contains('GET failed')));
    });

    test('WebDavSyncException 5xx → 服务器不可用人话', () {
      final msg = humanizeWebDavSyncError(
        WebDavSyncException(
          'PUT failed: Internal Server Error',
          statusCode: 500,
        ),
      );
      expect(msg, contains('服务器暂时不可用'));
      expect(msg, contains('HTTP 500'));
    });

    test('WebDavSyncException 404/409 → 目录问题人话', () {
      final msg = humanizeWebDavSyncError(
        WebDavSyncException('MKCOL failed: Conflict', statusCode: 409),
      );
      expect(msg, contains('服务器目录不存在或路径被占用'));
    });

    test('SocketException / TimeoutException → 网络人话', () {
      final a = humanizeWebDavSyncError(
        const SocketException('Connection refused (os error 111)'),
      );
      final b = humanizeWebDavSyncError(TimeoutException('timeout'));
      expect(a, contains('连不上服务器'));
      expect(b, contains('连不上服务器'));
      expect(a, isNot(contains('os error')));
    });

    test('HandshakeException → HTTPS 握手人话', () {
      final msg = humanizeWebDavSyncError(
        const HandshakeException('handshake failed'),
      );
      expect(msg, contains('握手失败'));
    });

    test('未知异常 → 兜底人话，不泄露异常内容', () {
      final msg = humanizeWebDavSyncError(const FormatException('bad json'));
      expect(msg, contains('请检查网络与账号设置'));
      expect(msg, isNot(contains('bad json')));
    });
  });
}
