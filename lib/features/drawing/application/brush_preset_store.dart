import 'dart:convert';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:drawing_notes_app/core/canvas_model/stroke.dart';

/// 单个书写工具的持久化预设。
class BrushPreset {
  const BrushPreset({
    required this.tool,
    required this.color,
    required this.size,
  });

  final BrushType tool;
  final Color color;
  final double size;

  BrushPreset copyWith({Color? color, double? size}) => BrushPreset(
    tool: tool,
    color: color ?? this.color,
    size: size ?? this.size,
  );

  Map<String, Object> toJson() => {'color': color.toARGB32(), 'size': size};

  static BrushPreset fromJson(BrushType tool, Map<String, dynamic> json) {
    final fallback = BrushPresetBook.defaults().forTool(tool);
    final rawColor = json['color'];
    final rawSize = json['size'];
    return BrushPreset(
      tool: tool,
      color: rawColor is num ? Color(rawColor.toInt()) : fallback.color,
      size: rawSize is num
          ? rawSize.toDouble().clamp(
              BrushPresetBook.minSize,
              BrushPresetBook.maxSize,
            )
          : fallback.size,
    );
  }
}

/// 全部工具预设的内存快照与 JSON 编解码器。
class BrushPresetBook {
  BrushPresetBook(Map<BrushType, BrushPreset> presets)
    : _presets = Map<BrushType, BrushPreset>.unmodifiable(presets);

  static const double minSize = 1;
  static const double maxSize = 96;

  final Map<BrushType, BrushPreset> _presets;

  factory BrushPresetBook.defaults() => BrushPresetBook({
    BrushType.pen: const BrushPreset(
      tool: BrushType.pen,
      color: Color(0xFF1A1A1A),
      size: 6,
    ),
    BrushType.pencil: const BrushPreset(
      tool: BrushType.pencil,
      color: Color(0xFF424242),
      size: 5,
    ),
    BrushType.marker: const BrushPreset(
      tool: BrushType.marker,
      color: Color(0xFFFFD54F),
      size: 24,
    ),
    BrushType.laser: const BrushPreset(
      tool: BrushType.laser,
      color: Color(0xFFFF3B30),
      size: 10,
    ),
    BrushType.eraser: const BrushPreset(
      tool: BrushType.eraser,
      color: Color(0x00000000),
      size: 24,
    ),
  });

  BrushPreset forTool(BrushType tool) => _presets[tool]!;

  BrushPresetBook update(BrushPreset preset) =>
      BrushPresetBook({..._presets, preset.tool: preset});

  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'tools': {
      for (final tool in BrushType.values) tool.name: forTool(tool).toJson(),
    },
  };

  factory BrushPresetBook.fromJson(Map<String, dynamic> json) {
    final defaults = BrushPresetBook.defaults();
    final rawTools = json['tools'];
    if (rawTools is! Map) return defaults;

    var result = defaults;
    for (final tool in BrushType.values) {
      final value = rawTools[tool.name];
      if (value is Map) {
        result = result.update(
          BrushPreset.fromJson(tool, Map<String, dynamic>.from(value)),
        );
      }
    }
    return result;
  }
}

/// 使用 [SharedPreferences] 保存工具预设。
///
/// 单个 JSON 键可避免多个异步写入相互覆盖；损坏或旧格式的值会自动回退到
/// 安全默认值，因而不会阻止用户进入编辑器。
class BrushPresetStore {
  BrushPresetStore({Future<SharedPreferences> Function()? preferencesLoader})
    : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const storageKey = 'writing_tool_presets.v1';

  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<BrushPresetBook> load() async {
    final prefs = await _preferencesLoader();
    final raw = prefs.getString(storageKey);
    if (raw == null) return BrushPresetBook.defaults();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return BrushPresetBook.defaults();
      return BrushPresetBook.fromJson(Map<String, dynamic>.from(decoded));
    } on FormatException {
      return BrushPresetBook.defaults();
    }
  }

  Future<void> save(BrushPresetBook book) async {
    final prefs = await _preferencesLoader();
    await prefs.setString(storageKey, jsonEncode(book.toJson()));
  }
}
