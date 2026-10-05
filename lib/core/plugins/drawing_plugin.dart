/// Drawing Notes extension contract.
///
/// v2.0 foundation: plugins can add brushes, exporters, AI adapters or
/// integrations without modifying the drawing core.
abstract interface class DrawingPlugin {
  /// Stable identifier used for registration and persistence.
  String get id;

  /// Human-readable plugin name.
  String get name;

  /// Called when the plugin is attached to the application runtime.
  void register(PluginContext context);

  /// Called before the plugin is removed.
  void dispose() {}
}

/// Minimal context exposed to extensions.
///
/// This intentionally starts small. Core services should be exposed only
/// through explicit capability interfaces to keep the security boundary clear.
abstract interface class PluginContext {
  void log(String message);
}
