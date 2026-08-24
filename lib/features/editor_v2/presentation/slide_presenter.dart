// SlidePresenter——幻灯片模式（AFFiNE 借鉴——2026-08-24）。
//
// 基于 NoteDocument 分页——支持：
// - 全屏播放
// - 翻页（左右滑动/键盘）
// - 退出（Esc）
// - 页码指示
//
// 版权：AFFiNE（BSL 1.1）——仅概念借鉴——NOTICE 已记录。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:editor_core/editor_core.dart';

/// 幻灯片页面数据（从 NoteDocument 段落分页生成）。
class SlidePage {
  const SlidePage({
    required this.title,
    required this.paragraphs,
  });

  final String title;
  final List<NoteParagraph> paragraphs;
}

/// 幻灯片模式 Widget（AFFiNE page mode 借鉴）。
///
/// 全屏播放 NoteDocument 页面——支持翻页/退出。
class SlidePresenter extends StatefulWidget {
  const SlidePresenter({
    super.key,
    required this.slides,
    this.initialSlide = 0,
    this.onExit,
  });

  /// 幻灯片列表。
  final List<SlidePage> slides;

  /// 初始幻灯片索引。
  final int initialSlide;

  /// 退出回调。
  final VoidCallback? onExit;

  /// 从 NoteDocument 创建幻灯片（按标题分页）。
  static List<SlidePage> fromDocument(NoteDocument doc) {
    final slides = <SlidePage>[];
    var currentTitle = doc.title.isNotEmpty ? doc.title : '幻灯片 1';
    var currentParagraphs = <NoteParagraph>[];
    var slideIndex = 1;

    for (final p in doc.paragraphs) {
      if (p.isHeading && currentParagraphs.isNotEmpty) {
        // 遇到标题且已有内容→分页
        slides.add(SlidePage(
          title: currentTitle,
          paragraphs: List.from(currentParagraphs),
        ));
        currentParagraphs = [];
        slideIndex++;
        currentTitle = p.content.isNotEmpty ? p.content : '幻灯片 $slideIndex';
      }
      currentParagraphs.add(p);
    }

    // 最后一页
    if (currentParagraphs.isNotEmpty) {
      slides.add(SlidePage(
        title: currentTitle,
        paragraphs: currentParagraphs,
      ));
    }

    // 若没有分页（无标题），整个文档作为一页
    if (slides.isEmpty) {
      slides.add(SlidePage(
        title: currentTitle,
        paragraphs: doc.paragraphs,
      ));
    }

    return slides;
  }

  /// 显示幻灯片（静态方法——方便调用）。
  static Future<void> show(
    BuildContext context, {
    required NoteDocument document,
    int initialSlide = 0,
  }) {
    final slides = fromDocument(document);
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        pageBuilder: (_, _, _) => SlidePresenter(
          slides: slides,
          initialSlide: initialSlide,
          onExit: () => Navigator.of(context).pop(),
        ),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<SlidePresenter> createState() => _SlidePresenterState();
}

class _SlidePresenterState extends State<SlidePresenter> {
  late PageController _pageController;
  late int _currentSlide;

  @override
  void initState() {
    super.initState();
    _currentSlide = widget.initialSlide;
    _pageController = PageController(initialPage: widget.initialSlide);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _previousSlide() {
    if (_currentSlide > 0) {
      _pageController.previousPage(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _nextSlide() {
    if (_currentSlide < widget.slides.length - 1) {
      _pageController.nextPage(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _exit() {
    if (widget.onExit != null) {
      widget.onExit!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black87,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;

          // Esc：退出
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _exit();
            return KeyEventResult.handled;
          }

          // 左箭头：上一页
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _previousSlide();
            return KeyEventResult.handled;
          }

          // 右箭头/空格：下一页
          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.space) {
            _nextSlide();
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTapUp: (details) {
            // 点击左半屏：上一页，右半屏：下一页
            final width = MediaQuery.of(context).size.width;
            if (details.globalPosition.dx < width / 2) {
              _previousSlide();
            } else {
              _nextSlide();
            }
          },
          child: Stack(
            children: [
              // 幻灯片内容
              PageView.builder(
                controller: _pageController,
                itemCount: widget.slides.length,
                onPageChanged: (index) {
                  setState(() => _currentSlide = index);
                },
                itemBuilder: (context, index) {
                  final slide = widget.slides[index];
                  return _buildSlidePage(context, slide);
                },
              ),

              // 页码指示器
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_currentSlide + 1} / ${widget.slides.length}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),

              // 退出按钮
              Positioned(
                top: 40,
                right: 20,
                child: GestureDetector(
                  onTap: _exit,
                  child: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close, color: Colors.white, size: 24),
                  ),
                ),
              ),

              // 导航箭头（左侧）
              if (_currentSlide > 0)
                Positioned(
                  left: 20,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _previousSlide,
                      child: Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.chevron_left,
                            color: Colors.white, size: 32),
                      ),
                    ),
                  ),
                ),

              // 导航箭头（右侧）
              if (_currentSlide < widget.slides.length - 1)
                Positioned(
                  right: 20,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _nextSlide,
                      child: Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.chevron_right,
                            color: Colors.white, size: 32),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlidePage(BuildContext context, SlidePage slide) {
    final theme = Theme.of(context);

    return Container(
      margin: EdgeInsets.all(60),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 幻灯片标题
              if (slide.title.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(bottom: 24),
                  child: Text(
                    slide.title,
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

              // 幻灯片内容（段落）
              Expanded(
                child: ListView.builder(
                  itemCount: slide.paragraphs.length,
                  itemBuilder: (context, index) {
                    final p = slide.paragraphs[index];
                    return Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        p.content,
                        style: p.isHeading
                            ? theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              )
                            : theme.textTheme.bodyLarge?.copyWith(
                                fontSize: 20,
                                height: 1.6,
                              ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
