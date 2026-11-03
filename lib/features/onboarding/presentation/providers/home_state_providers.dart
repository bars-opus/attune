import 'dart:async';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/data/home_state_store.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the home knows about the signed-in account right now (Spec 1
/// §5.3): the tab layout, link state, needs and hold, from the server's
/// last answer this run, else from the phone's cache; plus what the phone
/// still owes the server (a queued A5 or A6, §3.14). The path, the path
/// before it, the link details and the Dating summary come only from a
/// live answer and are never kept on the phone (D20).
@immutable
class HomeSnapshot {
  const HomeSnapshot({
    this.tab,
    this.link = LinkState.none,
    this.needs = const [],
    this.hold = false,
    this.holdKind,
    this.server,
  });

  /// Nothing known: no cache, no answer, nothing queued.
  static const unknown = HomeSnapshot();

  /// Null until something says which layout this account has.
  final AppTab? tab;
  final LinkState link;
  final List<HomeNeed> needs;
  final bool hold;

  /// Which hold (W6a); null when nothing named it.
  final HoldKind? holdKind;

  /// This run's live answer, in memory only.
  final HomeState? server;

  bool get known => tab != null;

  /// The v2 home may open: the layout is known, nothing is missing, no
  /// hold. An unrecognised need keeps it closed (HomeNeed.unknown).
  bool get isComplete => known && needs.isEmpty && !hold;

  AppPath? get path => server?.path;
  AppPath? get pathPrevious => server?.pathPrevious;
  DatingSummary? get dating => server?.dating;
  HomeLink get linkDetail => server?.link ?? HomeLink(state: link);

  factory HomeSnapshot.fromCache(CachedHomeState cache) => HomeSnapshot(
    tab: cache.tab,
    link: cache.link,
    needs: cache.needs,
    hold: cache.hold,
    holdKind: cache.holdKind,
  );

  factory HomeSnapshot.fromServer(HomeState state) => HomeSnapshot(
    tab: state.tab,
    link: state.link.state,
    needs: state.needs,
    hold: state.hold,
    holdKind: state.holdKind,
    server: state,
  );

  /// The queued writes count as done (§3.14): a queued A5 carries the
  /// consent, the date of birth and the name (and makes a brand-new
  /// account, so only A6 is left when nothing else is known); a queued A6
  /// carries the path and decides the layout.
  HomeSnapshot withQueued({required bool signUp, AppPath? path}) {
    var needs = this.needs;
    var tab = this.tab;
    if (signUp) {
      needs =
          known
              ? [
                for (final need in needs)
                  if (need != HomeNeed.consent &&
                      need != HomeNeed.birthDate &&
                      need != HomeNeed.name)
                    need,
              ]
              : const [HomeNeed.path];
    }
    if (path != null) {
      needs = [
        for (final need in needs)
          if (need != HomeNeed.path) need,
      ];
      tab = AppTab.forPath(path);
    }
    return HomeSnapshot(
      tab: tab,
      link: link,
      needs: needs,
      hold: hold,
      holdKind: holdKind,
      server: server,
    );
  }
}

/// One per signed-in account (keyed by user id). Synchronous, so the first
/// frame never waits: it opens on the cache and changes when [refresh] or
/// [apply] brings a server answer. HomeScreen refreshes it on launch,
/// resume, sign-in and relationshipModeResyncSignal; the gate and the
/// switch screens apply the answers their own calls return.
class HomeStateNotifier extends FamilyNotifier<HomeSnapshot, String> {
  HomeState? _server;
  Future<HomeState?>? _inFlight;

  /// Bumped when the provider is invalidated (sign-out). Riverpod keeps
  /// this instance, so a read that started before must not land after:
  /// it would bring back the path and Dating summary and rewrite the cache
  /// the sign-out just wiped (batch-1 review #2).
  int _generation = 0;

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  OnboardingStore get _store =>
      OnboardingStore(_prefs, scope: '${OnboardingStore.userScopePrefix}.$arg');

  @override
  HomeSnapshot build(String userId) {
    // Invalidating this provider forgets the live answer (sign-out).
    _server = null;
    _inFlight = null;
    ref.onDispose(() => _generation++);
    return _compose();
  }

  HomeSnapshot _compose() {
    final server = _server;
    final HomeSnapshot base;
    if (server != null) {
      base = HomeSnapshot.fromServer(server);
    } else {
      final cache = HomeStateStore(_prefs, userId: arg).read();
      base =
          cache == null ? HomeSnapshot.unknown : HomeSnapshot.fromCache(cache);
    }
    final store = _store;
    return base.withQueued(
      signUp: store.pendingSignUp != null,
      path: store.pendingPath,
    );
  }

  /// get_my_home_state(), once at a time. Null when it couldn't be read;
  /// the snapshot then stays as it was.
  Future<HomeState?> refresh() {
    final running = _inFlight;
    if (running != null) return running;
    late final Future<HomeState?> call;
    call = _refresh().whenComplete(() {
      if (identical(_inFlight, call)) _inFlight = null;
    });
    return _inFlight = call;
  }

  Future<HomeState?> _refresh() async {
    final generation = _generation;
    try {
      final answer = await ref.read(homeStateServiceProvider).fetch();
      if (generation != _generation) return null;
      await apply(answer);
      return answer;
    } catch (error) {
      debugPrint('[home-state] refresh failed: ${error.runtimeType}');
      return null;
    }
  }

  /// A server answer (from [refresh], set_my_path or the gate): kept in
  /// memory, and its tab layout, link, needs and hold cached for the next
  /// launch's first frame.
  Future<void> apply(HomeState answer) async {
    _server = answer;
    state = _compose();
    try {
      await HomeStateStore(_prefs, userId: arg).write(answer);
      // Spec §5.5: the v2 home replaces OnboardingMode for this account;
      // the legacy sync rebuilds it if flow_paths_v2 is switched off.
      final legacyMode =
          'attune.onboarding.${OnboardingStore.userScopePrefix}.$arg.mode';
      if (_prefs.containsKey(legacyMode)) await _prefs.remove(legacyMode);
    } catch (error) {
      debugPrint('[home-state] cache write failed: ${error.runtimeType}');
    }
  }

  /// After a local change the snapshot reads (a queued A6 choice, a
  /// replayed or dropped queue).
  void reloadLocal() => state = _compose();
}

final homeStateProvider =
    NotifierProvider.family<HomeStateNotifier, HomeSnapshot, String>(
      HomeStateNotifier.new,
    );
