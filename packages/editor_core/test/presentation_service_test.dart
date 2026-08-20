import 'package:test/test.dart';

import 'package:editor_core/editor_core.dart';

/// AFFiNE 借鉴——PresentationService 幻灯片测试（纯逻辑——不搞崩）。
void main() {
  late List<PageV2> pages;
  late PresentationService service;

  setUp(() {
    pages = [
      const PageV2(id: 'p1', index: 0, document: DocumentV2(id: 'd1', pageCount: 1)),
      const PageV2(id: 'p2', index: 1, document: DocumentV2(id: 'd2', pageCount: 1)),
      const PageV2(id: 'p3', index: 2, document: DocumentV2(id: 'd3', pageCount: 1)),
    ];
    service = PresentationService(pages);
  });

  test('初始状态：第一页', () {
    expect(service.currentIndex, 0);
    expect(service.currentPage!.id, 'p1');
    expect(service.hasPrev, false);
    expect(service.hasNext, true);
    expect(service.isPlaying, false);
  });

  test('next/prev：翻页', () {
    service.next();
    expect(service.currentIndex, 1);
    expect(service.currentPage!.id, 'p2');
    service.next();
    expect(service.currentIndex, 2);
    service.prev();
    expect(service.currentIndex, 1);
  });

  test('next：边界（最后一页不再前进）', () {
    service.goTo(2);
    service.next();
    expect(service.currentIndex, 2); // 边界。
    expect(service.hasNext, false);
  });

  test('prev：边界（第一页不再后退）', () {
    service.prev();
    expect(service.currentIndex, 0); // 边界。
    expect(service.hasPrev, false);
  });

  test('goTo：跳转（边界安全）', () {
    service.goTo(1);
    expect(service.currentIndex, 1);
    service.goTo(99); // 越界——不变。
    expect(service.currentIndex, 1);
    service.goTo(-1); // 负——不变。
    expect(service.currentIndex, 1);
  });

  test('play/stop/reset：播放状态', () {
    service.play();
    expect(service.isPlaying, true);
    service.next();
    service.stop();
    expect(service.isPlaying, false);
    service.reset();
    expect(service.currentIndex, 0);
    expect(service.isPlaying, false);
  });
}
