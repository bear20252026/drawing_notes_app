// editor_core——PresentationService（AFFiNE 幻灯片借鉴——2026-08-21）。
//
// 演示模式（全屏播放/翻页）——基于 PageV2 分页——纯 Dart 可测试。
// AFFiNE 幻灯片（presentation——大纲→幻灯片）本地化——不搞崩。
library;

import '../domain/page_v2.dart';

/// 演示服务（幻灯片模式——AFFiNE 借鉴）。
///
/// 基于 [PageV2] 分页——播放/翻页/跳转——纯逻辑（可独立测试）。
class PresentationService {
  PresentationService(this.pages);

  /// 演示页面（顺序）。
  final List<PageV2> pages;

  int _currentIndex = 0;
  bool _playing = false;

  /// 当前页索引。
  int get currentIndex => _currentIndex;

  /// 当前页。
  PageV2? get currentPage =>
      pages.isNotEmpty ? pages[_currentIndex] : null;

  /// 是否有下一页。
  bool get hasNext => _currentIndex < pages.length - 1;

  /// 是否有上一页。
  bool get hasPrev => _currentIndex > 0;

  /// 是否播放中。
  bool get isPlaying => _playing;

  /// 下一页。
  void next() {
    if (hasNext) _currentIndex++;
  }

  /// 上一页。
  void prev() {
    if (hasPrev) _currentIndex--;
  }

  /// 跳转到指定页（边界安全）。
  void goTo(int index) {
    if (index >= 0 && index < pages.length) _currentIndex = index;
  }

  /// 开始播放。
  void play() => _playing = true;

  /// 停止播放。
  void stop() => _playing = false;

  /// 重置到第一页。
  void reset() {
    _currentIndex = 0;
    _playing = false;
  }
}
