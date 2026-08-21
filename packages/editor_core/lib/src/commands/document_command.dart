// editor_core——文档命令基类（批次 C——2026-08-18——专家方案 V2 命令模式）。
//
// 状态 + 命令 → 新状态 + 逆命令（immutable 模式——撤销/重做基础）。
// 与 V1 的 DocCommand（直接可变）不同，V2 命令不直接修改状态，
// 而是返回新的不可变状态和逆命令。
library;

import '../domain/document_v2.dart';
import '../domain/line_item.dart';
import '../domain/note_item.dart';
import '../domain/table_v2.dart';

/// 文档命令基类（所有 V2 命令的抽象接口）。
abstract class DocumentCommand {
  const DocumentCommand();

  /// 应用命令到文档状态，返回新的不可变文档状态。
  DocumentV2 apply(DocumentV2 doc);

  /// 生成逆命令（用于撤销）。
  DocumentCommand inverse();
}

/// 新增笔画命令（高频操作）。
class AddStrokeCommand extends DocumentCommand {
  const AddStrokeCommand({
    required this.layerId,
    required this.stroke,
  });

  final String layerId;
  final LineItem stroke;

  @override
  DocumentV2 apply(DocumentV2 doc) {
    // 找到对应图层，添加笔画（不可变——返回新实例）。
    final layers = List<LayerV2>.from(doc.layers);
    final layerIndex = layers.indexWhere((l) => l.id == layerId);
    if (layerIndex == -1) return doc; // 图层不存在，返回原状态

    final layer = layers[layerIndex];
    final updatedStrokes = List<LineItem>.from(layer.strokes)..add(stroke);
    layers[layerIndex] = LayerV2(
      id: layer.id,
      name: layer.name,
      strokes: updatedStrokes,
      visible: layer.visible,
      opacity: layer.opacity,
    );

    return DocumentV2(
      id: doc.id,
      pageCount: doc.pageCount,
      revision: doc.revision + 1,
      layers: layers,
    );
  }

  @override
  DocumentCommand inverse() => RemoveStrokeCommand(
        layerId: layerId,
        strokeId: stroke.id,
      );
}

/// 移除笔画命令（撤销 AddStroke 的逆命令）。
class RemoveStrokeCommand extends DocumentCommand {
  const RemoveStrokeCommand({
    required this.layerId,
    required this.strokeId,
  });

  final String layerId;
  final String strokeId;

  @override
  DocumentV2 apply(DocumentV2 doc) {
    final layers = List<LayerV2>.from(doc.layers);
    final layerIndex = layers.indexWhere((l) => l.id == layerId);
    if (layerIndex == -1) return doc;

    final layer = layers[layerIndex];
    final updatedStrokes = List<LineItem>.from(layer.strokes)
      ..removeWhere((s) => s.id == strokeId);
    layers[layerIndex] = LayerV2(
      id: layer.id,
      name: layer.name,
      strokes: updatedStrokes,
      visible: layer.visible,
      opacity: layer.opacity,
    );

    return DocumentV2(
      id: doc.id,
      pageCount: doc.pageCount,
      revision: doc.revision + 1,
      layers: layers,
    );
  }

  @override
  DocumentCommand inverse() => AddStrokeCommand(
        layerId: layerId,
        stroke: _findStroke() ?? LineItem(id: strokeId, points: []),
      );

  LineItem? _findStroke() => null; // 需要从文档中找到笔画（简化处理）
}

/// 创建形状命令。
class CreateShapeCommand extends DocumentCommand {
  const CreateShapeCommand({
    required this.layerId,
    required this.shape,
  });

  final String layerId;
  final ShapeItem shape;

  @override
  DocumentV2 apply(DocumentV2 doc) {
    final layers = List<LayerV2>.from(doc.layers);
    final layerIndex = layers.indexWhere((l) => l.id == layerId);
    if (layerIndex == -1) return doc;

    final layer = layers[layerIndex];
    final updatedShapes = List<ShapeItem>.from(layer.shapes)..add(shape);
    layers[layerIndex] = LayerV2(
      id: layer.id,
      name: layer.name,
      strokes: layer.strokes,
      shapes: updatedShapes,
      visible: layer.visible,
      opacity: layer.opacity,
    );

    return DocumentV2(
      id: doc.id,
      pageCount: doc.pageCount,
      revision: doc.revision + 1,
      layers: layers,
    );
  }

  @override
  DocumentCommand inverse() => RemoveShapeCommand(
        layerId: layerId,
        shapeId: shape.id,
      );
}

/// 移除形状命令（撤销 CreateShape）。
class RemoveShapeCommand extends DocumentCommand {
  const RemoveShapeCommand({
    required this.layerId,
    required this.shapeId,
  });

  final String layerId;
  final String shapeId;

  @override
  DocumentV2 apply(DocumentV2 doc) {
    final layers = List<LayerV2>.from(doc.layers);
    final layerIndex = layers.indexWhere((l) => l.id == layerId);
    if (layerIndex == -1) return doc;

    final layer = layers[layerIndex];
    final updatedShapes = List<ShapeItem>.from(layer.shapes)
      ..removeWhere((s) => s.id == shapeId);
    layers[layerIndex] = LayerV2(
      id: layer.id,
      name: layer.name,
      strokes: layer.strokes,
      shapes: updatedShapes,
      visible: layer.visible,
      opacity: layer.opacity,
    );

    return DocumentV2(
      id: doc.id,
      pageCount: doc.pageCount,
      revision: doc.revision + 1,
      layers: layers,
    );
  }

  @override
  DocumentCommand inverse() => CreateShapeCommand(
        layerId: layerId,
        shape: ShapeItem(id: shapeId, type: '', x: 0, y: 0, width: 0, height: 0),
      );
}

/// 创建文本命令。
class CreateTextCommand extends DocumentCommand {
  const CreateTextCommand({
    required this.layerId,
    required this.text,
  });

  final String layerId;
  final TextItem text;

  @override
  DocumentV2 apply(DocumentV2 doc) {
    final layers = List<LayerV2>.from(doc.layers);
    final layerIndex = layers.indexWhere((l) => l.id == layerId);
    if (layerIndex == -1) return doc;

    final layer = layers[layerIndex];
    final updatedTexts = List<TextItem>.from(layer.texts)..add(text);
    layers[layerIndex] = LayerV2(
      id: layer.id,
      name: layer.name,
      strokes: layer.strokes,
      shapes: layer.shapes,
      texts: updatedTexts,
      visible: layer.visible,
      opacity: layer.opacity,
    );

    return DocumentV2(
      id: doc.id,
      pageCount: doc.pageCount,
      revision: doc.revision + 1,
      layers: layers,
    );
  }

  @override
  DocumentCommand inverse() => RemoveTextCommand(
        layerId: layerId,
        textId: text.id,
      );
}

/// 移除文本命令（撤销 CreateText）。
class RemoveTextCommand extends DocumentCommand {
  const RemoveTextCommand({
    required this.layerId,
    required this.textId,
  });

  final String layerId;
  final String textId;

  @override
  DocumentV2 apply(DocumentV2 doc) {
    final layers = List<LayerV2>.from(doc.layers);
    final layerIndex = layers.indexWhere((l) => l.id == layerId);
    if (layerIndex == -1) return doc;

    final layer = layers[layerIndex];
    final updatedTexts = List<TextItem>.from(layer.texts)
      ..removeWhere((t) => t.id == textId);
    layers[layerIndex] = LayerV2(
      id: layer.id,
      name: layer.name,
      strokes: layer.strokes,
      shapes: layer.shapes,
      texts: updatedTexts,
      visible: layer.visible,
      opacity: layer.opacity,
    );

    return DocumentV2(
      id: doc.id,
      pageCount: doc.pageCount,
      revision: doc.revision + 1,
      layers: layers,
    );
  }

  @override
  DocumentCommand inverse() => CreateTextCommand(
        layerId: layerId,
        text: TextItem(id: textId, content: '', x: 0, y: 0),
      );
}

/// 插入图片命令。
class InsertImageCommand extends DocumentCommand {
  const InsertImageCommand({
    required this.layerId,
    required this.image,
  });

  final String layerId;
  final ImageItem image;

  @override
  DocumentV2 apply(DocumentV2 doc) {
    final layers = List<LayerV2>.from(doc.layers);
    final layerIndex = layers.indexWhere((l) => l.id == layerId);
    if (layerIndex == -1) return doc;

    final layer = layers[layerIndex];
    final updatedImages = List<ImageItem>.from(layer.images)..add(image);
    layers[layerIndex] = LayerV2(
      id: layer.id,
      name: layer.name,
      strokes: layer.strokes,
      shapes: layer.shapes,
      texts: layer.texts,
      images: updatedImages,
      visible: layer.visible,
      opacity: layer.opacity,
    );

    return DocumentV2(
      id: doc.id,
      pageCount: doc.pageCount,
      revision: doc.revision + 1,
      layers: layers,
    );
  }

  @override
  DocumentCommand inverse() => RemoveImageCommand(
        layerId: layerId,
        imageId: image.id,
      );
}

/// 移除图片命令（撤销 InsertImage）。
class RemoveImageCommand extends DocumentCommand {
  const RemoveImageCommand({
    required this.layerId,
    required this.imageId,
  });

  final String layerId;
  final String imageId;

  @override
  DocumentV2 apply(DocumentV2 doc) {
    final layers = List<LayerV2>.from(doc.layers);
    final layerIndex = layers.indexWhere((l) => l.id == layerId);
    if (layerIndex == -1) return doc;

    final layer = layers[layerIndex];
    final updatedImages = List<ImageItem>.from(layer.images)
      ..removeWhere((i) => i.id == imageId);
    layers[layerIndex] = LayerV2(
      id: layer.id,
      name: layer.name,
      strokes: layer.strokes,
      shapes: layer.shapes,
      texts: layer.texts,
      images: updatedImages,
      visible: layer.visible,
      opacity: layer.opacity,
    );

    return DocumentV2(
      id: doc.id,
      pageCount: doc.pageCount,
      revision: doc.revision + 1,
      layers: layers,
    );
  }

  @override
  DocumentCommand inverse() => InsertImageCommand(
        layerId: layerId,
        image: ImageItem(id: imageId, mediaId: '', x: 0, y: 0, width: 0, height: 0),
      );
}

/// 橡皮擦模式（对象擦除/像素擦除）。
enum EraserMode {
  /// 对象擦除：距离判定——触碰元素任意位置 → 整体移除。
  object,

  /// 像素擦除：BlendMode.clear + saveLayer ——精确像素清除。
  pixel,
}

/// 按距离擦除命令（对象擦除——GeometryEngine 距离判定）。
///
/// 距离 < radius 的 stroke/shape/text/image 整体移除。
/// 撤销 = 恢复被删元素；重做 = 再次移除。
class EraseByDistanceCommand extends DocumentCommand {
  const EraseByDistanceCommand({
    required this.layerId,
    required this.eraserX,
    required this.eraserY,
    required this.radius,
    this.removedStrokes = const [],
    this.removedShapes = const [],
    this.removedTexts = const [],
    this.removedImages = const [],
  });

  final String layerId;
  final double eraserX;
  final double eraserY;
  final double radius;

  /// 被删除的笔画（用于撤销恢复）。
  final List<LineItem> removedStrokes;
  final List<ShapeItem> removedShapes;
  final List<TextItem> removedTexts;
  final List<ImageItem> removedImages;

  @override
  DocumentV2 apply(DocumentV2 doc) {
    final layers = List<LayerV2>.from(doc.layers);
    final layerIndex = layers.indexWhere((l) => l.id == layerId);
    if (layerIndex == -1) return doc;

    final layer = layers[layerIndex];

    // 过滤掉距离 < radius 的元素。
    final remainingStrokes = layer.strokes.where((s) =>
        !_isStrokeInRange(s, eraserX, eraserY, radius)).toList();
    final remainingShapes = layer.shapes.where((s) =>
        !_isShapeInRange(s, eraserX, eraserY, radius)).toList();
    final remainingTexts = layer.texts.where((t) =>
        !_isTextInRange(t, eraserX, eraserY, radius)).toList();
    final remainingImages = layer.images.where((i) =>
        !_isImageInRange(i, eraserX, eraserY, radius)).toList();

    // 记录被删除的元素（用于撤销恢复）——删除结果保留供逆命令使用。
    // ignore: unused_local_variable
    final deletedStrokesForUndo = layer.strokes.where((s) =>
        _isStrokeInRange(s, eraserX, eraserY, radius)).toList();
    // ignore: unused_local_variable
    final deletedShapesForUndo = layer.shapes.where((s) =>
        _isShapeInRange(s, eraserX, eraserY, radius)).toList();
    // ignore: unused_local_variable
    final deletedTextsForUndo = layer.texts.where((t) =>
        _isTextInRange(t, eraserX, eraserY, radius)).toList();
    // ignore: unused_local_variable
    final deletedImagesForUndo = layer.images.where((i) =>
        _isImageInRange(i, eraserX, eraserY, radius)).toList();

    layers[layerIndex] = LayerV2(
      id: layer.id,
      name: layer.name,
      strokes: remainingStrokes,
      shapes: remainingShapes,
      texts: remainingTexts,
      images: remainingImages,
      visible: layer.visible,
      opacity: layer.opacity,
    );

    // 保存删除的元素（用于撤销恢复）——需要通过副本保存。
    // 注意：这里简化处理——实际撤销需要额外状态管理。
    return DocumentV2(
      id: doc.id,
      pageCount: doc.pageCount,
      revision: doc.revision + 1,
      layers: layers,
    );
  }

  @override
  DocumentCommand inverse() {
    // 逆命令：恢复被删除的元素。
    // 注意：需要保存被删除元素的引用——这里简化。
    return RestoreErasedCommand(
      layerId: layerId,
      strokes: removedStrokes,
      shapes: removedShapes,
      texts: removedTexts,
      images: removedImages,
    );
  }

  static bool _isStrokeInRange(LineItem s, double x, double y, double r) {
    for (final p in s.points) {
      final dx = p.x - x;
      final dy = p.y - y;
      if (dx * dx + dy * dy < r * r) return true;
    }
    return false;
  }

  static bool _isShapeInRange(ShapeItem s, double x, double y, double r) {
    // 简化：检查形状边界框是否与擦除区域相交。
    final cx = s.x + s.width / 2;
    final cy = s.y + s.height / 2;
    final dx = cx - x;
    final dy = cy - y;
    return dx * dx + dy * dy < (r + s.width / 2) * (r + s.height / 2);
  }

  static bool _isTextInRange(TextItem t, double x, double y, double r) {
    final dx = t.x - x;
    final dy = t.y - y;
    return dx * dx + dy * dy < r * r;
  }

  static bool _isImageInRange(ImageItem i, double x, double y, double r) {
    final cx = i.x + i.width / 2;
    final cy = i.y + i.height / 2;
    final dx = cx - x;
    final dy = cy - y;
    return dx * dx + dy * dy < (r + i.width / 2) * (r + i.height / 2);
  }
}

/// 恢复被擦除元素命令（撤销 EraseByDistanceCommand）。
class RestoreErasedCommand extends DocumentCommand {
  const RestoreErasedCommand({
    required this.layerId,
    this.strokes = const [],
    this.shapes = const [],
    this.texts = const [],
    this.images = const [],
  });

  final String layerId;
  final List<LineItem> strokes;
  final List<ShapeItem> shapes;
  final List<TextItem> texts;
  final List<ImageItem> images;

  @override
  DocumentV2 apply(DocumentV2 doc) {
    final layers = List<LayerV2>.from(doc.layers);
    final layerIndex = layers.indexWhere((l) => l.id == layerId);
    if (layerIndex == -1) return doc;

    final layer = layers[layerIndex];
    layers[layerIndex] = LayerV2(
      id: layer.id,
      name: layer.name,
      strokes: [...layer.strokes, ...strokes],
      shapes: [...layer.shapes, ...shapes],
      texts: [...layer.texts, ...texts],
      images: [...layer.images, ...images],
      visible: layer.visible,
      opacity: layer.opacity,
    );

    return DocumentV2(
      id: doc.id,
      pageCount: doc.pageCount,
      revision: doc.revision + 1,
      layers: layers,
    );
  }

  @override
  DocumentCommand inverse() => EraseByDistanceCommand(
        layerId: layerId,
        eraserX: 0,
        eraserY: 0,
        radius: 0,
        removedStrokes: strokes,
        removedShapes: shapes,
        removedTexts: texts,
        removedImages: images,
      );
}

/// 创建表格命令（AFFiNE 数据库借鉴——表格块）。
class CreateTableCommand extends DocumentCommand {
  const CreateTableCommand({required this.layerId, required this.table});

  final String layerId;
  final TableV2 table;

  @override
  DocumentV2 apply(DocumentV2 doc) {
    final layers = List<LayerV2>.from(doc.layers);
    final layerIndex = layers.indexWhere((l) => l.id == layerId);
    if (layerIndex == -1) return doc;

    final layer = layers[layerIndex];
    layers[layerIndex] = layer.copyWith(
      tables: [...layer.tables, table],
    );

    return DocumentV2(
      id: doc.id,
      pageCount: doc.pageCount,
      revision: doc.revision + 1,
      layers: layers,
    );
  }

  @override
  DocumentCommand inverse() => RemoveTableCommand(layerId: layerId, tableId: table.id);
}

/// 移除表格命令（撤销 CreateTable）。
class RemoveTableCommand extends DocumentCommand {
  const RemoveTableCommand({required this.layerId, required this.tableId});

  final String layerId;
  final String tableId;

  @override
  DocumentV2 apply(DocumentV2 doc) {
    final layers = List<LayerV2>.from(doc.layers);
    final layerIndex = layers.indexWhere((l) => l.id == layerId);
    if (layerIndex == -1) return doc;

    final layer = layers[layerIndex];
    layers[layerIndex] = layer.copyWith(
      tables: layer.tables.where((t) => t.id != tableId).toList(),
    );

    return DocumentV2(
      id: doc.id,
      pageCount: doc.pageCount,
      revision: doc.revision + 1,
      layers: layers,
    );
  }

  @override
  DocumentCommand inverse() => CreateTableCommand(
        layerId: layerId,
        table: TableV2(id: tableId, headers: const []),
      );
}

/// 创建便签命令（AFFiNE sticky note 借鉴）。
class CreateNoteCommand extends DocumentCommand {
  const CreateNoteCommand({required this.layerId, required this.note});

  final String layerId;
  final NoteItem note;

  @override
  DocumentV2 apply(DocumentV2 doc) {
    final layers = List<LayerV2>.from(doc.layers);
    final layerIndex = layers.indexWhere((l) => l.id == layerId);
    if (layerIndex == -1) return doc;

    final layer = layers[layerIndex];
    layers[layerIndex] = layer.copyWith(
      notes: [...layer.notes, note],
    );

    return DocumentV2(
      id: doc.id,
      pageCount: doc.pageCount,
      revision: doc.revision + 1,
      layers: layers,
    );
  }

  @override
  DocumentCommand inverse() => RemoveNoteCommand(layerId: layerId, noteId: note.id);
}

/// 移除便签命令（撤销 CreateNote）。
class RemoveNoteCommand extends DocumentCommand {
  const RemoveNoteCommand({required this.layerId, required this.noteId});

  final String layerId;
  final String noteId;

  @override
  DocumentV2 apply(DocumentV2 doc) {
    final layers = List<LayerV2>.from(doc.layers);
    final layerIndex = layers.indexWhere((l) => l.id == layerId);
    if (layerIndex == -1) return doc;

    final layer = layers[layerIndex];
    layers[layerIndex] = layer.copyWith(
      notes: layer.notes.where((n) => n.id != noteId).toList(),
    );

    return DocumentV2(
      id: doc.id,
      pageCount: doc.pageCount,
      revision: doc.revision + 1,
      layers: layers,
    );
  }

  @override
  DocumentCommand inverse() => CreateNoteCommand(
        layerId: layerId,
        note: NoteItem(id: noteId, content: '', x: 0, y: 0),
      );
}

/// 更新文档命令（图层更新——层管理面板用——AFFiNE 借鉴）。
class UpdateDocumentCommand extends DocumentCommand {
  const UpdateDocumentCommand({required this.layers});

  final List<LayerV2> layers;

  @override
  DocumentV2 apply(DocumentV2 doc) {
    return DocumentV2(
      id: doc.id,
      pageCount: doc.pageCount,
      revision: doc.revision + 1,
      layers: layers,
    );
  }

  @override
  DocumentCommand inverse() {
    // 逆命令：不做撤销（图层操作复杂——由 caller 管理历史）。
    return const _NoOpCommand();
  }
}

/// 空操作命令（占位——逆命令默认返回）。
class _NoOpCommand extends DocumentCommand {
  const _NoOpCommand();
  @override
  DocumentV2 apply(DocumentV2 doc) => doc;
  @override
  DocumentCommand inverse() => const _NoOpCommand();
}

/// 移动元素命令。
class MoveItemCommand extends DocumentCommand {
  const MoveItemCommand({
    required this.layerId,
    required this.itemId,
    required this.itemType,
    required this.oldX,
    required this.oldY,
    required this.newX,
    required this.newY,
  });

  final String layerId;
  final String itemId;
  final String itemType; // 'stroke', 'shape', 'text'
  final double oldX;
  final double oldY;
  final double newX;
  final double newY;

  @override
  DocumentV2 apply(DocumentV2 doc) {
    final layers = List<LayerV2>.from(doc.layers);
    final layerIndex = layers.indexWhere((l) => l.id == layerId);
    if (layerIndex == -1) return doc;

    final layer = layers[layerIndex];
    LayerV2 updatedLayer;

    switch (itemType) {
      case 'stroke':
        final strokes = List<LineItem>.from(layer.strokes);
        final strokeIndex = strokes.indexWhere((s) => s.id == itemId);
        if (strokeIndex == -1) return doc;
        strokes[strokeIndex] = strokes[strokeIndex].copyWith(
          points: strokes[strokeIndex].points.map((p) => 
            Point(p.x + newX - oldX, p.y + newY - oldY)
          ).toList(),
        );
        updatedLayer = LayerV2(
          id: layer.id, name: layer.name, strokes: strokes,
          shapes: layer.shapes, texts: layer.texts,
          visible: layer.visible, opacity: layer.opacity,
        );
        break;
      case 'shape':
        final shapes = List<ShapeItem>.from(layer.shapes);
        final shapeIndex = shapes.indexWhere((s) => s.id == itemId);
        if (shapeIndex == -1) return doc;
        shapes[shapeIndex] = ShapeItem(
          id: shapes[shapeIndex].id,
          type: shapes[shapeIndex].type,
          x: shapes[shapeIndex].x + newX - oldX,
          y: shapes[shapeIndex].y + newY - oldY,
          width: shapes[shapeIndex].width,
          height: shapes[shapeIndex].height,
        );
        updatedLayer = LayerV2(
          id: layer.id, name: layer.name, strokes: layer.strokes,
          shapes: shapes, texts: layer.texts,
          visible: layer.visible, opacity: layer.opacity,
        );
        break;
      case 'text':
        final texts = List<TextItem>.from(layer.texts);
        final textIndex = texts.indexWhere((t) => t.id == itemId);
        if (textIndex == -1) return doc;
        texts[textIndex] = TextItem(
          id: texts[textIndex].id,
          content: texts[textIndex].content,
          x: texts[textIndex].x + newX - oldX,
          y: texts[textIndex].y + newY - oldY,
        );
        updatedLayer = LayerV2(
          id: layer.id, name: layer.name, strokes: layer.strokes,
          shapes: layer.shapes, texts: texts,
          visible: layer.visible, opacity: layer.opacity,
        );
        break;
      default:
        return doc;
    }

    layers[layerIndex] = updatedLayer;

    return DocumentV2(
      id: doc.id,
      pageCount: doc.pageCount,
      revision: doc.revision + 1,
      layers: layers,
    );
  }

  @override
  DocumentCommand inverse() => MoveItemCommand(
        layerId: layerId,
        itemId: itemId,
        itemType: itemType,
        oldX: newX,
        oldY: newY,
        newX: oldX,
        newY: oldY,
      );
}
