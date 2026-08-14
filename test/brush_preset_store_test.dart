import 'dart:ui';

import 'package:drawing_notes_app/engine/brush_preset_store.dart';
import 'package:drawing_notes_app/models/stroke.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('默认预设为每种工具提供独立颜色与尺寸', () {
    final presets = BrushPresetBook.defaults();

    expect(presets.forTool(BrushType.pen).size, 6);
    expect(presets.forTool(BrushType.marker).size, 24);
    expect(presets.forTool(BrushType.marker).color, const Color(0xFFFFD54F));
    expect(presets.forTool(BrushType.eraser).size, 24);
  });

  test('更新高亮笔不改变钢笔和橡皮擦预设', () {
    final presets = BrushPresetBook.defaults().update(
      const BrushPreset(
        tool: BrushType.marker,
        color: Color(0xFF80CBC4),
        size: 32,
      ),
    );

    expect(presets.forTool(BrushType.marker).size, 32);
    expect(presets.forTool(BrushType.marker).color, const Color(0xFF80CBC4));
    expect(presets.forTool(BrushType.pen).size, 6);
    expect(presets.forTool(BrushType.eraser).size, 24);
  });

  test('JSON 往返保留各工具独立预设', () {
    final original = BrushPresetBook.defaults().update(
      const BrushPreset(
        tool: BrushType.pencil,
        color: Color(0xFF6D4C41),
        size: 9,
      ),
    );

    final restored = BrushPresetBook.fromJson(original.toJson());

    expect(restored.forTool(BrushType.pencil).size, 9);
    expect(restored.forTool(BrushType.pencil).color, const Color(0xFF6D4C41));
    expect(restored.forTool(BrushType.marker).size, 24);
  });

  test('不合法预设值回退到安全尺寸范围', () {
    final restored = BrushPresetBook.fromJson({
      'tools': {
        'marker': {'color': 0xFF000000, 'size': 1000},
        'pen': {'color': 'invalid', 'size': -1},
      },
    });

    expect(restored.forTool(BrushType.marker).size, BrushPresetBook.maxSize);
    expect(restored.forTool(BrushType.pen).size, BrushPresetBook.minSize);
    expect(restored.forTool(BrushType.pen).color, const Color(0xFF1A1A1A));
  });
}
