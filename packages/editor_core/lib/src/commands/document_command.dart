// editor_core——文档命令基类（批次 C——2026-08-18——专家方案 V2 命令模式）。
//
// 状态 + 命令 → 新状态 + 逆命令（immutable 模式——撤销/重做基础）。
// 与 V1 的 DocCommand（直接可变）不同，V2 命令不直接修改状态，
// 而是返回新的不可变状态和逆命令。
library;

import '../domain/document_v2.dart';
import '../domain/line_item.dart';

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
