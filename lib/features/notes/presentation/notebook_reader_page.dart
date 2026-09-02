import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:drawing_notes_app/features/notes/domain/notebook.dart';
import 'package:drawing_notes_app/features/notes/rendering/notebook_page_canvas_painter.dart';
import 'package:drawing_notes_app/shared/widgets/encrypted_file_image.dart';

/// 分页画布翻页阅读模式（W2 核心能力）。
///
/// 用户定义的分页画布 = 一本多页画册：上下滑动像翻 PDF 一样切换
/// 第 1 页、第 2 页、第 3 页……本页提供该体验：
/// - 垂直 PageView 逐页整幅展示（FittedBox 保持纸张比例）；
/// - 页码指示器「第 N 页 / 共 M 页」；
/// - 点击页面进入编辑器；
/// - 键盘：↑/↓、PageUp/PageDown、空格翻页，Esc 退出（鼠标滚轮/
///   触屏滑动/键盘三输入通道齐备）。
class NotebookReaderPage extends StatefulWidget {
  const NotebookReaderPage({
    super.key,
    required this.notebook,
    required this.onEditPage,
  });

  final Notebook notebook;

  /// 点击当前页进入编辑器（调用方负责导航）。
  final void Function(NotebookPage page) onEditPage;

  @override
  State<NotebookReaderPage> createState() => _NotebookReaderPageState();
}

class _NotebookReaderPageState extends State<NotebookReaderPage> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int target) {
    if (target < 0 || target >= widget.notebook.pages.length) return;
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.space) {
      _goTo(_index + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp) {
      _goTo(_index - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.notebook.pages;
    return Scaffold(
      backgroundColor: const Color(0xFF15171A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF15171A),
        foregroundColor: Colors.white70,
        title: Text(
          '${widget.notebook.title} · 翻页阅读',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: pages.isEmpty
            ? const Center(
                child: Text(
                  '这个分页画布还没有页面',
                  style: TextStyle(color: Colors.white38),
                ),
              )
            : Stack(
                children: [
                  PageView.builder(
                    controller: _controller,
                    scrollDirection: Axis.vertical,
                    itemCount: pages.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => _ReaderSheet(
                      page: pages[i],
                      onTap: () => widget.onEditPage(pages[i]),
                    ),
                  ),
                  // 页码指示器（底部居中药丸）。
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 20,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '第 ${_index + 1} 页 / 共 ${pages.length} 页',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 单页整幅视图：固定纸张尺寸（保持画布比例）→ FittedBox 适配视口。
///
/// 手写/形状/文字由 [NotebookPageCanvasPainter] 忠实渲染；图片以
/// [EncryptedFileImage] widget 层叠加（解密/占位 fail-closed 复用既有管线）。
class _ReaderSheet extends StatelessWidget {
  const _ReaderSheet({required this.page, required this.onTap});

  final NotebookPage page;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final doc = page.document;
    final width = doc.width.toDouble();
    final height = doc.height.toDouble();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: onTap,
          child: FittedBox(
            key: ValueKey('reader-sheet-${page.id}'),
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: NotebookPageCanvasPainter(page: page),
                    ),
                  ),
                  // 图片内容层（EncryptedFileImage 同一解密管线：文件/VFS/
                  // DNV/DAN/明文五态兼容；fail-closed 失败显示空块，
                  // painter 底层仍有占位框）。
                  for (final image in page.imageItems)
                    if (image.filePath.isNotEmpty)
                      Positioned(
                        left: image.x,
                        top: image.y,
                        width: image.width,
                        height: image.height,
                        child: Image(
                          image: EncryptedFileImage(File(image.filePath)),
                          fit: BoxFit.fill,
                          errorBuilder: (_, _, _) => const SizedBox.expand(),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
