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
