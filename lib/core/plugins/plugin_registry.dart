import 'drawing_plugin.dart';

/// Runtime registry for Drawing Notes extensions.
///
/// This is intentionally independent from UI state. Future versions can add
/// persisted plugin metadata, permissions and marketplace discovery here.
final class PluginRegistry implements PluginContext {
  PluginRegistry({this.context, this.onLog});

  final PluginContext? context;
  final void Function(String)? onLog;
  final Map<String, DrawingPlugin> _plugins = <String, DrawingPlugin>{};
  bool _disposed = false;

  List<DrawingPlugin> get plugins => List.unmodifiable(_plugins.values);

  void register(DrawingPlugin plugin) {
    if (_disposed) throw StateError('Plugin registry is disposed');
    if (_plugins.containsKey(plugin.id)) {
      throw StateError('Plugin already registered: ${plugin.id}');
    }
    _plugins[plugin.id] = plugin;
    try {
      plugin.register(context ?? this);
    } catch (_) {
      _plugins.remove(plugin.id);
      try {
        plugin.dispose();
      } catch (_) {
        // Preserve the original registration failure.
      }
      rethrow;
    }
  }

  DrawingPlugin? find(String id) => _plugins[id];

  /// 注销并释放指定插件；未注册返回 null。
  ///
  /// B3 注册表统一（2026-10-07）：笔刷/工具扩展的「同 id 覆盖」语义经
  /// unregister + register 两步在同一引擎上实现——注册引擎只有这一份。
  DrawingPlugin? unregister(String id) {
    final plugin = _plugins.remove(id);
    if (plugin == null) return null;
    try {
      plugin.dispose();
    } catch (_) {
      // dispose 失败不影响注销结果（与 register 失败回滚同口径）。
    }
    return plugin;
  }

  @override
  void log(String message) {
    onLog?.call(message);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final registered = List<DrawingPlugin>.of(_plugins.values);
    _plugins.clear();
    Object? failure;
    StackTrace? trace;
    for (final plugin in registered) {
      try {
        plugin.dispose();
      } catch (error, stack) {
        failure ??= error;
        trace ??= stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
  }
}
