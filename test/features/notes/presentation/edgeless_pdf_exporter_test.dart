// EdgelessPdfExporter 测试：场景包围盒 / 缩采样预算 / 单页 PDF 产物契约。
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drawing_notes_app/core/documents/note_block.dart';
import 'package:drawing_notes_app/core/documents/note_block_doc.dart';
import 'package:drawing_notes_app/features/notes/presentation/edgeless_pdf_exporter.dart';
import 'package:drawing_notes_app/features/notes/domain/edgeless_connector.dart';
import 'package:drawing_notes_app/features/notes/domain/edgeless_doc.dart';
import 'package:drawing_notes_app/features/notes/domain/edgeless_stroke.dart';

NoteBlockDoc _doc({String title = '', List<NoteBlock>? body}) =>
    NoteBlockDoc(
      id: 'doc_${title.isEmpty ? 'empty' : title}',
      title: title,
      body: body,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

NoteFrame _frame(String id, double x, double y, {double w = 360, double h = 400}) =>
    NoteFrame(
      id: id,
      x: x,
      y: y,
      w: w,
      h: h,
      doc: _doc(title: '帧$id'),
      zIndex: 1,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('computeEdgelessSceneBounds 全场景包围盒', () {
    test('全空画布返回 null', () {
      expect(computeEdgelessSceneBounds(EdgelessDoc(id: 'd')), isNull);
    });

    test('仅帧：取各帧矩形并集', () {
      final doc = EdgelessDoc(id: 'd', frames: [
        _frame('a', 0, 0),
        _frame('b', 400, 0),
      ]);
      expect(computeEdgelessSceneBounds(doc), const Rect.fromLTWH(0, 0, 760, 400));
    });

    test('帧外墨迹纳入（含线宽外扩）', () {
      final doc = EdgelessDoc(id: 'd', frames: [
        _frame('a', 0, 0),
      ], strokes: [
        // 点 (500,100)-(600,150)，宽 4 → bounds 外扩 2：(498,98,602,152)。
        const EdgelessStroke(
          id: 's1',
          points: [500, 100, 600, 150],
          color: '#000000',
          width: 4,
        ),
      ]);
      // 与帧 (0,0,360,400) 取并集 → (0,0,602,400)。
      expect(computeEdgelessSceneBounds(doc), const Rect.fromLTWH(0, 0, 602, 400));
    });

    test('形状纳入', () {
      final doc = EdgelessDoc(id: 'd', shapes: [
        const EdgelessShape(
          id: 'sh1',
          x: -100,
          y: -50,
          w: 80,
          h: 60,
          kind: EdgelessShapeKind.rect,
          color: '#3366CC',
        ),
      ]);
      expect(computeEdgelessSceneBounds(doc), const Rect.fromLTWH(-100, -50, 80, 60));
    });

    test('连接线纳入：线段 + 端点圆点外扩', () {
      final doc = EdgelessDoc(id: 'd', frames: [
        _frame('a', 0, 0),
        _frame('b', 400, 0),
      ], connectors: [
        const NoteConnector(
          id: 'c1',
          fromFrameId: 'a',
          toFrameId: 'b',
          fromAnchor: ConnectorAnchor.right,
          toAnchor: ConnectorAnchor.left,
        ),
      ]);
      // 锚点 (360,200)-(400,200)，外扩 width(2)+1.5=3.5，仍在帧并集内。
      expect(computeEdgelessSceneBounds(doc), const Rect.fromLTWH(0, 0, 760, 400));
    });

    test('竖直连接线标签横向外扩包围盒', () {
      // 两帧竖排（宽 100）：底部-顶部锚点连线为竖直段（x=50±3.5）；标签以
      // 线段中点 (50,450) 为中心、按 maxWidth 200 折行排版（同屏上
      // _ConnectorPainter），折行后宽度仍明显大于帧宽 100——包围盒右缘
      // 必须超出帧右缘 100 才算纳入了标签。
      final doc = EdgelessDoc(id: 'd', frames: [
        _frame('a', 0, 0, w: 100),
        _frame('b', 0, 500, w: 100),
      ], connectors: [
        const NoteConnector(
          id: 'c1',
          fromFrameId: 'a',
          toFrameId: 'b',
          fromAnchor: ConnectorAnchor.bottom,
          toAnchor: ConnectorAnchor.top,
          label: '一个相当长的连接线标签文本用于测试标签横向扩展包围盒的行为',
        ),
      ]);
      final bounds = computeEdgelessSceneBounds(doc)!;
      expect(bounds.right, greaterThan(100));
      expect(bounds.top, lessThanOrEqualTo(0));
      expect(bounds.bottom, greaterThanOrEqualTo(900));
    });

    test('悬空连接线（帧缺失）被跳过，不产生空矩形', () {
      final doc = EdgelessDoc(id: 'd', connectors: [
        const NoteConnector(
          id: 'c1',
          fromFrameId: 'x',
          toFrameId: 'y',
          fromAnchor: ConnectorAnchor.left,
          toAnchor: ConnectorAnchor.right,
        ),
      ]);
      expect(computeEdgelessSceneBounds(doc), isNull);
    });
  });

  group('edgelessRasterScale 缩采样预算', () {
    test('长边在预算内 1:1', () {
      expect(
        edgelessRasterScale(const Rect.fromLTWH(0, 0, 3600, 2000)),
        1,
      );
      expect(edgelessRasterScale(Rect.zero), 1);
    });

    test('长边超预算等比缩至 8192', () {
      const long = Rect.fromLTWH(-100, -50, 20000, 4000);
      final scale = edgelessRasterScale(long);
      expect(scale, closeTo(8192 / 20000, 1e-9));
      // 缩放后像素长边恰为预算上限。
      expect(long.width * scale, closeTo(8192, 1e-6));
      expect(long.height * scale, lessThan(8192));
    });
  });

  group('EdgelessPdfExporter.export 产物契约', () {
    testWidgets('整图导出：单页合法 PDF，页尺寸 = 包围盒', (tester) async {
      final doc = EdgelessDoc(
        id: 'd',
        frames: [_frame('a', 0, 0), _frame('b', 400, 0)],
        connectors: [
          const NoteConnector(
            id: 'c1',
            fromFrameId: 'a',
            toFrameId: 'b',
            fromAnchor: ConnectorAnchor.right,
            toAnchor: ConnectorAnchor.left,
          ),
        ],
        strokes: [
          const EdgelessStroke(
            id: 's1',
            points: [100, 420, 300, 460, 500, 430],
            color: '#CC6600',
            width: 3,
          ),
        ],
      );
      Uint8List? bytes;
      await tester.runAsync(() async {
        bytes = await EdgelessPdfExporter.export(
          doc,
          theme: ThemeData.light(),
          locale: const Locale('zh'),
        );
      });
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes!.sublist(0, 5)), '%PDF-');

      // 页尺寸契约：MediaBox = 包围盒（两帧 + 连接线 + 墨迹的并集；
      // 墨迹 maxY 460 含线宽外扩 1.5 → 底 461.5）。
      final ascii = String.fromCharCodes(bytes!);
      final match =
          RegExp(r'/MediaBox\s*\[([^\]]+)\]').firstMatch(ascii);
      expect(match, isNotNull);
      final nums = match!
          .group(1)!
          .trim()
          .split(RegExp(r'\s+'))
          .map(double.parse)
          .toList();
      expect(nums, hasLength(4));
      expect(nums[0], closeTo(0, 1e-6));
      expect(nums[1], closeTo(0, 1e-6));
      expect(nums[2], closeTo(760, 1e-6));
      expect(nums[3], closeTo(461.5, 1e-6));
    });

    testWidgets('全空画布导出返回 null（调用方出「无内容」提示）', (tester) async {
      Uint8List? bytes;
      await tester.runAsync(() async {
        bytes = await EdgelessPdfExporter.export(
          EdgelessDoc(id: 'd'),
          theme: ThemeData.light(),
        );
      });
      expect(bytes, isNull);
    });
  });
}
