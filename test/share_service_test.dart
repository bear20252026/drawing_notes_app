import 'package:drawing_notes_app/features/drawing/application/share_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShareService', () {
    late List<MethodCall> methodCalls;

    setUp(() {
      methodCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('gov.drawingnotes/share'),
        (call) async {
          methodCalls.add(call);
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('gov.drawingnotes/share'),
        null,
      );
    });

    test('shareText sends correct method call', () async {
      await ShareService.shareText(text: 'Hello World', title: 'Test Title');

      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'shareText');
      expect(methodCalls[0].arguments['text'], 'Hello World');
      expect(methodCalls[0].arguments['title'], 'Test Title');
    });

    test('shareText without title sends default', () async {
      await ShareService.shareText(text: 'Hello World');

      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'shareText');
      expect(methodCalls[0].arguments['text'], 'Hello World');
      expect(methodCalls[0].arguments['title'], isNotNull);
    });

    test('shareFile sends correct method call', () async {
      await ShareService.shareFile(
        filePath: '/tmp/test.png',
        mimeType: 'image/png',
        title: 'Test File',
      );

      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'shareFile');
      expect(methodCalls[0].arguments['filePath'], '/tmp/test.png');
      expect(methodCalls[0].arguments['mimeType'], 'image/png');
      expect(methodCalls[0].arguments['title'], 'Test File');
    });

    test('shareFile without title sends default', () async {
      await ShareService.shareFile(
        filePath: '/tmp/test.png',
        mimeType: 'image/png',
      );

      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'shareFile');
      expect(methodCalls[0].arguments['title'], isNotNull);
    });

    test('shareText handles MissingPluginException gracefully', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('gov.drawingnotes/share'),
        (call) async {
          throw MissingPluginException('Plugin not found');
        },
      );

      // Should not throw
      await ShareService.shareText(text: 'Hello');
    });

    test('shareFile handles MissingPluginException gracefully', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('gov.drawingnotes/share'),
        (call) async {
          throw MissingPluginException('Plugin not found');
        },
      );

      // Should not throw
      await ShareService.shareFile(filePath: '/tmp/test.png', mimeType: 'image/png');
    });
  });
}
