import 'package:drawing_notes_app/features/drawing/application/clipboard_image_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClipboardImageService', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            return null; // No image in clipboard
          }
          if (call.method == 'Clipboard.hasStrings') {
            return {'value': false};
          }
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('getImage returns null when clipboard has no image', () async {
      final result = await ClipboardImageService.getImage();
      expect(result, isNull);
    });

    test('getImageAsPng returns null when clipboard has no image', () async {
      final result = await ClipboardImageService.getImageAsPng();
      expect(result, isNull);
    });

    test('hasImage returns false when clipboard has no image', () async {
      final result = await ClipboardImageService.hasImage();
      expect(result, isFalse);
    });
  });
}
