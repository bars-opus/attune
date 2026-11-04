import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The two Healing stages whose AI the crisis check guards (Spec 1 W9e).
enum HealingAiStage { postMortem, portrait }

/// One journey's stage, as the support state holds it.
typedef HealingSupportKey = ({String journeyId, HealingAiStage stage});

/// What the crisis check's `support_offered` answers mean for this run and
/// this account (Spec 1 W9e, W9c's pattern): [offered] shows the card for
/// that journey's stage; [hidden] keeps any AI text the phone holds for it
/// off the screen, also after "Not now", until a later `completed` answer
/// for that stage. Never stored on the phone, never sent anywhere.
@immutable
class HealingSupportState {
  const HealingSupportState({this.offered = const {}, this.hidden = const {}});

  final Set<HealingSupportKey> offered;
  final Set<HealingSupportKey> hidden;
}

/// Held in memory only (Spec 1, spec 6.6): emptied when the signed-in account
/// changes (D8, shared phones), and on sign-out and quick exit through the
/// device-wipe registry (`spec1.healing_support_memory`; on iOS quick exit
/// leaves the process alive behind the neutral screen).
class HealingSupport extends Notifier<HealingSupportState> {
  /// The account this state belongs to.
  String? account;

  @override
  HealingSupportState build() {
    account = ref.watch(healingAccountProvider);
    _matchedAt.clear();
    HealingSupportMemory.track(this, ref, () {
      _matchedAt.clear();
      state = const HealingSupportState();
    });
    return const HealingSupportState();
  }

  /// Requests are numbered when they are sent ([begin]); a match is
  /// numbered when it lands ([offer]).
  int _sent = 0;
  final _matchedAt = <HealingSupportKey, int>{};

  /// The number of a request about to be sent.
  int begin() => ++_sent;

  /// Whether an answer to [request] for [key] is older than the latest
  /// match for it: it is then never shown or saved, so an older non-match
  /// can't un-hide a newer match (W9 B8).
  bool isStale(HealingSupportKey key, int request) =>
      (_matchedAt[key] ?? 0) > request;

  /// `support_offered` for [key]: the card, and its AI text hidden.
  void offer(HealingSupportKey key) {
    _matchedAt[key] = ++_sent;
    state = HealingSupportState(
      offered: {...state.offered, key},
      hidden: {...state.hidden, key},
    );
    // The journey read before the match holds the AI text the server has
    // just removed: read it again.
    ref.invalidate(healingJourneyProvider);
  }

  /// "Not now": the card goes; the AI text stays hidden.
  void notNow(HealingSupportKey key) =>
      state = HealingSupportState(
        offered: {...state.offered}..remove(key),
        hidden: state.hidden,
      );

  /// A later `completed` answer for [key]: written for the words as they
  /// are now, so it may be shown.
  void completed(HealingSupportKey key) =>
      state = HealingSupportState(
        offered: {...state.offered}..remove(key),
        hidden: {...state.hidden}..remove(key),
      );
}

final healingSupportProvider =
    NotifierProvider<HealingSupport, HealingSupportState>(HealingSupport.new);

/// Healing's in-memory support state, emptied on sign-out and quick exit
/// (lib/app/device_wipes.dart). Mirrors the journal's JournalSupportMemory.
abstract final class HealingSupportMemory {
  static final _clears = <Object, void Function()>{};

  /// [owner]'s [clear], until [ref] is disposed or rebuilt.
  static void track(Object owner, Ref ref, void Function() clear) {
    _clears[owner] = clear;
    ref.onDispose(() => _clears.remove(owner));
  }

  static Future<void> clear() async {
    for (final clear in List.of(_clears.values)) {
      try {
        clear();
      } catch (_) {
        // A notifier being torn down has nothing left to clear.
      }
    }
  }
}
