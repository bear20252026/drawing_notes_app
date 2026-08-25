import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:material_ui/material_ui.dart' hide Dialog, Colors, TextButton, Theme;

import '../../../core/ui/widgets/ios_dialog.dart';
import 'editor_components.dart';
import '../domain/shape_item.dart';
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
      fillColor: 0x663A6EA5,
    ),
    PageShapeItem(
      id: 'lib_rect_fill',
      shapeType: ShapeType.rect,
      x: 0,
      y: 0,
      width: 180,
      height: 100,
      fillColor: 0x883A6EA5,
    ),
    PageShapeItem(
      id: 'lib_ellipse',
      shapeType: ShapeType.ellipse,
      x: 0,
      y: 0,
      width: 160,
      height: 110,
    ),
    PageShapeItem(
      id: 'lib_diamond',
      shapeType: ShapeType.diamond,
      x: 0,
      y: 0,
      width: 140,
      height: 110,
    ),
    PageShapeItem(
      id: 'lib_arrow',
      shapeType: ShapeType.arrow,
      x: 0,
      y: 0,
      width: 200,
      height: 60,
      strokeWidth: 4,
    ),
    PageShapeItem(
      id: 'lib_line_dash',
      shapeType: ShapeType.line,
      x: 0,
      y: 0,
      width: 200,
      height: 4,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final textColor = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF1D1D1F);
    final subTextColor = isDark ? const Color(0xFFEBEBF5) : const Color(0xFF6E6E73);
    final dividerColor = isDark ? const Color(0xFF38383A) : const Color(0xFFE0E0E0);
    final results = widget.library.search(_query);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 460,
        height: 420,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                '形状库（图书馆）',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    CupertinoTextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v),
                      placeholder: '检索形状（如：矩形/椭圆/箭头）…',
                      prefix: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(CupertinoIcons.search, size: 18, color: Color(0xFF8E8E93)),
                      ),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF3A3A3C) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: dividerColor),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: results.isEmpty
                          ? Center(
                              child: Text(
                                '没有匹配的形状',
                                style: TextStyle(color: subTextColor),
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
                                return GestureDetector(
                                  onTap: () {
                                    widget.onInsert(s);
                                    Navigator.of(context).pop();
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF3A3A3C)
                                          : const Color(0xFFE5E5EA),
                                      borderRadius: BorderRadius.circular(8),
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
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: subTextColor,
                                          ),
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
            ),
            // Divider
            Container(height: 0.5, color: dividerColor),
            // Actions
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0066CC),
                  shape: const RoundedRectangleBorder(),
                  textStyle: const TextStyle(fontSize: 17),
                ),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
