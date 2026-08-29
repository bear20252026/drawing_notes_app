// M11 契约测试：FavoriteStore 收藏持久化（临时目录注入）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/features/all_docs/infrastructure/favorite_store.dart';

void main() {
  late Directory tempDir;
  late FavoriteStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fav_store_test');
    store = FavoriteStore(directoryProvider: () async => tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('初始为空集', () async {
    expect(await store.loadKeys(), isEmpty);
  });

  test('toggleKey 添加与取消', () async {
    expect(await store.toggleKey('canvas:a'), isTrue);
    expect(await store.loadKeys(), {'canvas:a'});
    expect(await store.toggleKey('canvas:a'), isFalse);
    expect(await store.loadKeys(), isEmpty);
  });

  test('多键持久化跨实例可读', () async {
    await store.addKey('canvas:a');
    await store.addKey('blockdoc:b');
    final reopened = FavoriteStore(directoryProvider: () async => tempDir);
    expect(await reopened.loadKeys(), {'canvas:a', 'blockdoc:b'});
  });

  test('损坏文件 fail-open 返回空集', () async {
    await store.addKey('canvas:a');
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}all_docs_favorites.json',
    );
    await file.writeAsString('not-json{{');
    final reopened = FavoriteStore(directoryProvider: () async => tempDir);
    expect(await reopened.loadKeys(), isEmpty);
  });
}
