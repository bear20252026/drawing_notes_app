// 插件扩展注册表（plugin_registry.dart）单测：
// 注册 / 查找 / 重复注册覆盖 / 类型过滤 / 列表只读。

import 'package:drawing_notes_app/features/drawing/application/plugin_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('初始注册表为空（笔刷与工具均无注册）', () {
    final registry = PluginRegistry();

    expect(registry.brushes, isEmpty);
    expect(registry.tools, isEmpty);
  });

  test('注册笔刷扩展后可按注册顺序查到', () {
    final registry = PluginRegistry();
    const a = BrushExtension(id: 'ink', name: '水墨笔');
    const b = BrushExtension(id: 'marker', name: '马克笔');

    registry.registerBrush(a);
    registry.registerBrush(b);

    expect(registry.brushes, hasLength(2));
    expect(registry.brushes.first.id, 'ink');
    expect(registry.brushes.last.id, 'marker');
  });

  test('注册工具扩展后可查到', () {
    final registry = PluginRegistry();
    const tool = ToolExtension(id: 'ruler', name: '直尺');

    registry.registerTool(tool);

    expect(registry.tools, hasLength(1));
    expect(registry.tools.single.id, 'ruler');
    expect(registry.tools.single.name, '直尺');
  });

  test('重复注册同 id 笔刷：覆盖而非并存，后注册者生效', () {
    final registry = PluginRegistry();
    registry
      ..registerBrush(const BrushExtension(id: 'ink', name: '旧水墨'))
      ..registerBrush(const BrushExtension(id: 'ink', name: '新水墨'));

    expect(registry.brushes, hasLength(1), reason: '同 id 覆盖，不产生重复项');
    expect(registry.brushes.single.name, '新水墨');
  });

  test('重复注册同 id 工具：覆盖而非并存', () {
    final registry = PluginRegistry();
    registry
      ..registerTool(const ToolExtension(id: 'ruler', name: '直尺'))
      ..registerTool(const ToolExtension(id: 'ruler', name: '新直尺'));

    expect(registry.tools, hasLength(1));
    expect(registry.tools.single.name, '新直尺');
  });

  test('类型过滤：笔刷列表只含笔刷、工具列表只含工具（命名空间互不串扰）', () {
    final registry = PluginRegistry();
    registry
      ..registerBrush(const BrushExtension(id: 'shared', name: '同名笔刷'))
      ..registerTool(const ToolExtension(id: 'shared', name: '同名工具'));

    // 同 id 在两个命名空间可并存，互不覆盖。
    expect(registry.brushes, hasLength(1));
    expect(registry.tools, hasLength(1));
    expect(registry.brushes.single, isA<BrushExtension>());
    expect(registry.tools.single, isA<ToolExtension>());
    expect(registry.brushes.single.name, '同名笔刷');
    expect(registry.tools.single.name, '同名工具');
  });

  test('返回的列表不可变：外部 add 抛 UnsupportedError', () {
    final registry = PluginRegistry();
    registry.registerBrush(const BrushExtension(id: 'ink', name: '水墨笔'));

    expect(
      () => registry.brushes.add(const BrushExtension(id: 'x', name: 'x')),
      throwsUnsupportedError,
    );
    expect(
      () => registry.tools.add(const ToolExtension(id: 'x', name: 'x')),
      throwsUnsupportedError,
    );
  });

  test('覆盖注册保持既有条目稳定（其他 id 不受影响）', () {
    final registry = PluginRegistry();
    registry
      ..registerBrush(const BrushExtension(id: 'a', name: 'A'))
      ..registerBrush(const BrushExtension(id: 'b', name: 'B'))
      ..registerBrush(const BrushExtension(id: 'a', name: 'A2'));

    expect(registry.brushes.map((b) => b.id), ['b', 'a']);
    expect(
      registry.brushes.firstWhere((b) => b.id == 'b').name,
      'B',
      reason: '更新 a 不应波及 b',
    );
  });
}
