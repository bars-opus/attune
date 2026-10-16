import 'package:attune/features/couple_map/data/couple_map_local_store.dart';
import 'package:attune/features/couple_map/data/story_place_resolver.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:flutter/foundation.dart';

enum StoryPinNotice {
  paused,
  nearHome,
  notFound,

  /// Location isn't allowed for Attune: [StoryPinController.canAsk] says
  /// whether a tap may still show the system prompt, else Settings.
  allowLocation,

  /// The phone's location services are off: a tap opens their settings.
  turnOnLocation,
}

/// The "Pin to our map" switch (spec §3.3):
/// - off the first time, then the author's last choice;
/// - starts off while my area is paused;
/// - looks the place up only once on;
/// - turns itself off near the device-only home area, once, after which
///   the author's own "on" sticks.
class StoryPinController extends ChangeNotifier {
  StoryPinController({
    required this.store,
    required this.resolver,
    required this.paused,
    this.pausedCheck,
  });

  final CoupleMapLocalStore store;
  final StoryPlaceResolver resolver;
  final bool paused;

  /// My paused state, still being read: the pill shows at once and the
  /// default (paused → off, else the last choice) is applied when this
  /// lands — unless the author has already touched the switch.
  final Future<bool>? pausedCheck;

  Future<void>? _ready;
  bool _touched = false;

  bool _on = false;
  bool _resolving = false;
  bool _homeWarned = false;
  int _lookup = 0;
  StoryPlaceDraft? _place;
  StoryPinNotice? _notice;
  bool _disposed = false;
  Future<void>? _pending;

  bool get on => _on;
  bool get resolving => _resolving;
  StoryPlaceDraft? get place => _place;
  StoryPinNotice? get notice => _notice;

  bool _approximate = false;
  StoryPlaceProblem? _problem;

  /// The place is approximate (iOS Precise Location off).
  bool get approximate => _approximate;

  /// Location was denied but the system would still prompt.
  bool get canAsk => _problem == StoryPlaceProblem.needsAsk;

  /// What to attach at post time: only a resolved place while on. Waits
  /// for a lookup still in flight, so a shutter pressed while "Finding
  /// this place…" still pins the story.
  Future<StoryPlaceDraft?> placeForPost() async {
    // A shutter before the defaults are known waits for them, so a
    // remembered "on" still pins the story.
    await _ready;
    if (!_on) return null;
    await _pending;
    return _on ? _place : null;
  }

  Future<void> init() => _ready ??= _init();

  Future<void> _init() async {
    var isPaused = paused;
    final check = pausedCheck;
    if (check != null) {
      try {
        isPaused = await check;
      } catch (_) {
        isPaused = false;
      }
    }
    if (_touched) return; // the author chose while we waited
    if (isPaused) {
      _notice = StoryPinNotice.paused;
      _notify();
      return;
    }
    if (await readPinLastChoice(store) && !_touched) {
      // Started, not awaited: placeForPost awaits _ready, then _pending.
      // Never prompts: only a tap on the switch may ask.
      _pending = _lookupPlace(remember: false, ask: false);
    }
  }

  Future<void> setOn(bool on) async {
    _touched = true;
    if (!on) {
      _lookup++;
      _on = false;
      _resolving = false;
      _place = null;
      _pending = null;
      _approximate = false;
      _problem = null;
      if (_notice != StoryPinNotice.paused) _notice = null;
      _notify();
      await writePinLastChoice(store, false);
      return;
    }
    await _turnOn(remember: true);
  }

  Future<void> _turnOn({required bool remember}) {
    final f = _lookupPlace(remember: remember, ask: true);
    _pending = f;
    return f;
  }

  Future<void> _lookupPlace({required bool remember, required bool ask}) async {
    final lookupId = ++_lookup;
    _on = true;
    _resolving = true;
    // "Paused" only sets the default; turning it on clears that notice.
    if (_notice != StoryPinNotice.nearHome) _notice = null;
    _notify();
    if (remember) await writePinLastChoice(store, true);
    final lookup = await resolver.resolve(ask: ask);
    if (lookupId != _lookup || !_on) return; // turned off (or again) meanwhile
    _resolving = false;
    final draft = lookup.draft;
    _place = draft;
    _approximate = lookup.approximate;
    _problem = lookup.problem;
    if (draft == null) {
      _notice = switch (lookup.problem) {
        StoryPlaceProblem.needsAsk ||
        StoryPlaceProblem.noPermission => StoryPinNotice.allowLocation,
        StoryPlaceProblem.servicesOff => StoryPinNotice.turnOnLocation,
        _ => StoryPinNotice.notFound,
      };
    } else if (!_homeWarned) {
      final home = await readHomeArea(store);
      if (home != null && home.isNear(draft.lat, draft.lng)) {
        _homeWarned = true;
        _on = false;
        _notice = StoryPinNotice.nearHome;
      }
    } else {
      _notice = null;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
