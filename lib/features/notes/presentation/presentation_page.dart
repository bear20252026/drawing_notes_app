import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/text_scale_helper.dart';
import 'package:flutter/services.dart';

import 'package:drawing_notes_app/features/notes/domain/notebook.dart';

/// 幻灯片演示模式（对齐 Excalidraw presentation）。
///
/// 全屏黑色背景，按元素列表逐个居中展示（文字/图片/形状），
/// ←/→ 切换、Esc 或点击退出。适用于汇报/演示场景。
class PresentationPage extends StatefulWidget {
  const PresentationPage({
    super.key,
    required this.textItems,
    required this.imageItems,
    required this.shapes,
  });

  final List<PageTextItem> textItems;
  final List<PageImageItem> imageItems;
  final List<PageShapeItem> shapes;

  @override
  State<PresentationPage> createState() => _PresentationPageState();
}

class _PresentationPageState extends State<PresentationPage> {
  int _index = 0;

  /// 全部元素（按加入顺序），空元素跳过。
  List<Widget> get _elements {
    final items = <Widget>[];
    for (final t in widget.textItems) {
      items.add(
        Text(
          t.text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: TextScaleHelper.scaled(context, 28),
            color: Colors.white,
            fontWeight: t.bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      );
    }
    for (final i in widget.imageItems) {
      items.add(
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: i.filePath.isNotEmpty
              ? Image.file(File(i.filePath), fit: BoxFit.contain)
              : const ColoredBox(color: Colors.grey),
        ),
      );
    }
    for (final s in widget.shapes) {
      items.add(
        Icon(
          switch (s.shapeType) {
            ShapeType.rect => Icons.crop_square,
            ShapeType.ellipse => Icons.circle_outlined,
            ShapeType.diamond => Icons.diamond_outlined,
            ShapeType.arrow => Icons.arrow_forward,
            ShapeType.line => Icons.remove,
          },
          size: 120,
          color: Colors.white,
        ),
      );
    }
    return items.whereType<Widget>().toList();
  }

  void _next() {
    if (_index < _elements.length - 1) {
      setState(() => _index++);
    }
  }

  void _prev() {
    if (_index > 0) {
      setState(() => _index--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final elements = _elements;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
                event.logicalKey == LogicalKeyboardKey.space) {
              _next();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _prev();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: _next,
          onLongPress: () => Navigator.of(context).pop(),
          child: Stack(
            children: [
              // 当前元素居中展示。
              Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: KeyedSubtree(
                    key: ValueKey(_index),
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: elements.isEmpty
                          ? const Text(
                              '没有可演示的内容',
                              style: TextStyle(color: Colors.white54),
                            )
                          : elements[_index],
                    ),
                  ),
                ),
              ),
              // 底部进度指示。
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Center(
                  child: Text(
                    '${_index + 1} / ${elements.length} · 点击或 → 下一页，Esc 退出',
                    style: TextStyle(color: Colors.white38, fontSize: TextScaleHelper.scaled(context, 13)),
                  ),
                ),
              ),
              // 左上角退出按钮。
              Positioned(
                left: 12,
                top: 12,
                child: IconButton(
                  tooltip: '退出演示',
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
