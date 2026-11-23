// Spec 2 W6a (D8, D20): the chat's reads, one entry per account (the next
// account's entry starts as a plain loading value, never holding the last
// one's conversations), memory only, disposed when nothing shows them.
//
// Owner follow-up to W6 (fallback poll): some networks block WebSockets,
// so the signal channel may never join. While it is not joined, the app is
// in the foreground and the phone is online, the signals also tick a slow
// poll; the open chat and the list read again on it while they are the
// page shown and not already reading.
import 'dart:async';
import 'dart:math' as math;

import 'package:attune/features/dating/chat/dating_chat.dart';
import 'package:attune/features/dating/chat/dating_chat_repository.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_supabase_client.dart';
import 'package:attune/features/dating/device/dating_device_check.dart';
import 'package:attune/features/dating/device/trip_phone.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/lock/dating_unlock.dart'
    show DatingSessionMemory;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final datingChatGatewayProvider = Provider<DatingChatGateway>(
  (ref) => DatingChatRepository(
    ref.watch(datingRpcProvider),
    ref.watch(datingSupabaseClientProvider),
    // Spec 2 W8b (R-T4-9): the account signed in at each call (D8).
    showSameGender:
        () => DatingTripPhone.showFor(ref.read(datingAccountProvider)),
  ),
);

/// The conversations list (with the ended ones) for [account].
final datingConversationsProvider = FutureProvider.autoDispose
    .family<DatingConversations, String?>((ref, account) async {
      if (account == null) return DatingConversations.failed;
      // Final client fix (I-1): as Today, after a device check due or under
      // way (at most 3 s); not sent when its answer asked for a new read.
      final checker = ref.read(datingDeviceCheckerProvider.notifier);
      final asked = checker.changesFor(account);
      await checker.settled(account);
      if (checker.changesFor(account) != asked) {
        return DatingConversations.failed;
      }
      return ref.read(datingChatGatewayProvider).conversations(ended: true);
    });

/// Spec 2 W6b Task 7 fix round 1 (M-1): [account]'s card dismissals the
/// server has not confirmed yet. Their cards stay hidden and they are sent
/// again on the next good read. Memory only (D20): opaque ids, kept for
/// the app's life, one set per account, never shown to another. Final
/// client fix (M-3, §7.4): emptied by quick exit and sign-out (Dating's
/// session entry in the device wipe registry).
final datingPendingCardDismissalsProvider =
    Provider.family<Set<String>, String>(_wipedSet);

/// Spec 2 W6c Task 9 fix round 1 (M-3): [account]'s timebox dismissals
/// the server has not confirmed yet, as `matchId|card`. Their cards stay
/// hidden and they are sent again on the next good read (as the card
/// dismissals above). Memory only (D20), one set per account; emptied as
/// the card dismissals are (M-3).
final datingPendingTimeboxDismissalsProvider =
    Provider.family<Set<String>, String>(_wipedSet);

/// M-3: a set the session wipe empties (it stays the same set, so a
/// sender holding it sees it emptied).
Set<String> _wipedSet(Ref ref, String account) {
  final set = <String>{};
  DatingSessionMemory.track(set, ref, set.clear);
  return set;
}

/// Owner follow-up (fallback poll): how often the open chat and the list
/// read again while the signal channel is not joined.
const kDatingChatFallbackPoll = Duration(seconds: 30);

/// Each wait is [kDatingChatFallbackPoll] give or take this much, so many
/// phones never fall into step.
const kDatingChatFallbackJitter = Duration(seconds: 3);

/// A wait's jitter, from minus to plus [kDatingChatFallbackJitter] (tests
/// pin it).
final datingChatPollJitterProvider = Provider<Duration Function()>((ref) {
  final random = math.Random();
  final span = kDatingChatFallbackJitter.inMilliseconds;
  return () => Duration(milliseconds: random.nextInt(2 * span + 1) - span);
});

/// What [datingChatSignalsProvider] says. A new [reads] means "read again";
/// a new [polls] means "read again if shown and not already reading".
@immutable
class DatingChatSignals {
  const DatingChatSignals({
    this.reads = 0,
    this.polls = 0,
    this.rejoined = false,
  });

  /// Something changed, or the channel joined again after a gap (realtime
  /// never replays what changed while it was away: final client fix I-1).
  final int reads;

  /// The fallback poll's ticks.
  final int polls;

  /// N-1: a rejoin has read again since the phone last went offline (and
  /// the channel has not dropped since: fix round 1, M-1), so the
  /// connection's return need not read again.
  final bool rejoined;

  DatingChatSignals _with({int? reads, int? polls, bool? rejoined}) =>
      DatingChatSignals(
        reads: reads ?? this.reads,
        polls: polls ?? this.polls,
        rejoined: rejoined ?? this.rejoined,
      );
}

/// [account]'s chat signals while something listens. Never an error (a
/// dropped connection is silence; the screens read again when they open
/// and on resume, and the poll covers a channel that never joins). One
/// entry per account (D8): another account's entry starts fresh, and the
/// last one's poll goes with it.
final datingChatSignalsProvider = NotifierProvider.autoDispose
    .family<DatingChatSignalsNotifier, DatingChatSignals, String?>(
      DatingChatSignalsNotifier.new,
    );

class DatingChatSignalsNotifier
    extends AutoDisposeFamilyNotifier<DatingChatSignals, String?>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _live = false;
  bool _online = true;
  bool _foreground = true;

  /// Quick exit or sign-out: no more polls from this entry.
  bool _halted = false;

  /// The channel has joined at least once.
  bool _joined = false;

  /// Since the last join the channel went down or the poll ran: realtime
  /// may have missed something, so the next join reads again (N-2).
  bool _missed = false;

  /// Whether a poll is waiting (tests).
  @visibleForTesting
  bool get polling => _timer?.isActive ?? false;

  bool get _due => !_halted && !_live && _foreground && _online;

  @override
  DatingChatSignals build(String? account) {
    if (account == null) return const DatingChatSignals();
    final life = WidgetsBinding.instance.lifecycleState;
    _foreground = life == null || life == AppLifecycleState.resumed;
    _online = ref.read(datingOnlineProvider).valueOrNull ?? true;
    ref.listen<AsyncValue<bool>>(datingOnlineProvider, _onOnline);
    final binding = WidgetsBinding.instance..addObserver(this);
    final events = ref
        .read(datingChatGatewayProvider)
        .signals(account)
        .listen(_onSignal, onError: (Object _) {});
    DatingSessionMemory.track(this, ref, _halt);
    ref.onDispose(() {
      _cancel();
      binding.removeObserver(this);
      unawaited(events.cancel());
    });
    _ensure();
    return const DatingChatSignals();
  }

  void _onSignal(DatingChatSignal signal) {
    switch (signal) {
      case DatingChatSignal.changed:
        state = state._with(reads: state.reads + 1);
        _restart();
      case DatingChatSignal.live:
        // I-1 and N-2: a join after a gap (an earlier join, a failure, or
        // the poll running) reads again once; the very first join does not.
        final again = _joined || _missed;
        _joined = true;
        _missed = false;
        _live = true;
        _cancel();
        if (again) {
          state = state._with(reads: state.reads + 1, rejoined: true);
        }
      case DatingChatSignal.down:
        _missed = true;
        _live = false;
        // M-1: the rejoin's read no longer covers what comes next.
        if (state.rejoined) state = state._with(rejoined: false);
        _ensure();
    }
  }

  void _onOnline(AsyncValue<bool>? previous, AsyncValue<bool> next) {
    final online = next.valueOrNull ?? true;
    if (online == _online) return;
    _online = online;
    if (online) {
      // The screens read on the return themselves: a full wait from here.
      _restart();
    } else {
      _cancel();
      if (state.rejoined) state = state._with(rejoined: false);
    }
  }

  @override
  // The parameter keeps the framework's name; `this.state` is the signals.
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    // The chat and (fix round 1, M-2) the list read on resume themselves:
    // a full wait from there.
    foreground ? _restart() : _cancel();
  }

  /// Fix round 1 (M-3): a screen's own read is on its way (opening, the
  /// way back, Try again, resume): the next poll waits a full interval.
  void readStarted() => _restart();

  void _halt() {
    _halted = true;
    _cancel();
  }

  void _tick() {
    _timer = null;
    if (!_due) return;
    _missed = true;
    state = state._with(polls: state.polls + 1);
    _ensure();
  }

  /// A poll waiting, if one is due and none is.
  void _ensure() {
    if (_timer != null || !_due) return;
    _timer = Timer(
      kDatingChatFallbackPoll + ref.read(datingChatPollJitterProvider)(),
      _tick,
    );
  }

  /// A read is on its way: the next poll waits a full interval from now.
  void _restart() {
    _cancel();
    _ensure();
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
