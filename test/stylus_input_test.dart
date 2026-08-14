import 'package:drawing_notes_app/engine/stylus_input.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

PointerMoveEvent pointerEvent({
  required PointerDeviceKind kind,
  required double pressure,
  double pressureMin = 1,
  double pressureMax = 1,
}) => PointerMoveEvent(
  kind: kind,
  position: Offset.zero,
  pressure: pressure,
  pressureMin: pressureMin,
  pressureMax: pressureMax,
);

void main() {
  test(
    'normalizes a stylus pressure range and exposes real hardware source',
    () {
      final processor = StylusInputProcessor(smoothing: 0);
      final sample = processor.process(
        pointerEvent(
          kind: PointerDeviceKind.stylus,
          pressure: 550,
          pressureMin: 100,
          pressureMax: 1000,
        ),
      );

      expect(sample.value, closeTo(0.5, 0.001));
      expect(sample.source, InkInputSource.stylusPressure);
      expect(sample.hasHardwarePressure, isTrue);
    },
  );

  test('uses explicit fallback when a mouse reports no pressure range', () {
    final processor = StylusInputProcessor(smoothing: 0);
    final sample = processor.process(
      pointerEvent(kind: PointerDeviceKind.mouse, pressure: 1),
      fallbackPressure: 0.72,
    );

    expect(sample.value, 0.72);
    expect(sample.source, InkInputSource.mouseVelocityFallback);
    expect(sample.hasHardwarePressure, isFalse);
  });

  test('does not treat generic touch pressure as ink pressure by default', () {
    final processor = StylusInputProcessor(smoothing: 0);
    final sample = processor.process(
      pointerEvent(
        kind: PointerDeviceKind.touch,
        pressure: 0.5,
        pressureMin: 0,
        pressureMax: 1,
      ),
      fallbackPressure: 0.9,
    );

    expect(sample.value, 0.9);
    expect(sample.source, InkInputSource.mouseVelocityFallback);
  });

  test('resets smoothing between separate strokes', () {
    final processor = StylusInputProcessor(smoothing: 0.5);
    processor.process(
      pointerEvent(
        kind: PointerDeviceKind.stylus,
        pressure: 1,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    processor.resetStroke();
    final sample = processor.process(
      pointerEvent(
        kind: PointerDeviceKind.stylus,
        pressure: 0,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );

    expect(sample.value, 0);
  });
}
