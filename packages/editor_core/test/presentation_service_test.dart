import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// PresentationService 幻灯片播放逻辑测试（纯 Dart 可测试——不搞崩）。
void main() {
  /// 辅助：创建带 DocumentV2 的 PageV2。
  PageV2 makePage(String id, int index) {
    return PageV2(
      id: id,
      document: DocumentV2(id: 'doc_$id', pageCount: 1),
      index: index,
    );
  }

  group('PresentationService', () {
    test('空页面列表——currentPage 为 null', () {
      final svc = PresentationService([]);
      expect(svc.currentPage, isNull);
      expect(svc.hasNext, isFalse);
      expect(svc.hasPrev, isFalse);
    });

    test('单页——初始 currentPage 指向第 0 页', () {
      final svc = PresentationService([makePage('p0', 0)]);
      expect(svc.currentPage!.id, 'p0');
      expect(svc.currentIndex, 0);
      expect(svc.hasNext, isFalse);
      expect(svc.hasPrev, isFalse);
    });

    test('多页——next 递增 currentIndex', () {
      final pages = [
        makePage('p0', 0),
        makePage('p1', 1),
        makePage('p2', 2),
      ];
      final svc = PresentationService(pages);
      expect(svc.currentIndex, 0);

      svc.next();
      expect(svc.currentIndex, 1);
      expect(svc.currentPage!.id, 'p1');

      svc.next();
      expect(svc.currentIndex, 2);
      expect(svc.currentPage!.id, 'p2');

      // 边界——不再递增。
      svc.next();
      expect(svc.currentIndex, 2);
    });

    test('多页——prev 递减 currentIndex', () {
      final pages = [
        makePage('p0', 0),
        makePage('p1', 1),
        makePage('p2', 2),
      ];
      final svc = PresentationService(pages);
      svc.goTo(2);
      expect(svc.currentIndex, 2);

      svc.prev();
      expect(svc.currentIndex, 1);

      svc.prev();
      expect(svc.currentIndex, 0);

      // 边界——不再递减。
      svc.prev();
      expect(svc.currentIndex, 0);
    });

    test('goTo 跳转指定页', () {
      final pages = [
        makePage('p0', 0),
        makePage('p1', 1),
        makePage('p2', 2),
      ];
      final svc = PresentationService(pages);
      svc.goTo(2);
      expect(svc.currentIndex, 2);
      expect(svc.currentPage!.id, 'p2');
    });

    test('goTo 负数边界安全', () {
      final pages = [makePage('p0', 0)];
      final svc = PresentationService(pages);
      svc.goTo(-1);
      expect(svc.currentIndex, 0); // 不变。
    });

    test('goTo 超出边界安全', () {
      final pages = [makePage('p0', 0)];
      final svc = PresentationService(pages);
      svc.goTo(100);
      expect(svc.currentIndex, 0); // 不变。
    });

    test('play/stop 切换 isPlaying', () {
      final svc = PresentationService([makePage('p0', 0)]);
      expect(svc.isPlaying, isFalse);

      svc.play();
      expect(svc.isPlaying, isTrue);

      svc.stop();
      expect(svc.isPlaying, isFalse);
    });

    test('reset 重置到第一页并停止播放', () {
      final pages = [
        makePage('p0', 0),
        makePage('p1', 1),
        makePage('p2', 2),
      ];
      final svc = PresentationService(pages);
      svc.goTo(2);
      svc.play();
      expect(svc.currentIndex, 2);
      expect(svc.isPlaying, isTrue);

      svc.reset();
      expect(svc.currentIndex, 0);
      expect(svc.isPlaying, isFalse);
      expect(svc.currentPage!.id, 'p0');
    });

    test('hasNext/hasPrev 边界正确', () {
      final pages = [
        makePage('p0', 0),
        makePage('p1', 1),
      ];
      final svc = PresentationService(pages);

      // 第一页。
      expect(svc.hasPrev, isFalse);
      expect(svc.hasNext, isTrue);

      // 最后一页。
      svc.next();
      expect(svc.hasPrev, isTrue);
      expect(svc.hasNext, isFalse);
    });
  });
}
