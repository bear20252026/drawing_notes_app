import 'dart:io';

import 'package:drawing_notes_app/features/drawing/application/file_drop_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileDropService', () {
    test('supportedImageExtensions contains common image formats', () {
      expect(FileDropService.supportedImageExtensions, contains('png'));
      expect(FileDropService.supportedImageExtensions, contains('jpg'));
      expect(FileDropService.supportedImageExtensions, contains('jpeg'));
      expect(FileDropService.supportedImageExtensions, contains('gif'));
      expect(FileDropService.supportedImageExtensions, contains('bmp'));
      expect(FileDropService.supportedImageExtensions, contains('webp'));
    });

    test('supportedDocumentExtensions contains json svg pdf', () {
      expect(FileDropService.supportedDocumentExtensions, contains('json'));
      expect(FileDropService.supportedDocumentExtensions, contains('svg'));
      expect(FileDropService.supportedDocumentExtensions, contains('pdf'));
    });

    test('isSupportedImage returns true for supported extensions', () {
      expect(FileDropService.isSupportedImage('image.png'), isTrue);
      expect(FileDropService.isSupportedImage('image.jpg'), isTrue);
      expect(FileDropService.isSupportedImage('image.jpeg'), isTrue);
      expect(FileDropService.isSupportedImage('IMAGE.PNG'), isTrue);
    });

    test('isSupportedImage returns false for unsupported extensions', () {
      expect(FileDropService.isSupportedImage('document.pdf'), isFalse);
      expect(FileDropService.isSupportedImage('video.mp4'), isFalse);
      expect(FileDropService.isSupportedImage('text.txt'), isFalse);
    });

    test('isSupportedDocument returns true for document extensions', () {
      expect(FileDropService.isSupportedDocument('drawing.json'), isTrue);
      expect(FileDropService.isSupportedDocument('image.svg'), isTrue);
      expect(FileDropService.isSupportedDocument('doc.pdf'), isTrue);
    });

    test('isSupportedDocument returns false for non-document extensions', () {
      expect(FileDropService.isSupportedDocument('image.png'), isFalse);
      expect(FileDropService.isSupportedDocument('video.mp4'), isFalse);
    });

    test('isSupportedFile returns true for both image and document', () {
      expect(FileDropService.isSupportedFile('image.png'), isTrue);
      expect(FileDropService.isSupportedFile('drawing.json'), isTrue);
      expect(FileDropService.isSupportedFile('video.mp4'), isFalse);
    });

    test('readImageFile returns null for nonexistent file', () async {
      final result = await FileDropService.readImageFile('/nonexistent/file.png');
      expect(result, isNull);
    });

    test('readImageFile returns null for unsupported format', () async {
      final tmpDir = Directory.systemTemp;
      final tmpFile = File('${tmpDir.path}/test_file_drop.txt');
      await tmpFile.writeAsString('test');

      final result = await FileDropService.readImageFile(tmpFile.path);
      expect(result, isNull);

      if (await tmpFile.exists()) await tmpFile.delete();
    });

    test('readImageFile returns data for valid image file', () async {
      final tmpDir = Directory.systemTemp;
      final tmpFile = File('${tmpDir.path}/test_file_drop.png');
      // Write minimal PNG header bytes
      await tmpFile.writeAsBytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

      final result = await FileDropService.readImageFile(tmpFile.path);
      expect(result, isNotNull);
      expect(result!.length, 8);

      if (await tmpFile.exists()) await tmpFile.delete();
    });
  });
}
