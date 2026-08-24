// drawing——DocumentContainerCodec 容器格式（Saber .sbn 借鉴——2026-08-24）。
//
// 参考 Saber 的 .sbn 容器格式：JSON index + 二进制文档数据。
// 优势：JSON index 可快速读取元数据，二进制数据压缩存储笔画点列。
//
// 文件格式（.sbc - Saber Container 格式借鉴）：
// [4 bytes] 魔数: 0x53424330 ("SBC0")
// [4 bytes] 版本: 3
// [4 bytes] index 偏移量
// [N bytes] 二进制文档数据（笔画点列压缩）
// [M bytes] JSON index（元数据 + 数据偏移引用）
//
// 笔画点列压缩（对齐 Saber BSON 思路）：
// 每个点存储为 Float32List: [x: float32, y: float32, pressure: float32]
// 每点 12 字节 vs JSON 的 ~50+ 字节，体积缩小 ~4 倍。
//
// GPL-3.0 许可证——保留原始版权声明。
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:drawing_notes_app/features/drawing/domain/document.dart';
import 'package:drawing_notes_app/features/drawing/domain/document_image_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/layer.dart';
import 'package:drawing_notes_app/features/drawing/domain/shape_item.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';

/// 容器格式编解码器（Saber .sbn 借鉴——JSON index + 二进制数据）。
///
/// 文件结构：
/// - 魔数 + 版本头（8 字节）
/// - index 偏移量（4 字节）
/// - 二进制数据区（笔画点列压缩存储）
/// - JSON index 区（元数据 + 数据偏移引用）
class DocumentContainerCodec {
  const DocumentContainerCodec();

  /// 容器格式版本。
  static const int containerVersion = 3;

  /// 魔数: "SBC0" (Saber Container 0)。
  static const int magicNumber = 0x53424330;

  /// 头部大小: 4 (magic) + 4 (version) + 4 (index offset) = 12 字节。
  static const int headerSize = 12;

  /// 编码为容器格式字节。
  Uint8List encode(DrawingDocument doc) {
    // 1. 收集所有笔画点列，分配二进制偏移。
    final binaryData = BytesBuilder();
    final strokeOffsets = <String, int>{};

    var strokeIdx = 0;
    for (final layer in doc.layers) {
      for (final stroke in layer.strokes) {
        final key = '${layer.id}_$strokeIdx';
        strokeOffsets[key] = binaryData.length;
        strokeIdx++;

        // 压缩点列为 Float32List（每点 12 字节）。
        final pointData = _encodeStrokePoints(stroke.points);
        binaryData.add(pointData);
      }
    }

    // 2. 构建 JSON index（引用二进制偏移）。
    final indexMap = <String, dynamic>{
      'version': containerVersion,
      'document': {
        'id': doc.id,
        'title': doc.title,
        'width': doc.width,
        'height': doc.height,
        'infinite': doc.infinite,
        'paperType': doc.paperType.name,
        'createdAt': doc.createdAt.toIso8601String(),
        'updatedAt': doc.updatedAt.toIso8601String(),
      },
      'layers': doc.layers.map((l) {
        return {
          'id': l.id,
          'name': l.name,
          'visible': l.visible,
          'opacity': l.opacity,
          'strokes': l.strokes.asMap().entries.map((entry) {
            final key = '${l.id}_${entry.key}';
            final s = entry.value;
            return {
              'id': key,
              'color': s.color.value,
              'width': s.width,
              'type': s.type.name,
              'opacity': s.opacity,
              'pointCount': s.points.length,
              'binaryOffset': strokeOffsets[key],
            };
          }).toList(),
          'shapes': <Map<String, dynamic>>[],
          'texts': <Map<String, dynamic>>[], // V2 格式暂不支持
          'images': <Map<String, dynamic>>[], // V2 格式暂不支持
        };
      }).toList(),
      'shapes': doc.shapes.map((s) => s.toJson()).toList(),
      'imageItems': doc.imageItems.map((i) => i.toJson()).toList(),
    };

    final indexBytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(indexMap)),
    );

    // 3. 组装容器：头部 + 二进制数据 + JSON index。
    final header = ByteData(12);
    header.setUint32(0, magicNumber);
    header.setUint32(4, containerVersion);
    header.setUint32(8, headerSize + binaryData.length);

    final result = BytesBuilder();
    result.add(header.buffer.asUint8List());
    result.add(binaryData.toBytes());
    result.add(indexBytes);

    return result.toBytes();
  }

  /// 从容器格式字节解码。
  DrawingDocument decode(Uint8List bytes) {
    if (bytes.length < headerSize) {
      throw FormatException('容器文件过小');
    }

    final header = bytes.buffer.asByteData(0, headerSize);
    final magic = header.getUint32(0);
    if (magic != magicNumber) {
      throw FormatException('无效的容器文件格式');
    }

    final version = header.getUint32(4);
    if (version > containerVersion) {
      throw FormatException('容器版本过新（v$version），请升级应用');
    }

    final indexOffset = header.getUint32(8);
    if (indexOffset >= bytes.length) {
      throw FormatException('index 偏移量超出文件范围');
    }

    // 读取 JSON index。
    final indexBytes = bytes.sublist(indexOffset);
    final indexMap = jsonDecode(utf8.decode(indexBytes)) as Map<String, dynamic>;
    final docMap = indexMap['document'] as Map<String, dynamic>;

    // 读取二进制数据区（用于恢复笔画点列）。
    final binaryData = bytes.sublist(headerSize, indexOffset);

    // 恢复图层和笔画。
    final layers = <Layer>[];
    final layersList = indexMap['layers'] as List<dynamic>? ?? [];
    for (final layerEntry in layersList) {
      final layerJson = layerEntry as Map<String, dynamic>;
      final strokes = <Stroke>[];

      final strokesList = layerJson['strokes'] as List<dynamic>? ?? [];
      for (final strokeEntry in strokesList) {
        final strokeJson = strokeEntry as Map<String, dynamic>;
        final binaryOffset = strokeJson['binaryOffset'] as int? ?? 0;
        final pointCount = strokeJson['pointCount'] as int? ?? 0;

        // 从二进制数据恢复点列。
        final points = _decodeStrokePoints(
          binaryData,
          binaryOffset,
          pointCount,
        );

        if (points.isNotEmpty) {
          strokes.add(Stroke(
            points: points,
            color: Color(strokeJson['color'] as int? ?? 0xFF000000),
            width: (strokeJson['width'] as num?)?.toDouble() ?? 2.0,
            type: BrushType.values.firstWhere(
              (t) => t.name == strokeJson['type'],
              orElse: () => BrushType.pen,
            ),
            opacity: (strokeJson['opacity'] as num?)?.toDouble() ?? 1.0,
          ));
        }
      }

      layers.add(Layer(
        id: layerJson['id'] as String? ?? 'layer_1',
        name: layerJson['name'] as String? ?? '图层',
        visible: layerJson['visible'] as bool? ?? true,
        opacity: (layerJson['opacity'] as num?)?.toDouble() ?? 1.0,
        strokes: strokes,
      ));
    }

    // 恢复形状和图片（使用 JSON 格式）。
    final shapes = <PageShapeItem>[];
    final shapesList = indexMap['shapes'] as List<dynamic>? ?? [];
    for (final shapeEntry in shapesList) {
      try {
        shapes.add(PageShapeItem.fromJson(
          Map<String, dynamic>.from(shapeEntry as Map),
        ));
      } catch (_) {}
    }

    final imageItems = <DocumentImageItem>[];
    final imagesList = indexMap['imageItems'] as List<dynamic>? ?? [];
    for (final imageEntry in imagesList) {
      try {
        imageItems.add(DocumentImageItem.fromJson(
          Map<String, dynamic>.from(imageEntry as Map),
        ));
      } catch (_) {}
    }

    return DrawingDocument(
      id: docMap['id'] as String? ?? 'doc_1',
      title: docMap['title'] as String? ?? '未命名',
      width: (docMap['width'] as num?)?.toInt() ?? 2048,
      height: (docMap['height'] as num?)?.toInt() ?? 1536,
      infinite: docMap['infinite'] as bool? ?? false,
      paperType: PaperType.values.firstWhere(
        (t) => t.name == docMap['paperType'],
        orElse: () => PaperType.blank,
      ),
      layers: layers.isEmpty ? [Layer(id: 'layer_1', name: '图层 1')] : layers,
      shapes: shapes,
      imageItems: imageItems,
      createdAt: DateTime.tryParse(docMap['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(docMap['updatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  /// 编码笔画点列为 Float32List（每点 12 字节）。
  Uint8List _encodeStrokePoints(List<StrokePoint> points) {
    final data = ByteData(points.length * 12);
    for (var i = 0; i < points.length; i++) {
      final offset = i * 12;
      data.setFloat32(offset, points[i].x);
      data.setFloat32(offset + 4, points[i].y);
      data.setFloat32(offset + 8, points[i].pressure);
    }
    return data.buffer.asUint8List();
  }

  /// 从 Float32List 解码笔画点列。
  List<StrokePoint> _decodeStrokePoints(Uint8List binaryData, int offset, int count) {
    final points = <StrokePoint>[];
    final maxLength = binaryData.length;

    for (var i = 0; i < count; i++) {
      final pointOffset = offset + i * 12;
      if (pointOffset + 12 > maxLength) break;

      final data = binaryData.buffer.asByteData(pointOffset, 12);
      final x = data.getFloat32(0);
      final y = data.getFloat32(4);
      final pressure = data.getFloat32(8);

      if (x.isFinite && y.isFinite && pressure.isFinite) {
        points.add(StrokePoint(x, y, pressure.clamp(0.0, 1.0)));
      }
    }

    return points;
  }

  /// 检测文件是否为容器格式。
  static bool isContainerFormat(Uint8List bytes) {
    if (bytes.length < 4) return false;
    final magic = bytes.buffer.asByteData(0, 4).getUint32(0);
    return magic == magicNumber;
  }
}
