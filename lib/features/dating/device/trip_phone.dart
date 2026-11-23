// Spec 2 W8b (§2.5, §3.11; R-T4-9, Re4-I-2): a same-gender trip's note and
// "Show it on this phone anyway" live on this phone only, never on the
// server (any server record of that choice would say who made it). The
// home answers `trip: {kind: 'same_gender'}` and nothing else; the phone
// decides whether the note shows and what the reads ask for.
//
// One mark per account, made only when the person answers the note: the
// mark is "the note was answered", its choice, and the last time the home
// answered a same-gender trip. Every same-gender answer moves that time;
// the mark goes only after 7 consecutive days of homes with no
// same-gender trip, so a home that flips (a VPN on and off, a place not
// always resolved) never brings the note back within a trip.
//
// Stored in the Safety PIN's keystore (this phone only, excluded from
// backups) under one neutral key; nothing in the key or the value names
// Dating, a gender, a trip or a place (D20). Quick exit and sign-out
// remove it (Dating's device wipe entry spec2.section_view). Every
// failure reads as no mark: the note shows and nothing is shown anyway
// (fail closed).
//
// Spec 2 W8 final client fix (M-1, M-2): every keystore read, write and
// delete of the key runs through one queue in the app, one at a time and
// in order (iOS's plugin runs its calls on a concurrent queue, so the
// platform's order is not the app's), and a stale mark of any account is
// dropped whenever the marks are read or written.
import 'dart:async';
import 'dart:convert';

import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One account's answer to a same-gender trip's note on this phone.
@immutable
class DatingTripMark {
  const DatingTripMark({required this.show, required this.lastSeen});

  /// "Show it on this phone anyway" (false: "Keep it hidden").
  final bool show;

  /// The last home that answered a same-gender trip (UTC, seconds).
  final DateTime lastSeen;
}

abstract final class DatingTripPhone {
  /// The device key (neutral, D20).
  static const key = 'me_section_view';

  /// A mark goes after this long with no same-gender trip (Re4-I-2).
  static const clearAfter = Duration(days: 7);

  /// Fix round 1 (I-1): a mark dated further ahead than this (the phone's
  /// clock set back) is no mark.
  static const aheadAllowed = Duration(days: 1);

  /// The keystore (tests replace it).
  @visibleForTesting
  static FlutterSecureStorage storage = SafetyPinStore.defaultStorage;

  static Map<String, DatingTripMark>? _marks;
  static Future<Map<String, DatingTripMark>>? _loading;
  static int _epoch = 0;
  static Future<void>? _queue;

  /// Forgets what was read (tests: a fresh phone).
  @visibleForTesting
  static void reset() {
    _marks = null;
    _loading = null;
    _epoch++;
    _queue = null;
  }

  /// Runs [job] after every keystore call before it (one at a time, in
  /// order; final client fix M-1: reads, writes and deletes alike). With
  /// nothing before it, [job] starts in this same turn. A job that fails
  /// never stops the next. Nothing is kept once the last one is done (a
  /// finished future would hold its zone).
  static Future<T> _enqueue<T>(Future<T> Function() job) {
    final before = _queue;
    final next = before == null ? job() : before.then((_) => job());
    final done = next.then<void>((_) {}, onError: (Object _) {});
    _queue = done;
    unawaited(
      done.whenComplete(() {
        if (identical(_queue, done)) _queue = null;
      }),
    );
    return next;
  }

  /// Final client fix (M-2): drops every account's stale mark from
  /// [marks] (another account's too: its 7 days run while someone else
  /// uses the phone); whether any went.
  static bool _prune(Map<String, DatingTripMark> marks) {
    final now = _now();
    final before = marks.length;
    marks.removeWhere((_, mark) => _stale(mark, now));
    return marks.length != before;
  }

  static Future<Map<String, DatingTripMark>> _load() {
    final marks = _marks;
    if (marks != null) return Future.value(marks);
    return _loading ??= () async {
      final epoch = _epoch;
      final read = <String, DatingTripMark>{};
      try {
        final raw = await _enqueue(() => storage.read(key: key));
        final decoded = raw == null ? null : jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((account, value) {
            if (account is String &&
                value is List &&
                value.length == 2 &&
                value[0] is int &&
                value[1] is int) {
              read[account] = DatingTripMark(
                show: value[0] == 1,
                lastSeen: DateTime.fromMillisecondsSinceEpoch(
                  (value[1] as int) * 1000,
                  isUtc: true,
                ),
              );
            }
          });
        }
      } catch (_) {
        // Unreadable: no mark (the note shows; nothing is shown anyway).
      }
      if (epoch != _epoch) return _marks ?? <String, DatingTripMark>{};
      _loading = null;
      return _marks = read;
    }();
  }

  /// Writes [marks] in order, unless a wipe came since [epoch].
  static Future<void> _save(int epoch) {
    return _enqueue(() async {
      final marks = _marks;
      if (epoch != _epoch || marks == null) return;
      // M-2: no stale mark is written back.
      _prune(marks);
      try {
        if (marks.isEmpty) {
          await storage.delete(key: key);
        } else {
          await storage.write(
            key: key,
            value: jsonEncode({
              for (final MapEntry(key: account, value: m) in marks.entries)
                account: [
                  m.show ? 1 : 0,
                  m.lastSeen.millisecondsSinceEpoch ~/ 1000,
                ],
            }),
          );
        }
      } catch (_) {
        // Kept in memory for this session; the next start reads no mark.
      }
    });
  }

  static DateTime _now() => clock.now().toUtc();

  /// Fix round 1 (I-1): a mark 7 days or more old (however long since the
  /// last read: three weeks without opening Attune are three weeks without
  /// a same-gender trip), or dated more than [aheadAllowed] ahead of this
  /// phone's clock, is no answer: the note shows again, nothing is shown
  /// anyway.
  static bool _stale(DatingTripMark mark, DateTime now) {
    final age = now.difference(mark.lastSeen);
    return age >= clearAfter || -age > aheadAllowed;
  }

  /// [account]'s mark, or null (a stale one is removed, any account's:
  /// M-2).
  static Future<DatingTripMark?> markFor(String? account) async {
    if (account == null) return null;
    final epoch = _epoch;
    final marks = await _load();
    if (epoch != _epoch) return null;
    if (_prune(marks)) unawaited(_save(epoch));
    return marks[account];
  }

  /// "Show it on this phone anyway" for [account]: what the reads pass as
  /// `p_show_same_gender` (false with no mark, or on any failure).
  static Future<bool> showFor(String? account) async {
    try {
      return (await markFor(account))?.show ?? false;
    } catch (_) {
      return false;
    }
  }

  /// The person answered the note: "Show it on this phone anyway"
  /// ([show]) or "Keep it hidden".
  static Future<void> answer(String account, {required bool show}) async {
    final epoch = _epoch;
    final marks = await _load();
    // A wipe while the marks were read: the answer goes with it.
    if (epoch != _epoch) return;
    marks[account] = DatingTripMark(show: show, lastSeen: _now());
    await _save(epoch);
  }

  /// A good home read for [account]: a same-gender trip is given its note
  /// and choice from this phone, and moves the mark's time; any other home
  /// removes every mark older than [clearAfter] (M-2: another account's
  /// too; in the background, so a home without a trip is never held up).
  static FutureOr<DatingHome> onHome(String account, DatingHome home) {
    if (home.trip?.kind == DatingTripKind.sameGender) {
      return _sameGender(account, home);
    }
    unawaited(_expire());
    return home;
  }

  static Future<DatingHome> _sameGender(String account, DatingHome home) async {
    DatingTripMark? mark;
    try {
      final epoch = _epoch;
      mark = await markFor(account);
      if (epoch != _epoch) {
        // A wipe while it was read: the old answer is gone.
        mark = null;
      } else if (mark != null) {
        _marks?[account] = DatingTripMark(show: mark.show, lastSeen: _now());
        unawaited(_save(epoch));
      }
    } catch (_) {
      mark = null;
    }
    return home.withTrip(
      DatingTrip(
        kind: DatingTripKind.sameGender,
        note: mark == null,
        showHere: mark?.show ?? false,
      ),
    );
  }

  static Future<void> _expire() async {
    try {
      final epoch = _epoch;
      final marks = await _load();
      if (epoch != _epoch || !_prune(marks)) return;
      await _save(epoch);
    } catch (_) {
      // Tried again on the next home.
    }
  }

  /// The device wipe (quick exit, sign-out): every account's mark, from
  /// memory at once, and the keystore's delete sent in the same turn, so
  /// both happen before quick exit's decoy (fix round 1, M-5). Final
  /// client fix (M-1): on iOS a write already sent may still land after
  /// that delete (the plugin's queue is concurrent), so a second delete
  /// goes through the queue, after every keystore call already sent, and
  /// the wipe waits for it (within its entry's bound; the queued delete
  /// still runs after that). Any later write sees the new epoch and writes
  /// nothing. If the process dies before the keystore has the delete on
  /// disk, the mark is read again on the next start, and is no answer
  /// once 7 days old or dated ahead (I-1).
  static Future<void> clear() async {
    _epoch++;
    _loading = null;
    _marks = <String, DatingTripMark>{};
    final now = _delete();
    final queued = _enqueue(_delete);
    await now;
    await queued;
  }

  static Future<void> _delete() async {
    try {
      await storage.delete(key: key);
    } catch (_) {
      // Memory is clear; the keystore is tried again on the next wipe.
    }
  }
}

/// Spec 2 W8b (R-T5-1; Task 5 review carry c): a hiding read's parameters
/// with this phone's "Show it on this phone anyway" for the signed-in
/// account ([show]), always as an explicit boolean in the RPC's body
/// (never left out, never in a URL); false when it can't be read.
Future<Map<String, dynamic>> datingShowSameGender(
  Future<bool> Function()? show, [
  Map<String, dynamic>? params,
]) async {
  var shown = false;
  try {
    shown = show != null && await show();
  } catch (_) {
    shown = false;
  }
  return {...?params, 'p_show_same_gender': shown};
}
