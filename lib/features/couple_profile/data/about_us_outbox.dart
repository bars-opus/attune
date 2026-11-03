import 'dart:convert';

import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// About us answers given offline, per account and per target, replayed
/// later (spec §3.8 "offline edits queue and replay (last write wins,
/// attributed at replay)", §3.14). One key per account,
/// `attune.flow.<uid>.about_us_outbox`, a JSON map from the target's wire
/// (a relationship id or `draft`) to its answers in the order they were
/// given, each `{patch, attempts}` (B3 fix round 2, NM-1: each answer on
/// its own, so a refusal of one never takes another with it). Wiped at
/// sign-out for every account on the phone (device wipe
/// `spec1.about_us_outbox`).
///
/// Shared phones (preflight F-1): an outbox belongs to one account and is
/// never cached for the app run (aboutUsOutboxProvider builds one for the
/// account signed in at each use). [currentUserId], when given, is read
/// before each replayed send, so a session that ends part-way (another
/// account signs in) leaves the rest queued for its own account and never
/// sends it as the next one.
class AboutUsOutbox {
  AboutUsOutbox(
    this._prefs, {
    required this.userId,
    String? Function()? currentUserId,
  }) : _currentUserId = currentUserId;

  final SharedPreferences _prefs;
  final String userId;
  final String? Function()? _currentUserId;

  /// Still this outbox's account (always true without [_currentUserId]).
  bool get _signedIn {
    final read = _currentUserId;
    return read == null || read() == userId;
  }

  /// A replay that keeps failing for a reason other than a refusal is
  /// dropped after this many tries, so a queue can't grow forever.
  static const maxAttempts = 5;

  static String keyFor(String userId) => 'attune.flow.$userId.about_us_outbox';

  static bool isOutboxKey(String key) =>
      key.startsWith('attune.flow.') && key.endsWith('.about_us_outbox');

  String get _key => keyFor(userId);

  /// Batch-3 fix round 1 (ruling I-3, D20): what is stored on the phone
  /// names no Dating, in a key or a value. AU1's stage is kept as a neutral
  /// code and the couple's own words as hex (UTF-8), both mapped back on
  /// read; the server is sent its own values.
  static const _stageCodes = {
    'dating': 's1',
    'engaged': 's2',
    'married': 's3',
    'other': 's4',
  };

  static Map<String, Object?> _encode(Map<String, Object?> patch) => {
    for (final MapEntry(:key, :value) in patch.entries)
      key:
          key == 'stage' && value is String
              ? _stageCodes[value] ?? value
              : key == 'stage_words' && value is String
              ? _hex(utf8.encode(value))
              : value,
  };

  static Map<String, Object?> _decode(Map<String, Object?> patch) => {
    for (final MapEntry(:key, :value) in patch.entries)
      key:
          key == 'stage' && value is String
              ? _stageWire(value)
              : key == 'stage_words' && value is String
              ? _unhex(value)
              : value,
  };

  static String _stageWire(String code) {
    for (final MapEntry(key: wire, value: stored) in _stageCodes.entries) {
      if (stored == code) return wire;
    }
    return code;
  }

  static String _hex(List<int> bytes) =>
      [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

  static String? _unhex(String text) {
    if (text.length.isOdd) return null;
    try {
      return utf8.decode([
        for (var i = 0; i < text.length; i += 2)
          int.parse(text.substring(i, i + 2), radix: 16),
      ]);
    } catch (_) {
      return null;
    }
  }

  /// At most this many answers are kept per target; past it the two
  /// oldest are joined (an AU1-AU6 run is six).
  static const maxQueued = 32;

  static Map<String, Object?>? _entryFrom(Object? raw) {
    if (raw is! Map) return null;
    return {
      for (final MapEntry(:key, :value) in raw.entries)
        key as String:
            key == 'patch' && value is Map
                ? _decode(Map<String, Object?>.from(value))
                : value,
    };
  }

  Map<String, List<Map<String, Object?>>> _read() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return {};
      return {
        for (final MapEntry(:key, :value) in json.entries)
          if (key is String && value is List)
            key: [
              for (final item in value)
                if (_entryFrom(item) case final entry?) entry,
            ],
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _write(Map<String, List<Map<String, Object?>>> entries) {
    entries.removeWhere((_, list) => list.isEmpty);
    return entries.isEmpty
        ? _prefs.remove(_key)
        : _prefs.setString(
          _key,
          jsonEncode({
            for (final MapEntry(key: wire, value: list) in entries.entries)
              wire: [
                for (final entry in list)
                  {
                    for (final MapEntry(:key, :value) in entry.entries)
                      key:
                          key == 'patch' && value is Map
                              ? _encode(Map<String, Object?>.from(value))
                              : value,
                  },
              ],
          }),
        );
  }

  static String _patchJson(Map<String, Object?> entry) =>
      jsonEncode(entry['patch']);

  /// The answers still owed for [target], oldest first.
  List<AboutUsPatch> pendingPatches(AboutUsTarget target) => [
    for (final entry in _read()[target.wire] ?? const [])
      if (AboutUsPatch.fromJson(entry['patch']) case final patch?) patch,
  ];

  /// What is still owed for [target] taken together (the last answer's
  /// keys win), or null: what a screen shows until it is sent.
  AboutUsPatch? pending(AboutUsTarget target) {
    AboutUsPatch? owed;
    for (final patch in pendingPatches(target)) {
      owed = owed?.merge(patch) ?? patch;
    }
    return owed;
  }

  /// Queues [patch] for [target] after anything already queued, as its own
  /// answer (NM-1). An answer that replaces every key of the last one
  /// takes its place: replaying both would end the same way.
  Future<void> enqueue(AboutUsTarget target, AboutUsPatch patch) async {
    final entries = _read();
    final list = entries[target.wire] ?? [];
    final last =
        list.isEmpty ? null : AboutUsPatch.fromJson(list.last['patch']);
    if (last != null &&
        patch.values.keys.toSet().containsAll(last.values.keys)) {
      list.removeLast();
    }
    list.add({'patch': patch.values, 'attempts': 0});
    while (list.length > maxQueued) {
      final first = AboutUsPatch.fromJson(list.removeAt(0)['patch']);
      final second = AboutUsPatch.fromJson(list[0]['patch']);
      if (first != null && second != null) {
        list[0] = {'patch': first.merge(second).values, 'attempts': 0};
      }
    }
    entries[target.wire] = list;
    await _write(entries);
  }

  Future<void> remove(AboutUsTarget target) async {
    final entries = _read()..remove(target.wire);
    await _write(entries);
  }

  /// The entry kept after a failed send: a try is counted only when the
  /// server answered (I-2: being offline, or a server that is down or
  /// busy, never uses one up).
  static Map<String, Object?>? _retry(
    Map<String, Object?> entry,
    AboutUsPatch patch, {
    required bool counts,
  }) {
    final attempts = ((entry['attempts'] as int?) ?? 0) + (counts ? 1 : 0);
    if (attempts >= maxAttempts) {
      debugPrint('[about-us] queued answer dropped after $attempts tries');
      return null;
    }
    return {'patch': patch.values, 'attempts': attempts};
  }

  /// Ruling I-4 (amends F-2): a draft answer refused because the invite
  /// was accepted meanwhile goes to the shared profile, filling only the
  /// fields nobody has answered there (as the draft adoption at accept
  /// does). False when the account changed part-way (kept, untried).
  Future<bool> _reroute(
    CoupleProfileService service,
    AboutUsPatch patch,
    Future<String?> Function() linkedRelationshipId,
  ) async {
    final String? relationshipId;
    try {
      relationshipId = await linkedRelationshipId();
    } on AboutUsOffline {
      rethrow;
    } catch (error) {
      throw AboutUsOffline(reachedServer: !isAboutUsOutage(error));
    }
    // W5 final review NM-4: a session that ended during the lookup reads
    // no link; that is not "no link", so the answers stay, untried.
    if (!_signedIn) return false;
    if (relationshipId == null) {
      debugPrint('[about-us] queued draft answer dropped: no link');
      return true;
    }
    if (!_signedIn) return false;
    final shared = AboutUsTarget.shared(relationshipId);
    final fill = patch.onlyUnsetIn(await service.fetch(shared));
    if (fill == null) {
      debugPrint('[about-us] queued draft answer dropped: already answered');
      return true;
    }
    if (!_signedIn) return false;
    await service.update(shared, fill);
    return true;
  }

  /// Replays [target]'s queued answers, oldest first, each on its own
  /// (NI-1: the server checks the row each one leaves, so only an answer
  /// that is itself refused goes). Sent: removed. Refused: dropped, it
  /// can't succeed; a draft answer refused because the invite was accepted
  /// is re-routed to the shared profile when [linkedRelationshipId] finds
  /// the link (I-4). Not sent (offline, or a try counted): kept, and the
  /// ones after it wait behind it, so the order holds. Another account
  /// signed in part-way: the rest is kept, untried (F-1). Never throws.
  Future<AboutUsReplay> flushTarget(
    CoupleProfileService service,
    AboutUsTarget target, {
    Future<String?> Function()? linkedRelationshipId,
  }) async {
    final sent = _read()[target.wire];
    if (sent == null || sent.isEmpty) return AboutUsReplay.settled;
    var done = 0;
    Map<String, Object?>? retried;
    var result = AboutUsReplay.settled;
    // Fix round 4 (NM-3): set once the merged re-route was refused; the
    // rest go to the shared profile one by one.
    var eachAlone = false;
    for (final (index, entry) in sent.indexed) {
      if (!_signedIn) {
        debugPrint('[about-us] replay stopped: the account changed');
        result = AboutUsReplay.stopped;
        break;
      }
      final patch = AboutUsPatch.fromJson(entry['patch']);
      if (patch == null) {
        done++;
        continue;
      }
      try {
        if (eachAlone) {
          if (!await _reroute(service, patch, linkedRelationshipId!)) {
            debugPrint('[about-us] replay stopped: the account changed');
            result = AboutUsReplay.stopped;
            break;
          }
          done++;
          continue;
        }
        try {
          await service.update(target, patch);
        } on AboutUsRefused catch (refused) {
          if (!target.isDraft ||
              refused.reason != AboutUsRefusal.notFound ||
              linkedRelationshipId == null) {
            rethrow;
          }
          // Fix round 3 (NI-2): the draft is gone, so this answer and every
          // later one for it go to the shared profile together, as one
          // answer (the latest of each wins), filling only what nobody has
          // answered there. One by one, the first would fill a field and
          // the next, which corrects it or completes it, would find it
          // answered and go.
          var together = patch;
          for (final later in sent.skip(index + 1)) {
            final next = AboutUsPatch.fromJson(later['patch']);
            if (next != null) together = together.merge(next);
          }
          try {
            if (!await _reroute(service, together, linkedRelationshipId)) {
              debugPrint('[about-us] replay stopped: the account changed');
              result = AboutUsReplay.stopped;
              break;
            }
            done = sent.length;
            break;
          } on AboutUsRefused catch (refused) {
            // Fix round 4 (NM-3): the merge can't be taken, so each answer
            // goes on its own, and a refusal drops only the one refused.
            // The draft is gone, so this one and the rest are re-routed.
            debugPrint(
              '[about-us] merged re-route refused: ${refused.reason.name}; '
              'one by one',
            );
            eachAlone = true;
            if (!await _reroute(service, patch, linkedRelationshipId)) {
              debugPrint('[about-us] replay stopped: the account changed');
              result = AboutUsReplay.stopped;
              break;
            }
          }
        }
        done++;
      } on AboutUsRefused catch (refused) {
        debugPrint('[about-us] queued answer refused: ${refused.reason.name}');
        done++;
      } catch (error) {
        retried = _retry(
          entry,
          patch,
          counts: error is! AboutUsOffline || error.reachedServer,
        );
        if (retried == null) {
          done++;
          continue;
        }
        result = AboutUsReplay.kept;
        break;
      }
    }
    await _settle(target.wire, sent, done, retried);
    return result;
  }

  /// Writes back what a replay of [sent] did: its first [done] answers
  /// are owed no more, and the next one, if [retried], has its tries
  /// counted. Only while the queue still starts with them: an answer
  /// queued or replaced meanwhile is kept as it is.
  Future<void> _settle(
    String wire,
    List<Map<String, Object?>> sent,
    int done,
    Map<String, Object?>? retried,
  ) async {
    try {
      final latest = _read();
      final list = latest[wire];
      if (list == null) return;
      var i = 0;
      while (i < done &&
          list.isNotEmpty &&
          _patchJson(list.first) == _patchJson(sent[i])) {
        list.removeAt(0);
        i++;
      }
      if (i == done &&
          retried != null &&
          list.isNotEmpty &&
          _patchJson(list.first) == _patchJson(sent[done])) {
        list[0] = retried;
      }
      await _write(latest);
    } catch (error) {
      debugPrint('[about-us] outbox write failed: ${error.runtimeType}');
    }
  }

  /// Replays every target's queued answers ([flushTarget]), the draft's
  /// first (fix round 5: they are older than any shared answer, so a
  /// re-routed draft answer never overwrites a newer shared one; while
  /// one is still owed, the rest wait behind it). Never throws.
  Future<void> flush(
    CoupleProfileService service, {
    Future<String?> Function()? linkedRelationshipId,
  }) async {
    const draft = AboutUsTarget.draft();
    final wires = _read().keys.toList();
    for (final wire in [
      ...wires.where((wire) => wire == draft.wire),
      ...wires.where((wire) => wire != draft.wire),
    ]) {
      final result = await flushTarget(
        service,
        AboutUsTarget.fromWire(wire),
        linkedRelationshipId: linkedRelationshipId,
      );
      if (result == AboutUsReplay.stopped) break;
      if (wire == draft.wire && result == AboutUsReplay.kept) break;
    }
  }
}

/// W5 final review M-4: [userId]'s queued draft answers, dropped when the
/// account switches to Dating (the server drops the draft itself in
/// set_user_path_internal). Never throws; writes no key or value naming
/// Dating.
Future<void> clearAboutUsDraftQueue(
  SharedPreferences prefs,
  String userId,
) async {
  try {
    await AboutUsOutbox(
      prefs,
      userId: userId,
    ).remove(const AboutUsTarget.draft());
  } catch (error) {
    debugPrint('[about-us] draft queue not cleared: ${error.runtimeType}');
  }
}

/// What a replay of one target did: every answer settled (sent, refused or
/// dropped), one still owed (offline: the rest wait behind it), or stopped
/// because another account signed in.
enum AboutUsReplay { settled, kept, stopped }
