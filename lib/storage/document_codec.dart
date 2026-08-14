import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

import '../models/document.dart';
import '../models/document_image_item.dart';
import '../models/layer.dart';
import '../models/shape_item.dart';
import '../models/stroke.dart';

/// 文档编解码器：DrawingDocument <-> JSON 字符串（工程文件格式）。
///
/// 说明：工程文件使用 JSON 存储全部图层与笔画（矢量数据），
/// 不依赖第三方格式（如 PSD，按开发计划 Phase 1-7 不实现 PSD 导出）。
///
/// 文件结构（v1）：
/// {
///   "version": 1,
///   "document": { "id","title","width","height","createdAt","updatedAt",
///                 "layers": [ {id,name,visible,opacity,strokes:[...]} ] }
/// }
class DocumentCodec {
  const DocumentCodec();

  static const int _version = 2;

  /// 序列化为 JSON 字节。
  Uint8List encode(DrawingDocument doc) {
    final map = <String, dynamic>{
      'version': _version,
      'document': {
        'id': doc.id,
        'title': doc.title,
        'width': doc.width,
        'height': doc.height,
        'infinite': doc.infinite,
        'paperType': doc.paperType.name,
        'createdAt': doc.createdAt.toIso8601String(),
        'updatedAt': doc.updatedAt.toIso8601String(),
        'layers': doc.layers.map((l) => l.toJson()).toList(),
        'shapes': doc.shapes.map((shape) => shape.toJson()).toList(),
        'imageItems': doc.imageItems.map((item) => item.toJson()).toList(),
      },
    };
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(map)),
    );
  }

  /// 从 JSON 字节反序列化并执行防御性恢复。
  ///
  /// 根结构和文档 ID 损坏时抛出 [FormatException]；图层、笔画、形状和图片
  /// 属于可隔离对象，单个条目损坏不会阻止其余可靠内容打开。恢复阶段还会移除
  /// 重复 ID、危险几何和指向已不存在目标的箭头绑定，避免外部/旧版文件使渲染
  /// 或后续编辑陷入异常状态。
  DrawingDocument decode(Uint8List bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw FormatException('文档 JSON 格式无效');
    }
    if (decoded is! Map) {
      throw FormatException('文档根节点必须是对象');
    }
    final documentValue = decoded['document'];
    if (documentValue is! Map) {
      throw FormatException('文档缺少 document 对象');
    }
    final document = Map<String, dynamic>.from(documentValue);
    final id = document['id'];
    if (id is! String || !_validDocumentId.hasMatch(id)) {
      throw FormatException('文档 ID 无效');
    }

    return DrawingDocument(
      id: id,
      title: document['title'] is String ? document['title'] as String : '未命名',
      width: _restoreCanvasDimension(document['width'], 2048),
      height: _restoreCanvasDimension(document['height'], 1536),
      infinite: document['infinite'] == true,
      paperType: PaperType.values.firstWhere(
        (type) => type.name == document['paperType'],
        orElse: () => PaperType.blank,
      ),
      layers: _restoreLayers(document['layers']),
      shapes: _restoreShapes(document['shapes']),
      imageItems: _restoreImageItems(document['imageItems']),
      createdAt:
          DateTime.tryParse(document['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(document['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static final RegExp _validDocumentId = RegExp(r'^[A-Za-z0-9_-]+$');
  static const double _maxCoordinate = 1000000;
  static const double _maxShapeExtent = 8192;
  static const double _maxStrokeWidth = 512;

  static int _restoreCanvasDimension(Object? value, int fallback) {
    if (value is! num || !value.toDouble().isFinite) return fallback;
    return value.toInt().clamp(16, 32768).toInt();
  }

  static List<Layer> _restoreLayers(Object? value) {
    final layers = <Layer>[];
    final ids = <String>{};
    if (value is List) {
      for (final entry in value) {
        if (entry is! Map) continue;
        try {
          final json = Map<String, dynamic>.from(entry);
          final id = json['id'];
          if (id is! String || id.isEmpty || !ids.add(id)) continue;
          final opacity = json['opacity'];
          final safeOpacity = opacity is num && opacity.toDouble().isFinite
              ? opacity.toDouble().clamp(0.0, 1.0).toDouble()
              : 1.0;
          final strokes = _restoreStrokes(json['strokes']);
          layers.add(
            Layer(
              id: id,
              name: json['name'] is String ? json['name'] as String : '图层',
              visible: json['visible'] is bool ? json['visible'] as bool : true,
              opacity: safeOpacity,
              strokes: strokes,
            ),
          );
        } catch (_) {
          // 局部对象损坏时继续恢复其余图层。
        }
      }
    }
    return layers.isEmpty ? [Layer(id: 'layer_1', name: '图层 1')] : layers;
  }

  static List<Stroke> _restoreStrokes(Object? value) {
    final strokes = <Stroke>[];
    if (value is! List) return strokes;
    for (final entry in value) {
      if (entry is! Map) continue;
      try {
        final json = Map<String, dynamic>.from(entry);
        final rawPoints = json['points'];
        final color = json['color'];
        final width = json['width'];
        if (rawPoints is! List || color is! num || width is! num) continue;
        final safeWidth = width.toDouble();
        if (!safeWidth.isFinite ||
            safeWidth <= 0 ||
            safeWidth > _maxStrokeWidth) {
          continue;
        }
        final points = <StrokePoint>[];
        for (final pointValue in rawPoints) {
          if (pointValue is! Map) continue;
          final point = StrokePoint.fromJson(
            Map<String, dynamic>.from(pointValue),
          );
          if (!_isSafeCoordinate(point.x) ||
              !_isSafeCoordinate(point.y) ||
              !point.pressure.isFinite) {
            continue;
          }
          points.add(
            StrokePoint(
              point.x,
              point.y,
              point.pressure.clamp(0.0, 1.0).toDouble(),
            ),
          );
        }
        if (points.isEmpty) continue;
        final opacity = json['opacity'];
        strokes.add(
          Stroke(
            points: points,
            color: Color(color.toInt()),
            width: safeWidth,
            type: BrushType.values.firstWhere(
              (type) => type.name == json['type'],
              orElse: () => BrushType.pen,
            ),
            opacity: opacity is num && opacity.toDouble().isFinite
                ? opacity.toDouble().clamp(0.0, 1.0).toDouble()
                : 1.0,
          ),
        );
      } catch (_) {
        // 丢弃单条无法安全恢复的笔画。
      }
    }
    return strokes;
  }

  static List<PageShapeItem> _restoreShapes(Object? value) {
    final shapes = <PageShapeItem>[];
    final ids = <String>{};
    if (value is List) {
      for (final entry in value) {
        if (entry is! Map) continue;
        try {
          final shape = PageShapeItem.fromJson(
            Map<String, dynamic>.from(entry),
          );
          if (shape.id.isEmpty ||
              !ids.add(shape.id) ||
              !_isSafeCoordinate(shape.x) ||
              !_isSafeCoordinate(shape.y) ||
              !shape.width.isFinite ||
              !shape.height.isFinite ||
              shape.width <= 0 ||
              shape.height <= 0 ||
              shape.width > _maxShapeExtent ||
              shape.height > _maxShapeExtent ||
              !shape.rotation.isFinite) {
            continue;
          }
          shape.strokeWidth =
              shape.strokeWidth.isFinite &&
                  shape.strokeWidth > 0 &&
                  shape.strokeWidth <= _maxStrokeWidth
              ? shape.strokeWidth
              : 3;
          shapes.add(shape);
        } catch (_) {
          // 丢弃单个无效形状，保留文档中其余对象。
        }
      }
    }

    final bindableIds = shapes
        .where(
          (shape) =>
              shape.shapeType == ShapeType.rect ||
              shape.shapeType == ShapeType.ellipse ||
              shape.shapeType == ShapeType.diamond,
        )
        .map((shape) => shape.id)
        .toSet();
    for (final shape in shapes) {
      if (shape.shapeType != ShapeType.arrow) {
        shape
          ..startBinding = null
          ..endBinding = null;
        continue;
      }
      if (!bindableIds.contains(shape.startBinding?.targetShapeId)) {
        shape.startBinding = null;
      }
      if (!bindableIds.contains(shape.endBinding?.targetShapeId)) {
        shape.endBinding = null;
      }
    }
    return shapes;
  }

  static List<DocumentImageItem> _restoreImageItems(Object? value) {
    final images = <DocumentImageItem>[];
    final ids = <String>{};
    if (value is! List) return images;
    for (final entry in value) {
      if (entry is! Map) continue;
      try {
        final item = DocumentImageItem.fromJson(
          Map<String, dynamic>.from(entry),
        );
        if (item.id.isEmpty ||
            !ids.add(item.id) ||
            item.filePath.isEmpty ||
            !_isSafeCoordinate(item.x) ||
            !_isSafeCoordinate(item.y) ||
            !item.width.isFinite ||
            !item.height.isFinite ||
            item.width <= 0 ||
            item.height <= 0 ||
            item.width > _maxShapeExtent ||
            item.height > _maxShapeExtent) {
          continue;
        }
        images.add(item);
      } catch (_) {
        // 图片文件是否存在由惰性解码层决定；只有模型无效时才隔离对象。
      }
    }
    return images;
  }

  static bool _isSafeCoordinate(double value) =>
      value.isFinite && value.abs() <= _maxCoordinate;
}
