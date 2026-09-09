import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Injectable haptic feedback so widgets can trigger taps and tests can assert
/// call counts without a device. Universal — any feature can depend on it.
abstract class Haptics {
  void light();
  void selection();

  /// A deliberate, discrete action — locking a recording, stopping one.
  /// Heavier than [light], which marks incidental contact.
  void medium();
}

class SystemHaptics implements Haptics {
  const SystemHaptics();
  @override
  void light() => HapticFeedback.lightImpact();
  @override
  void selection() => HapticFeedback.selectionClick();
  @override
  void medium() => HapticFeedback.mediumImpact();
}

class FakeHaptics implements Haptics {
  int lightCount = 0;
  int selectionCount = 0;
  int mediumCount = 0;
  @override
  void light() => lightCount++;
  @override
  void selection() => selectionCount++;
  @override
  void medium() => mediumCount++;
}

final hapticsProvider = Provider<Haptics>((ref) => const SystemHaptics());

/// Controls the iOS audio-session flag that permits haptics while a
/// microphone is active.
///
/// iOS defaults this flag to false. Without enabling it, a camera-recording
/// flow can call [Haptics.medium] correctly while lock/stop feedback remains
/// physically silent. The flag is scoped to capture screens so unrelated
/// voice recording cannot admit app sounds into recorded audio.
abstract class RecordingHaptics {
  Future<void> enable();
  Future<void> disable();
}

class PlatformRecordingHaptics implements RecordingHaptics {
  const PlatformRecordingHaptics({
    this.channel = const MethodChannel('attune/recording_haptics'),
    this.platform,
  });

  final MethodChannel channel;

  /// Test seam; production follows Flutter's current target platform.
  @visibleForTesting
  final TargetPlatform? platform;

  Future<void> _setEnabled(bool enabled) async {
    if (kIsWeb || (platform ?? defaultTargetPlatform) != TargetPlatform.iOS) {
      return;
    }
    try {
      await channel.invokeMethod<void>('setEnabled', enabled);
    } on MissingPluginException {
      // Older builds and non-hosted test environments degrade to the normal
      // Flutter haptic path rather than breaking camera capture.
    } on PlatformException catch (error) {
      if (kDebugMode) {
        debugPrint('[haptics] recording-session configuration failed: $error');
      }
    }
  }

  @override
  Future<void> enable() => _setEnabled(true);

  @override
  Future<void> disable() => _setEnabled(false);
}

class FakeRecordingHaptics implements RecordingHaptics {
  int enableCount = 0;
  int disableCount = 0;

  @override
  Future<void> enable() async => enableCount++;

  @override
  Future<void> disable() async => disableCount++;
}

final recordingHapticsProvider = Provider<RecordingHaptics>(
  (ref) => const PlatformRecordingHaptics(),
);
