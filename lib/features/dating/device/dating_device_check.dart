// Spec 2 W8 final client fix (I-1; §2.3, §2.5): the device check, owned by
// Dating rather than Me's section alone. A trip's hiding is the server's,
// from the context row only dating-device-check moves, so a read sent
// before the check lands is read against the last place.
//
// - The check starts when the app comes back and when the first Dating
//   page opens (for someone whose home is known to have Dating data), and
//   from Today's, the conversations' and the messages' own reads, at most
//   once per [kDatingDeviceCheckEvery] per account.
// - Those reads wait for a check under way, at most
//   [kDatingDeviceCheckWait], then read as before.
// - The last answer (away, the place) is kept per account in memory. When
//   a new one differs, the home, Today, the conversations and the open
//   chat read again, so a trip that began (a same-gender one too: a place
//   now, none before) or ended leaves no page drawn from the last place.
//   A man-woman person in a place that restricts gets the same answer
//   every time, so nothing reads again for them.
// - The throttle runs on a monotonic stopwatch (a clock set back never
//   stalls it) or the wall clock (a phone asleep on a flight: the
//   stopwatch may not count the sleep), whichever says the time is up.
//
// Memory only, autoDispose (D8): gone when no Dating page or section
// listens, and emptied by quick exit and sign-out (Dating's session entry
// in the device wipe registry). A failed check changes nothing.
import 'dart:async';

import 'package:attune/features/dating/chat/dating_chat_providers.dart'
    show datingConversationsProvider;
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/device/dating_trip.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart'
    show DatingSessionMemory;
import 'package:attune/features/dating/routes/dating_page_watch.dart';
import 'package:attune/features/dating/today/dating_today_providers.dart'
    show datingTodayProvider;
import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long Today, the conversations and the messages wait for a check
/// under way before they read as before.
const kDatingDeviceCheckWait = Duration(seconds: 3);

/// §2.3: someone with Dating data, on a phone Dating can use.
bool datingDeviceCheckApplies(DatingHome home) =>
    home.hasData &&
    !const {
      DatingHomeState.featureUnavailable,
      DatingHomeState.countryClosed,
      DatingHomeState.regionClosed,
      DatingHomeState.reverifyDevice,
    }.contains(home.state);

/// What a check said about the place, as kept per account.
@immutable
class DatingTripAnswer {
  const DatingTripAnswer({this.away = false, this.noteCountry});

  /// No check yet: no restriction known (so a man-woman person at home
  /// never reads again on the first answer).
  static const none = DatingTripAnswer();

  final bool away;
  final String? noteCountry;

  @override
  bool operator ==(Object other) =>
      other is DatingTripAnswer &&
      other.away == away &&
      other.noteCountry == noteCountry;

  @override
  int get hashCode => Object.hash(away, noteCountry);
}

/// The checker's state: [changes] moves when an answer differed from the
/// last one (the open chat reads again on it); [answers] per account.
@immutable
class DatingDeviceChecks {
  const DatingDeviceChecks({this.changes = 0, this.answers = const {}});

  final int changes;
  final Map<String, DatingTripAnswer> answers;
}

/// One check's answer, and whether it changed what this phone knew (the
/// reads have then been asked again).
@immutable
class DatingDeviceCheckRun {
  const DatingDeviceCheckRun(this.answer, {this.changed = false});

  static const failed = DatingDeviceCheckRun(DatingDeviceCheck.failed);

  final DatingDeviceCheck answer;
  final bool changed;
}

final datingDeviceCheckerProvider =
    NotifierProvider.autoDispose<DatingDeviceChecker, DatingDeviceChecks>(
      DatingDeviceChecker.new,
    );

class DatingDeviceChecker extends AutoDisposeNotifier<DatingDeviceChecks>
    with WidgetsBindingObserver {
  /// The monotonic time (tests replace it).
  @visibleForTesting
  static Duration Function() monotonic = _elapsed;

  static final _stopwatch = Stopwatch()..start();
  static Duration _elapsed() => _stopwatch.elapsed;

  /// When each account's last check started: monotonic and wall clock.
  final _started = <String, (Duration, DateTime)>{};
  final _running = <String, Future<DatingDeviceCheckRun>>{};

  /// How many answers changed what the phone knew, per account (counts
  /// only; a wipe leaves them, so a read waiting across it still reads).
  final _changed = <String, int>{};
  int _epoch = 0;
  bool _disposed = false;

  @override
  DatingDeviceChecks build() {
    WidgetsBinding? binding;
    try {
      binding = WidgetsBinding.instance;
    } catch (_) {
      // No binding (a plain test): no lifecycle hook.
    }
    binding?.addObserver(this);
    DatingPageWatch.firstOpened.addListener(_onFirstPage);
    DatingSessionMemory.track(this, ref, _forget);
    ref.onDispose(() {
      _disposed = true;
      binding?.removeObserver(this);
      DatingPageWatch.firstOpened.removeListener(_onFirstPage);
    });
    return const DatingDeviceChecks();
  }

  @override
  // The parameter keeps the framework's name; `this.state` is the checks.
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _hook();
  }

  /// The first Dating page opened (in a later turn: never while a page
  /// builds).
  void _onFirstPage() => scheduleMicrotask(_hook);

  /// The lifecycle hook: only for an account whose home is known here.
  void _hook() {
    if (_disposed) return;
    ensure(ref.read(datingAccountProvider), needHome: true);
  }

  /// Quick exit and sign-out: every answer and every throttle goes; a
  /// check under way changes nothing when it lands.
  void _forget() {
    _epoch++;
    _started.clear();
    _running.clear();
    if (_disposed) return;
    state = DatingDeviceChecks(changes: state.changes);
  }

  DatingHome? _knownHome(String account) {
    final provider = datingHomeProvider(account);
    if (!ref.exists(provider)) return null;
    final read = ref.read(provider);
    return read.hasError ? null : read.valueOrNull;
  }

  bool _due(String account) {
    final last = _started[account];
    if (last == null) return true;
    final (mono, wall) = last;
    return monotonic() - mono >= kDatingDeviceCheckEvery ||
        clock.now().difference(wall) >= kDatingDeviceCheckEvery;
  }

  /// Starts a check for [account] when one is due: never for a home that
  /// [datingDeviceCheckApplies] refuses ([home], or the one read here),
  /// nor, with [needHome], while no home is known. Answers the check under
  /// way (a new one or one already running), or null.
  Future<DatingDeviceCheckRun>? ensure(
    String? account, {
    DatingHome? home,
    bool needHome = false,
  }) {
    if (account == null || _disposed) return null;
    final running = _running[account];
    if (running != null) return running;
    final known = home ?? _knownHome(account);
    if (known == null ? needHome : !datingDeviceCheckApplies(known)) {
      return null;
    }
    if (!_due(account)) return null;
    _started[account] = (monotonic(), clock.now());
    final run = _run(account, _epoch);
    _running[account] = run;
    unawaited(
      run.whenComplete(() {
        if (identical(_running[account], run)) _running.remove(account);
      }),
    );
    return run;
  }

  /// How many of [account]'s answers have changed what the phone knew: a
  /// read that waited for a check and sees this move has been asked again
  /// (the read it would send is superseded).
  int changesFor(String? account) => _changed[account] ?? 0;

  /// The check under way for [account], or null (none is started).
  Future<DatingDeviceCheckRun>? running(String? account) =>
      account == null ? null : _running[account];

  /// Today's and the conversations' reads: a check due or under way for
  /// [account] is waited for, at most [kDatingDeviceCheckWait].
  Future<void> settled(String? account) async {
    final run = ensure(account);
    if (run != null) await wait(run);
  }

  /// [run], waited for at most [kDatingDeviceCheckWait]; never throws.
  static Future<void> wait(Future<DatingDeviceCheckRun> run) async {
    try {
      await run.timeout(kDatingDeviceCheckWait);
    } catch (_) {
      // Read as before; a late answer that differs asks again.
    }
  }

  Future<DatingDeviceCheckRun> _run(String account, int epoch) async {
    try {
      final answer = await checkDatingDevice(ref.read);
      if (_disposed || epoch != _epoch || !answer.ok) {
        return DatingDeviceCheckRun(answer);
      }
      final next = DatingTripAnswer(
        away: answer.away,
        noteCountry: answer.noteCountry,
      );
      if (next == (state.answers[account] ?? DatingTripAnswer.none)) {
        return DatingDeviceCheckRun(answer);
      }
      _changed[account] = changesFor(account) + 1;
      state = DatingDeviceChecks(
        changes: state.changes + 1,
        answers: {...state.answers, account: next},
      );
      ref
        ..invalidate(datingHomeProvider(account))
        ..invalidate(datingTodayProvider(account))
        ..invalidate(datingConversationsProvider(account));
      return DatingDeviceCheckRun(answer, changed: true);
    } catch (_) {
      return DatingDeviceCheckRun.failed;
    }
  }
}
