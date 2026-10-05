import 'package:flutter/foundation.dart';

/// Drawing domain service boundary.
///
/// v2 architecture preparation: new drawing capabilities should be added
/// through services instead of expanding DrawingController directly.
///
/// Existing controller code remains the compatibility facade during migration.
abstract interface class DrawingService {
  /// Called when the owning feature is disposed.
  @mustCallSuper
  void dispose() {}
}
