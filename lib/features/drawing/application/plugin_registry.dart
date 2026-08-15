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

/// 插件扩展注册表（B3，借鉴 QOwnNotes 脚本 API / Joplin 插件生态）。
///
/// 集中管理笔刷扩展与工具扩展的注册与查询；
/// 界面（工具栏/笔刷菜单）从注册表动态生成，便于扩展而不改核心代码。
class PluginRegistry {
  final List<BrushExtension> _brushes = [];
  final List<ToolExtension> _tools = [];

  /// 注册笔刷扩展（已存在同 id 则覆盖）。
  void registerBrush(BrushExtension brush) {
    _brushes.removeWhere((b) => b.id == brush.id);
    _brushes.add(brush);
  }

  /// 注册工具扩展（已存在同 id 则覆盖）。
  void registerTool(ToolExtension tool) {
    _tools.removeWhere((t) => t.id == tool.id);
    _tools.add(tool);
  }

  /// 已注册笔刷列表。
  List<BrushExtension> get brushes => List.unmodifiable(_brushes);

  /// 已注册工具列表。
  List<ToolExtension> get tools => List.unmodifiable(_tools);
}
