import 'package:drawing_notes_app/core/plugins/drawing_plugin.dart';
import 'package:drawing_notes_app/core/plugins/plugin_registry.dart' as core;

/// 笔刷扩展（B3：插件接口，借鉴 QOwnNotes 脚本 API 扩展点）。
///
/// 第三方/内置模块可注册自定义笔刷（新笔画类型），
/// 渲染逻辑由注册的 [render] 标识对应的渲染分支处理。
class BrushExtension {
  const BrushExtension({
    required this.id,
    required this.name,
    this.icon = 'brush',
    this.description = '',
  });

  final String id;
  final String name;
  final String icon;
  final String description;
}

/// 工具扩展（B3）：可注册额外工具（如未来插件提供的新工具）。
class ToolExtension {
  const ToolExtension({
    required this.id,
    required this.name,
    this.description = '',
  });

  final String id;
  final String name;
  final String description;
}

/// 插件扩展注册表（B3）——**已与 core 插件引擎统一**（2026-10-07）。
///
/// 此前本类自持两张 List（笔刷/工具），与 `core/plugins/plugin_registry.dart`
/// 的 DrawingPlugin 引擎（生命周期、上下文、重复注册 fail-fast）并行并存、
/// 互不相通——「注册表有两份」正是台账遗留待办。统一后：注册引擎只有 core
/// 一份（单一事实来源），本类降级为 drawing 域的**类型化门面**——把笔刷/
/// 工具扩展适配成 [DrawingPlugin] 注册进同一引擎，公开 API（registerBrush /
/// registerTool / brushes / tools）与覆盖语义不变，既有调用方与测试零改动。
class PluginRegistry {
  final core.PluginRegistry _engine = core.PluginRegistry();

  /// 统一注册引擎的直读口（诊断 / 未来工具栏、笔刷菜单接线用）。
  core.PluginRegistry get engine => _engine;

  /// 注册笔刷扩展（已存在同 id 则覆盖——先注销旧实例再注册）。
  void registerBrush(BrushExtension brush) =>
      _replace(_BrushExtensionPlugin(brush));

  /// 注册工具扩展（已存在同 id 则覆盖——先注销旧实例再注册）。
  void registerTool(ToolExtension tool) => _replace(_ToolExtensionPlugin(tool));

  /// 已注册笔刷列表。
  List<BrushExtension> get brushes => _engine.plugins
      .whereType<_BrushExtensionPlugin>()
      .map((p) => p.extension)
      .toList(growable: false);

  /// 已注册工具列表。
  List<ToolExtension> get tools => _engine.plugins
      .whereType<_ToolExtensionPlugin>()
      .map((p) => p.extension)
      .toList(growable: false);

  /// 释放全部扩展（委托统一引擎——dispose 级联语义与其一致）。
  void dispose() => _engine.dispose();

  void _replace(DrawingPlugin plugin) {
    _engine.unregister(plugin.id);
    _engine.register(plugin);
  }
}

/// 笔刷扩展的引擎适配壳：扩展本体是不可变描述符，
/// 生命周期为空实现（implements 契约要求显式给出）。
class _BrushExtensionPlugin implements DrawingPlugin {
  _BrushExtensionPlugin(this.extension);

  final BrushExtension extension;

  /// 引擎按单一 id 键控，而 B3 契约允许同 id 在笔刷/工具两个命名空间并存
  /// （「类型过滤…命名空间互不串扰」）——引擎层加前缀映射保住该契约，
  /// 对外 [BrushExtension.id] 原样不动。
  @override
  String get id => 'brush:${extension.id}';

  @override
  String get name => extension.name;

  @override
  void register(covariant PluginContext context) {}

  @override
  void dispose() {}
}

/// 工具扩展的引擎适配壳（同 [_BrushExtensionPlugin]）。
class _ToolExtensionPlugin implements DrawingPlugin {
  _ToolExtensionPlugin(this.extension);

  final ToolExtension extension;

  /// 同 [_BrushExtensionPlugin.id] 的命名空间映射。
  @override
  String get id => 'tool:${extension.id}';

  @override
  String get name => extension.name;

  @override
  void register(covariant PluginContext context) {}

  @override
  void dispose() {}
}
