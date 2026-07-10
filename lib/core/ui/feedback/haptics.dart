import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Injectable haptic feedback so widgets can trigger taps and tests can assert
/// call counts without a device. Universal — any feature can depend on it.
abstract class Haptics {
  void light();
  void selection();
}

class SystemHaptics implements Haptics {
  const SystemHaptics();
  @override
  void light() => HapticFeedback.lightImpact();
  @override
  void selection() => HapticFeedback.selectionClick();
}

class FakeHaptics implements Haptics {
  int lightCount = 0;
  int selectionCount = 0;
  @override
  void light() => lightCount++;
  @override
  void selection() => selectionCount++;
}

final hapticsProvider = Provider<Haptics>((ref) => const SystemHaptics());
