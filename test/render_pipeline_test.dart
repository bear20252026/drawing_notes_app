// 渲染引擎单元测试——渲染管线（LayerCompositor）+ 图层顺序合成 + 性能冒烟。
//
// 覆盖 Leader 要求的缺口：
// 1. 渲染管线正确性：空图层、单笔画、橡皮擦 clear 混合（像素级断言）
// 2. 视口裁剪：region 增量重建只绘制区域内像素
// 3. 高亮笔强制全量重建：绕过 region 裁剪（对比用例）
// 4. 图层排序：paintViews 文档序自底向上语义（顶层覆盖底层）
// 5. 大量元素性能冒烟：SpatialIndex 2000 元素 + 700 次查询
//
// 注：SpatialIndex 无最近邻查询 API（全库检索确认），该项无对应实现可测。
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drawing_notes_app/core/rendering/layer_compositor.dart';
import 'package:drawing_notes_app/features/drawing/application/spatial_index.dart';
import 'package:drawing_notes_app/features/drawing/domain/layer.dart';
import 'package:drawing_notes_app/features/drawing/domain/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

/// 水平直线笔画：从 (x1,y) 到 (x2,y)。
Stroke hline({
  required double x1,
  required double x2,
  required double y,
  ui.Color color = const ui.Color(0xFF000000),
  double width = 6,
  BrushType type = BrushType.pen,
}) =>
    Stroke(
      points: [StrokePoint(x1, y, 0.8), StrokePoint(x2, y, 0.8)],
      color: color,
      width: width,
      type: type,
    );

/// 读取图像指定坐标的像素颜色。
Future<ui.Color> pixelAt(ui.Image image, int x, int y) async {
  final ByteData? data =
      await image.toByteData();
  final bytes = data!.buffer.asUint8List();
  final offset = (y * image.width + x) * 4;
  return ui.Color.fromARGB(
    bytes[offset + 3],
    bytes[offset],
    bytes[offset + 1],
    bytes[offset + 2],
  );
}

const _transparent = ui.Color(0x00000000);

/// Color 通道访问的推荐写法（避免 deprecated 的 .alpha/.red 等 getter）。
int ch8(double normalized) => (normalized * 255.0).round().clamp(0, 255);
int alphaOf(ui.Color c) => ch8(c.a);
int redOf(ui.Color c) => ch8(c.r);
int greenOf(ui.Color c) => ch8(c.g);
int blueOf(ui.Color c) => ch8(c.b);

void main() {
  group('渲染管线：rasterize 正确性', () {
    test('空图层光栅化为全透明位图（边界：空集合）', () async {
      const compositor = LayerCompositor();
      final layer = Layer(id: 'empty', name: 'E');

      final image = await compositor.rasterize(layer, 120, 120);
      expect(await pixelAt(image, 60, 60), _transparent);
      expect(await pixelAt(image, 5, 5), _transparent);
      image.dispose();
    });

    test('单笔画渲染在预期位置着墨、远离处透明（渲染正确性）', () async {
      const compositor = LayerCompositor();
      final layer = Layer(id: 'l1', name: 'L1')
        ..strokes.add(hline(x1: 20, x2: 100, y: 60));

      final image = await compositor.rasterize(layer, 200, 120);
      final onStroke = await pixelAt(image, 60, 60);
      expect(alphaOf(onStroke), greaterThan(200), reason: '笔画线上应有墨');
      final offStroke = await pixelAt(image, 60, 15);
      expect(offStroke, _transparent, reason: '笔画线外应透明');
      image.dispose();
    });

    test('橡皮擦笔画清除同层已有墨迹（clear 混合模式）', () async {
      const compositor = LayerCompositor();

      // 底图：一条黑线
      final base = await compositor.rasterize(
        (Layer(id: 'l', name: 'L')..strokes.add(hline(x1: 20, x2: 100, y: 60))),
        200,
        120,
      );
      expect(alphaOf(await pixelAt(base, 60, 60)), greaterThan(200));

      // 同层再画橡皮擦（同一路径）→ 全量重建后该处透明
      final layer = Layer(id: 'l', name: 'L')
        ..strokes.add(hline(x1: 20, x2: 100, y: 60))
        ..strokes.add(hline(x1: 20, x2: 100, y: 60, type: BrushType.eraser));
      final erased = await compositor.rasterize(layer, 200, 120);

      expect(alphaOf(await pixelAt(erased, 60, 60)), lessThan(50),
          reason: '橡皮擦应清除路径上的墨迹');
      base.dispose();
      erased.dispose();
    });
  });

  group('视口裁剪（增量重建 region 语义）', () {
    test('region 外像素保持底图内容，笔画仅落在区域内（裁剪生效）', () async {
      const compositor = LayerCompositor();

      // 空白底图（模拟区域外"旧内容为空"）
      final emptyBase =
          await compositor.rasterize(Layer(id: 'b', name: 'B'), 200, 120);

      // 笔画横跨左右两半；只重绘右半 region
      final layer = Layer(id: 'l', name: 'L')
        ..strokes.add(hline(x1: 20, x2: 180, y: 60));
      final result = await compositor.rasterize(
        layer,
        200,
        120,
        region: const ui.Rect.fromLTWH(100, 0, 100, 120),
        base: emptyBase,
      );

      expect(alphaOf(await pixelAt(result, 150, 60)), greaterThan(200),
          reason: '区域内笔画段应着墨');
      expect(await pixelAt(result, 50, 60), _transparent,
          reason: '区域外笔画段应被 clipRect 裁掉');

      emptyBase.dispose();
      result.dispose();
    });

    test('高亮笔强制全量重建：即使传入 region 也两侧都着墨', () async {
      const compositor = LayerCompositor();
      final emptyBase =
          await compositor.rasterize(Layer(id: 'b', name: 'B'), 200, 120);

      final layer = Layer(id: 'l', name: 'L')
        ..strokes.add(
          hline(x1: 20, x2: 180, y: 60, color: const ui.Color(0xFF00FF00)),
        )
        ..strokes.add(
          hline(
            x1: 20,
            x2: 180,
            y: 90,
            color: const ui.Color(0x8000FF00),
            type: BrushType.marker,
          ),
        );
      final result = await compositor.rasterize(
        layer,
        200,
        120,
        region: const ui.Rect.fromLTWH(100, 0, 100, 120),
        base: emptyBase,
      );

      expect(alphaOf(await pixelAt(result, 150, 90)), greaterThan(0));
      expect(alphaOf(await pixelAt(result, 50, 90)), greaterThan(0),
          reason: 'marker 层不走增量路径：region 左侧也应被全量重绘');

      emptyBase.dispose();
      result.dispose();
    });
  });

  group('图层排序合成（paintViews 文档序自底向上语义）', () {
    Future<ui.Image> composite(List<LayerPaintView> views, int w, int h) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      for (final view in views) {
        final image = view.image;
        if (image == null || !view.visible || view.opacity <= 0) continue;
        final paint = ui.Paint()
          ..color = ui.Color.fromRGBO(0, 0, 0, view.opacity);
        canvas.drawImage(image, ui.Offset.zero, paint);
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(w, h);
      picture.dispose();
      return image;
    }

    test('顶层不透明笔画覆盖底层同位置颜色（文档序=自底向上）', () async {
      const compositor = LayerCompositor();

      final bottom = Layer(id: 'bottom', name: 'B')
        ..strokes.add(
          hline(x1: 20, x2: 180, y: 60, color: const ui.Color(0xFFFF0000)),
        );
      final top = Layer(id: 'top', name: 'T')
        ..strokes.add(
          hline(x1: 20, x2: 180, y: 60, color: const ui.Color(0xFF0000FF)),
        );

      final bottomImg = await compositor.rasterize(bottom, 200, 120);
      final topImg = await compositor.rasterize(top, 200, 120);

      // 文档序合成：bottom 在前（底）、top 在后（顶）
      final docOrder = await composite([
        LayerPaintView(image: bottomImg, visible: true, opacity: 1),
        LayerPaintView(image: topImg, visible: true, opacity: 1),
      ], 200, 120);
      expect(await pixelAt(docOrder, 100, 60), const ui.Color(0xFF0000FF),
          reason: '顶层的蓝色应覆盖底层的红色');

      // 反转顺序 → 红色在顶
      final reversed = await composite([
        LayerPaintView(image: topImg, visible: true, opacity: 1),
        LayerPaintView(image: bottomImg, visible: true, opacity: 1),
      ], 200, 120);
      expect(await pixelAt(reversed, 100, 60), const ui.Color(0xFFFF0000),
          reason: '列表顺序反转后红色应在顶部');

      for (final img in [bottomImg, topImg, docOrder, reversed]) {
        img.dispose();
      }
    });

    test('visible=false 与 opacity=0 的层被跳过（painter continue 分支）', () async {
      const compositor = LayerCompositor();

      final hidden = Layer(id: 'h', name: 'H')..visible = false;
      hidden.strokes.add(
        hline(x1: 20, x2: 180, y: 30, color: const ui.Color(0xFFFF00FF)),
      );
      final zeroOpacity = Layer(id: 'z', name: 'Z')..opacity = 0;
      zeroOpacity.strokes.add(
        hline(x1: 20, x2: 180, y: 90, color: const ui.Color(0xFFFFFF00)),
      );

      final hiddenImg = await compositor.rasterize(hidden, 200, 120);
      final zeroImg = await compositor.rasterize(zeroOpacity, 200, 120);

      final merged = await composite([
        LayerPaintView(image: hiddenImg, visible: false, opacity: 1),
        LayerPaintView(image: zeroImg, visible: true, opacity: 0),
      ], 200, 120);

      expect(await pixelAt(merged, 100, 30), _transparent,
          reason: '不可见层不应出现在合成结果');
      expect(await pixelAt(merged, 100, 90), _transparent,
          reason: 'opacity=0 层不应出现在合成结果');

      hiddenImg.dispose();
      zeroImg.dispose();
      merged.dispose();
    });

    test('半透明层与不透明层混合出中间色', () async {
      const compositor = LayerCompositor();

      final opaqueWhite = Layer(id: 'w', name: 'W')
        ..strokes.add(
          hline(x1: 40, x2: 160, y: 60, color: const ui.Color(0xFFFFFFFF)),
        );
      final semiRed = Layer(id: 'r', name: 'R')
        ..strokes.add(
          hline(x1: 40, x2: 160, y: 60, color: const ui.Color(0xFFFF0000)),
        );

      final wImg = await compositor.rasterize(opaqueWhite, 200, 120);
      final rImg = await compositor.rasterize(semiRed, 200, 120);

      // 红色层以 0.5 不透明度盖在白色上 → 粉色（红白各半）
      final mixed = await composite([
        LayerPaintView(image: wImg, visible: true, opacity: 1),
        LayerPaintView(image: rImg, visible: true, opacity: 0.5),
      ], 200, 120);

      final px = await pixelAt(mixed, 100, 60);
      // 0.5 不透明纯红叠白底：r = 255 保持高位，g/b ≈ 127。
      expect(redOf(px), greaterThan(200), reason: '红色层叠加后红分量保持高位');
      expect(greenOf(px), inInclusiveRange(110, 145),
          reason: '绿分量应约为白底的一半');
      expect(blueOf(px), inInclusiveRange(110, 145), reason: '蓝分量应约为白底的一半');

      for (final img in [wImg, rImg, mixed]) {
        img.dispose();
      }
    });
  });

  group('空间索引大量元素性能冒烟', () {
    test('2000 个元素插入 + 700 次查询在时限内完成且抽查正确', () async {
      final index = SpatialIndex();
      final sw = Stopwatch()..start();

      // 插入 2000 个互不重叠的网格方块（80 列 × 25 行）
      const cols = 80;
      for (var i = 0; i < 2000; i++) {
        final col = i % cols;
        final row = i ~/ cols;
        index.insert(
          'e-$i',
          ui.Rect.fromLTWH(col * 70.0, row * 70.0, 64, 64),
        );
      }
      final insertMs = sw.elapsedMilliseconds;

      var hitCount = 0;
      for (var q = 0; q < 500; q++) {
        final col = (q * 7) % cols;
        final row = ((q * 13) % 25).clamp(0, 24);
        final hits = index.query(
          ui.Rect.fromLTWH(col * 70.0 + 10, row * 70.0 + 10, 32, 32),
        );
        if (hits.isNotEmpty) hitCount++;
      }
      for (var q = 0; q < 200; q++) {
        index.queryPoint(ui.Offset(q * 11.0 % 5000, q * 17.0 % 1500));
      }
      sw.stop();

      // 宽松阈值：网格索引下应远低于此（CI 波动安全余量）
      expect(sw.elapsedMilliseconds, lessThan(3000),
          reason: '插入 ${insertMs}ms + 查询应在 3s 内完成');
      expect(hitCount, greaterThan(400),
          reason: '抽查的查询绝大多数应命中（索引精度健全性）');
    });
  });
}
