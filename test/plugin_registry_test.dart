import 'package:drawing_notes_app/core/plugins/drawing_plugin.dart';
import 'package:drawing_notes_app/core/plugins/nova_ai_plugin.dart';
import 'package:drawing_notes_app/core/plugins/plugin_registry.dart';
import 'package:drawing_notes_app/core/plugins/plugin_runtime_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'NOVA adapter receives runtime context and returns a proposal',
    () async {
      final logs = <String>[];
      final runtime = PluginRuntimeContext(onLog: logs.add);
      final registry = PluginRegistry(context: runtime);
      final plugin = _Nova();
      registry.register(plugin);
      expect(plugin.context, same(runtime));
      expect(logs, ['NOVA registered']);
      final refs = ['input.png'];
      final request = NovaAiRequest(prompt: 'sketch', references: refs);
      refs.clear();
      expect(request.references, ['input.png']);
      final result = await plugin.generate(request);
      expect(result.text, 'sketch');
      expect(result.artifacts, ['proposal.png']);
      expect(() => result.artifacts.clear(), throwsUnsupportedError);
      expect(() => registry.register(_Nova()), throwsStateError);
      registry.dispose();
      registry.dispose();
      expect(plugin.disposals, 1);
      expect(registry.plugins, isEmpty);
      expect(() => registry.register(_Nova()), throwsStateError);
    },
  );

  test('failed registration releases plugin and allows retry', () {
    final registry = PluginRegistry();
    final failed = _Nova(fail: true);
    expect(() => registry.register(failed), throwsStateError);
    expect(registry.find(failed.id), isNull);
    expect(failed.disposals, 1);
    registry.register(_Nova());
    registry.dispose();
  });

  test('unregister：移除并释放插件；未知 id 返回 null；幂等', () {
    final registry = PluginRegistry();
    final plugin = _Nova();
    registry.register(plugin);

    expect(registry.unregister('nope'), isNull);
    expect(registry.unregister(plugin.id), same(plugin));
    expect(plugin.disposals, 1);
    expect(registry.find(plugin.id), isNull);
    // 二次注销同一 id：未知 → null（幂等）。
    expect(registry.unregister(plugin.id), isNull);
    expect(plugin.disposals, 1, reason: '不重复释放');
    registry.dispose();
  });

  test('unregister 的 dispose 抛错不影响注销结果', () {
    final registry = PluginRegistry();
    final plugin = _NovaBoom();
    registry.register(plugin);
    expect(registry.unregister(plugin.id), same(plugin));
    expect(registry.find(plugin.id), isNull);
    registry.dispose();
  });
}

class _NovaBoom implements DrawingPlugin {
  @override
  String get id => 'boom';
  @override
  String get name => 'BOOM';
  @override
  void register(PluginContext context) {}
  @override
  void dispose() => throw StateError('dispose exploded');
}

class _Nova implements NovaAiPlugin {
  _Nova({this.fail = false});
  final bool fail;
  PluginContext? context;
  int disposals = 0;
  @override
  String get id => 'nova';
  @override
  String get name => 'NOVA';
  @override
  void register(PluginContext context) {
    this.context = context;
    if (fail) throw StateError('registration failed');
    context.log('NOVA registered');
  }

  @override
  Future<NovaAiProposal> generate(NovaAiRequest request) async =>
      NovaAiProposal(text: request.prompt, artifacts: ['proposal.png']);
  @override
  void dispose() => disposals++;
}
