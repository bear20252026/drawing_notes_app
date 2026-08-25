import 'dart:io';

import 'package:drawing_notes_app/core/platform/file_association.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileAssociation.extractProjectPath', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('file_association_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('从参数中提取 .dnproj 文件路径', () async {
      final testFile = File('${tempDir.path}${Platform.pathSeparator}test.dnproj');
      await testFile.writeAsString('test');

      final args = [
        'some_arg',
        testFile.path,
        'another_arg',
      ];

      final result = FileAssociation.extractProjectPath(args);
      expect(result, testFile.path);
    });

    test('无 .dnproj 文件时返回 null', () {
      final args = ['foo.dart', 'bar.txt', '--verbose'];
      final result = FileAssociation.extractProjectPath(args);
      expect(result, isNull);
    });

    test('.dnproj 文件不存在时返回 null', () {
      final args = ['${tempDir.path}${Platform.pathSeparator}nonexistent.dnproj'];
      final result = FileAssociation.extractProjectPath(args);
      expect(result, isNull);
    });

    test('空参数列表返回 null', () {
      final result = FileAssociation.extractProjectPath([]);
      expect(result, isNull);
    });

    test('多个 .dnproj 时返回第一个存在的', () async {
      final file1 = File('${tempDir.path}${Platform.pathSeparator}a.dnproj');
      final file2 = File('${tempDir.path}${Platform.pathSeparator}b.dnproj');
      await file1.writeAsString('a');
      await file2.writeAsString('b');

      final result = FileAssociation.extractProjectPath([file1.path, file2.path]);
      expect(result, file1.path);
    });

    test('参数中有不存在的 .dnproj 不会被返回', () {
      final result = FileAssociation.extractProjectPath(['something.dnproj']);
      expect(result, isNull);
    });
  });

  group('FileAssociation.extractAllProjectPaths', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('file_association_all_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('提取所有存在的 .dnproj 文件', () async {
      final file1 = File('${tempDir.path}${Platform.pathSeparator}x.dnproj');
      final file2 = File('${tempDir.path}${Platform.pathSeparator}y.dnproj');
      await file1.writeAsString('x');
      await file2.writeAsString('y');

      final result = FileAssociation.extractAllProjectPaths([
        'readme.md',
        file1.path,
        file2.path,
        'config.yaml',
      ]);

      expect(result, hasLength(2));
      expect(result, contains(file1.path));
      expect(result, contains(file2.path));
    });

    test('无 .dnproj 返回空列表', () {
      final result = FileAssociation.extractAllProjectPaths(['foo', 'bar']);
      expect(result, isEmpty);
    });

    test('不存在的 .dnproj 被过滤', () {
      final result = FileAssociation.extractAllProjectPaths([
        '${tempDir.path}${Platform.pathSeparator}ghost.dnproj',
      ]);
      expect(result, isEmpty);
    });

    test('空列表返回空', () {
      expect(FileAssociation.extractAllProjectPaths([]), isEmpty);
    });

    test('混合存在和不存在的 .dnproj', () async {
      final file1 = File('${tempDir.path}${Platform.pathSeparator}exists.dnproj');
      await file1.writeAsString('exists');

      final result = FileAssociation.extractAllProjectPaths([
        file1.path,
        '${tempDir.path}${Platform.pathSeparator}not_exist.dnproj',
      ]);

      expect(result, hasLength(1));
      expect(result, contains(file1.path));
    });
  });

  group('FileAssociation.register / unregister', () {
    test('registerFileAssociation 不抛异常', () {
      expect(
        () => FileAssociation.registerFileAssociation(),
        returnsNormally,
      );
    });

    test('unregisterFileAssociation 不抛异常', () {
      expect(
        () => FileAssociation.unregisterFileAssociation(),
        returnsNormally,
      );
    });
  });
}
