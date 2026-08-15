import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/document_image_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/layer.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';

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

  /// 当前支持的工程文件格式版本。
  ///
  /// 对齐 Saber SBN 的版本管理思路：写入固定 [version]，读取时若遇到
  /// 高于本值的文件（由新版本应用生成）则明确拒绝并提示升级，而不是
  /// 静默忽略未知字段造成数据损坏（政府审计项目严禁静默丢数据）。
  static const int latestVersion = 2;

  static const int _version = latestVersion;

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
    // 入口大小预检（红蓝攻防 D-4 修复 2026-08-15）：拒绝超大文档，
    // 防恶意构造文件耗尽内存（OOM）。
    if (bytes.length > _maxDecodeBytes) {
      throw FormatException('文档过大（超过 100MB 限制），拒绝打开');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw FormatException('文档 JSON 格式无效');
    }
    if (decoded is! Map) {
      throw FormatException('文档根节点必须是对象');
    }
    // 版本只读降级（对齐 Saber SBN）：文件版本高于当前支持版本时，
    // 拒绝以旧逻辑解码（避免静默丢失新字段），提示用户升级应用。
    final fileVersion = decoded['version'];
    if (fileVersion is num && fileVersion.toInt() > _version) {
      throw FormatException(
        '文档版本过新（v$fileVersion，当前支持 v$_version），请升级应用后再打开',
      );
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

  // 对象数量/大小上限（红蓝攻防 D-4 修复 2026-08-15）：
  // 防恶意 JSON 堆叠海量条目触发 OOM（拒绝服务）。
  static const int _maxDecodeBytes = 100 * 1024 * 1024; // 100MB
  static const int _maxLayerCount = 200;
  static const int _maxStrokeCount = 10000;
  // 链 C 修复（军工审计 2026-08-15）：单笔点数上限——D-4 只限笔画数，
  // 一笔可含海量点（JSON 炸弹放大：95MB 文件反序列化内存爆 500MB+）。
  static const int _maxPointsPerStroke = 50000;
  // H-02 补全（专家审计 2026-08-15）：全局预算——层×笔画×点累计上限，
  // 防 200 层 × 1 万笔 × 海量点的 JSON 炸弹放大（100MB 输入解出天文对象）。
  static const int _maxTotalStrokes = 50000;
  static const int _maxTotalPoints = 1000000;
  static const int _maxShapeCount = 5000;
  static const int _maxImageCount = 5000;

  static int _restoreCanvasDimension(Object? value, int fallback) {
    if (value is! num || !value.toDouble().isFinite) return fallback;
    return value.toInt().clamp(16, 32768).toInt();
  }

  static List<Layer> _restoreLayers(Object? value) {
    final layers = <Layer>[];
    final ids = <String>{};
    // H-02 补全：全局笔画/点预算计数器。
    var totalStrokes = 0;
    var totalPoints = 0;
    if (value is List) {
      final limit = value.length.clamp(0, _maxLayerCount);
      for (var i = 0; i < limit; i++) {
        final entry = value[i];
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
          // H-02 补全：全局笔画/点预算——超限跳过后续层（防 JSON 炸弹放大）。
          totalStrokes += strokes.length;
          totalPoints += strokes.fold(0, (sum, s) => sum + s.points.length);
          if (totalStrokes > _maxTotalStrokes || totalPoints > _maxTotalPoints) {
            break;
          }
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
    final limit = value.length.clamp(0, _maxStrokeCount);
    for (var i = 0; i < limit; i++) {
      final entry = value[i];
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
        if (rawPoints.isNotEmpty && rawPoints.first is Map) {
          // 旧格式：对象数组 [{x,y,p}, ...]。
          for (final pointValue in rawPoints) {
            if (points.length >= _maxPointsPerStroke) break;
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
        } else {
          // 新格式（压缩点列）：扁平数值数组 [x0,y0,p0, x1,y1,p1, ...]。
          // 对齐 Saber SBN 二进制点列压缩思路，防御性恢复同步兼容。
          final flat = rawPoints.cast<num>();
          for (var i = 0; i + 2 < flat.length; i += 3) {
            if (points.length >= _maxPointsPerStroke) break;
            final x = flat[i].toDouble();
            final y = flat[i + 1].toDouble();
            final p = flat[i + 2].toDouble();
            if (!_isSafeCoordinate(x) || !_isSafeCoordinate(y) || !p.isFinite) {
              continue;
            }
            points.add(StrokePoint(x, y, p.clamp(0.0, 1.0).toDouble()));
          }
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
      final limit = value.length.clamp(0, _maxShapeCount);
      for (var i = 0; i < limit; i++) {
        final entry = value[i];
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
    final limit = value.length.clamp(0, _maxImageCount);
    for (var i = 0; i < limit; i++) {
      final entry = value[i];
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
