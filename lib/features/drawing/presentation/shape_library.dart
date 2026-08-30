import 'package:flutter/material.dart';

import 'package:drawing_notes_app/features/drawing/presentation/editor_components.dart';
import 'package:drawing_notes_app/core/canvas_model/shape_item.dart';
import 'editor_toolbar.dart' show shapeTypeName;

/// 图书馆/形状库（对齐 Excalidraw libraries）。
///
/// 内置常用形状模板库 + 检索 + 个人收藏（收藏存于内存，会话内有效）。
/// 点击模板即在画布中心插入对应形状。
class ShapeLibrary {
  /// 内置公共形状模板（Excalidraw 常见图形）。
  static final List<PageShapeItem> builtin = [
    PageShapeItem(
      id: 'lib_rect',
      shapeType: ShapeType.rect,
      x: 0,
      y: 0,
      width: 180,
      height: 100,
      color: 0xFF3A6EA5,
      fillColor: 0x663A6EA5,
    ),
    PageShapeItem(
      id: 'lib_rect_fill',
      shapeType: ShapeType.rect,
      x: 0,
      y: 0,
      width: 180,
      height: 100,
      color: 0xFF3A6EA5,
      fillColor: 0x883A6EA5,
    ),
    PageShapeItem(
      id: 'lib_ellipse',
      shapeType: ShapeType.ellipse,
      x: 0,
      y: 0,
      width: 160,
      height: 110,
      color: 0xFF3A6EA5,
    ),
    PageShapeItem(
      id: 'lib_diamond',
      shapeType: ShapeType.diamond,
      x: 0,
      y: 0,
      width: 140,
      height: 110,
      color: 0xFF3A6EA5,
    ),
    PageShapeItem(
      id: 'lib_arrow',
      shapeType: ShapeType.arrow,
      x: 0,
      y: 0,
      width: 200,
      height: 60,
      color: 0xFF3A6EA5,
      strokeWidth: 4,
    ),
    PageShapeItem(
      id: 'lib_line_dash',
      shapeType: ShapeType.line,
      x: 0,
      y: 0,
      width: 200,
      height: 4,
      color: 0xFF3A6EA5,
      dash: true,
    ),
    PageShapeItem(
      id: 'lib_rect_green',
      shapeType: ShapeType.rect,
      x: 0,
      y: 0,
      width: 180,
      height: 100,
      color: 0xFF4CAF50,
      fillColor: 0x664CAF50,
    ),
    PageShapeItem(
      id: 'lib_ellipse_red',
      shapeType: ShapeType.ellipse,
      x: 0,
      y: 0,
      width: 160,
      height: 110,
      color: 0xFFE53935,
      fillColor: 0x66E53935,
    ),
  ];

  /// 个人收藏（用户点击"收藏到库"添加，会话内有效）。
  final List<PageShapeItem> personal = [];

  /// 全部模板（内置 + 个人）。
  List<PageShapeItem> get all => [...builtin, ...personal];

  /// 按名称/类型关键词检索。
  List<PageShapeItem> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where(
          (s) =>
              shapeTypeName(s.shapeType).toLowerCase().contains(q) ||
              s.id.toLowerCase().contains(q),
        )
        .toList();
  }

  /// 收藏一个形状到个人库（深拷贝，避免共享引用）。
  void addToPersonal(PageShapeItem shape) {
    personal.add(PageShapeItem.fromJson(shape.toJson()));
  }
}

/// 图书馆对话框：网格浏览 + 搜索 + 点击插入。
class ShapeLibraryDialog extends StatefulWidget {
  const ShapeLibraryDialog({
    super.key,
    required this.library,
    required this.onInsert,
  });

  final ShapeLibrary library;
  final ValueChanged<PageShapeItem> onInsert;

  @override
  State<ShapeLibraryDialog> createState() => _ShapeLibraryDialogState();
}

class _ShapeLibraryDialogState extends State<ShapeLibraryDialog> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.library.search(_query);
    return AlertDialog(
      title: const Text('形状库（图书馆）'),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: '检索形状（如：矩形/椭圆/箭头）…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: results.isEmpty
                  ? const Center(
                      child: Text(
                        '没有匹配的形状',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 110,
                            childAspectRatio: 1.1,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: results.length,
                      itemBuilder: (context, i) {
                        final s = results[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            widget.onInsert(s);
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            padding: const EdgeInsets.all(6),
                            child: Column(
                              children: [
                                Expanded(
                                  child: CustomPaint(
                                    painter: ShapePainter(
                                      shape: s,
                                      viewScale: 1.0,
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                                Text(
                                  shapeTypeName(s.shapeType),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
