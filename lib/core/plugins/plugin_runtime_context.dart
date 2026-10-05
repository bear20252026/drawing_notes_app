import 'package:drawing_notes_app/core/plugins/drawing_plugin.dart';

/// Runtime capabilities exposed to extensions.
///
/// The context intentionally starts small. New capabilities should be added
/// through stable APIs instead of exposing internal controller state.
final class PluginRuntimeContext implements PluginContext {
  PluginRuntimeContext({Map<String, Object?> metadata = const {}, this.onLog})
    : _metadata = Map<String, Object?>.unmodifiable(metadata);

  final void Function(String)? onLog;
  final Map<String, Object?> _metadata;

  @override
  void log(String message) => onLog?.call(message);

  Map<String, Object?> get metadata => _metadata;
}
