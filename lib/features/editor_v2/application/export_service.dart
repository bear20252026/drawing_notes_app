// editor_v2——ExportService（批次 F-6——2026-08-21——Excalidraw 导出模式）。
//
// 导出服务（PNG/SVG/JSON——Excalidraw 导出模式——本地化适配）。
// - toJson：文档序列化（Excalidraw .excalidraw 简单格式——纯逻辑可测试）
// - toSvg：SVG 生成（手写 XML——纯逻辑可测试）
// - toPng：toImage（UI 层——接受 RenderRepaintBoundary）
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:editor_core/editor_core.dart';

/// 导出服务（Excalidraw 导出模式——PNG/SVG/JSON）。
class ExportService {
  const ExportService._();

  /// 导出 JSON（文档序列化——Excalidraw .excalidraw 简单格式）。
  static String toJson(DocumentV2 doc) {
    final layersJson = doc.layers.map((l) {
      final strokes = l.strokes.map((s) => {
        'id': s.id,
        'points': s.points.map((p) => [p.x, p.y]).toList(),
      }).toList();
      final shapes = l.shapes.map((s) => {
        'id': s.id,
        'type': s.type,
        'x': s.x,
        'y': s.y,
        'width': s.width,
        'height': s.height,
      }).toList();
      final texts = l.texts.map((t) => {
        'id': t.id,
        'content': t.content,
        'x': t.x,
        'y': t.y,
      }).toList();
      return {
        'id': l.id,
        'name': l.name,
        'strokes': strokes,
        'shapes': shapes,
        'texts': texts,
        'visible': l.visible,
        'opacity': l.opacity,
      };
    }).toList();

    return jsonEncode({
      'type': 'excalidraw',
      'version': 2,
      'documentId': doc.id,
      'revision': doc.revision,
      'layers': layersJson,
    });
  }

  /// 导出 SVG（手写 XML——Excalidraw SVG 导出）。
  static String toSvg(DocumentV2 doc, {double width = 1200, double height = 800}) {
    final buffer = StringBuffer();
    buffer.write('<?xml version="1.0" encoding="UTF-8"?>\n');
    buffer.write('<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height">\n');

    for (final layer in doc.layers) {
      if (!layer.visible) continue;

      // 笔画（path——二次贝塞尔平滑——与 CanvasPainterV2 一致）。
      for (final stroke in layer.strokes) {
        if (stroke.points.length < 2) continue;
        final pts = stroke.points;
        buffer.write('<path d="M${pts.first.x},${pts.first.y}');
        for (var i = 1; i < pts.length - 1; i++) {
          final midX = (pts[i].x + pts[i + 1].x) / 2;
          final midY = (pts[i].y + pts[i + 1].y) / 2;
          buffer.write(' Q${pts[i].x},${pts[i].y} $midX,$midY');
        }
        buffer.write(' L${pts.last.x},${pts.last.y}" stroke="black" stroke-width="2" fill="none" stroke-linecap="round"/>\n');
      }

      // 形状。
      for (final shape in layer.shapes) {
        if (shape.type == 'rect') {
          buffer.write('<rect x="${shape.x}" y="${shape.y}" width="${shape.width}" height="${shape.height}" stroke="blue" stroke-width="2" fill="none"/>\n');
        } else if (shape.type == 'ellipse') {
          buffer.write('<ellipse cx="${shape.x + shape.width / 2}" cy="${shape.y + shape.height / 2}" rx="${shape.width / 2}" ry="${shape.height / 2}" stroke="blue" stroke-width="2" fill="none"/>\n');
        }
      }

      // 文本。
      for (final text in layer.texts) {
        buffer.write('<text x="${text.x}" y="${text.y}" font-size="14" fill="black">${_escapeXml(text.content)}</text>\n');
      }
    }

    buffer.write('</svg>\n');
    return buffer.toString();
  }

  /// 导出 PNG（toImage——UI 层——接受 RenderRepaintBoundary）。
  static Future<Uint8List> toPng(RenderRepaintBoundary boundary,
      {double pixelRatio = 2.0}) async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
