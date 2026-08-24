import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:drawing_notes_app/features/drawing/presentation/editor_page_drop_handler.dart';

void main() {
  group('DropHandler', () {
    test('detectType 识别 PNG 图片', () {
      expect(DropHandler.detectType('image.png'), DropFileType.image);
      expect(DropHandler.detectType('photo.PNG'), DropFileType.image);
    });

    test('detectType 识别 JPG 图片', () {
      expect(DropHandler.detectType('photo.jpg'), DropFileType.image);
      expect(DropHandler.detectType('photo.jpeg'), DropFileType.image);
      expect(DropHandler.detectType('photo.JPG'), DropFileType.image);
    });

    test('detectType 识别其他图片格式', () {
      expect(DropHandler.detectType('anim.gif'), DropFileType.image);
      expect(DropHandler.detectType('modern.webp'), DropFileType.image);
      expect(DropHandler.detectType('legacy.bmp'), DropFileType.image);
    });

    test('detectType 识别非图片文件', () {
      expect(DropHandler.detectType('document.pdf'), DropFileType.unknown);
      expect(DropHandler.detectType('data.json'), DropFileType.unknown);
      expect(DropHandler.detectType('readme.txt'), DropFileType.unknown);
      expect(DropHandler.detectType('noextension'), DropFileType.unknown);
    });

    test('readFiles 返回正确数量', () async {
      final files = await DropHandler.readFiles([
        '/path/to/image.png',
        '/path/to/doc.pdf',
        '/path/to/photo.jpg',
      ]);
      expect(files, hasLength(3));
      expect(files[0].type, DropFileType.image);
      expect(files[1].type, DropFileType.unknown);
      expect(files[2].type, DropFileType.image);
    });

    test('readFiles 提取文件名', () async {
      final files = await DropHandler.readFiles([
        'C:\\Users\\test\\Pictures\\photo.png',
      ]);
      expect(files.first.name, 'photo.png');
    });
  });

  group('DropFile', () {
    test('isImage 属性', () {
      final imageFile = DropFile(
        name: 'test.png',
        type: DropFileType.image,
        bytes: Uint8List(0),
      );
      expect(imageFile.isImage, isTrue);

      final otherFile = DropFile(
        name: 'test.pdf',
        type: DropFileType.unknown,
        bytes: Uint8List(0),
      );
      expect(otherFile.isImage, isFalse);
    });

    test('携带 mimeType', () {
      final file = DropFile(
        name: 'test.png',
        type: DropFileType.image,
        bytes: Uint8List(0),
        mimeType: 'image/png',
      );
      expect(file.mimeType, 'image/png');
    });
  });

  group('DropRegionState', () {
    test('初始状态非拖放', () {
      final state = DropRegionState();
      expect(state.isDragging, isFalse);
    });

    test('setDragging 更新状态', () {
      final state = DropRegionState();
      state.setDragging(true);
      expect(state.isDragging, isTrue);
      state.setDragging(false);
      expect(state.isDragging, isFalse);
    });

    test('重复设置不触发通知', () {
      var notifyCount = 0;
      final state = DropRegionState();
      state.addListener(() => notifyCount++);

      state.setDragging(true);
      state.setDragging(true); // 重复设置
      expect(notifyCount, 1);

      state.setDragging(false);
      expect(notifyCount, 2);
    });
  });
}
