import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Spec 8 (B3 (a); plan review M3): the sender's pause timer. Only its end
/// time, only on this device, so it survives the app closing; the partner
/// never sees a timer and the server never stores one.
const _kPrefix = 'pause_timer_end_';

/// The clock, replaceable in tests.
final pauseClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class PauseTimerNotifier extends StateNotifier<DateTime?> {
  PauseTimerNotifier(this._prefs, this._relationshipId, this._now)
    : super(_read(_prefs, _relationshipId));

  final SharedPreferences _prefs;
  final String _relationshipId;
  final DateTime Function() _now;

  String get _key => '$_kPrefix$_relationshipId';

  static DateTime? _read(SharedPreferences prefs, String relationshipId) {
    final raw = prefs.getString('$_kPrefix$relationshipId');
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> start(int minutes) async {
    final end = _now().add(Duration(minutes: minutes));
    state = end;
    await _prefs.setString(_key, end.toUtc().toIso8601String());
  }

  Future<void> clear() async {
    state = null;
    await _prefs.remove(_key);
  }
}

final pauseTimerProvider =
    StateNotifierProvider.family<PauseTimerNotifier, DateTime?, String>(
      (ref, relationshipId) => PauseTimerNotifier(
        ref.watch(sharedPreferencesProvider),
        relationshipId,
        ref.watch(pauseClockProvider),
      ),
    );
