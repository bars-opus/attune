// Spec 2 W9 (§3.9, §4.4; S-5, S-6, I-12, C-4): "Become a couple on Attune"
// as the server sends it, and its calls. The chat side (the link page's
// read, asking, the second Yes, Not right now, taking it back) goes
// through the Dating RPC client with this phone's "Show it on this phone
// anyway" (R-T5-1), as every Dating read. The couple side (the match date
// for About us, How we met, the Relationship home's card and its dismiss)
// is read by the relationship's members only, on the app's own client with
// no install id (final client fix I-1; couple_link_couple_side.dart). Every
// field is read defensively; a server's text is never shown; memory only
// (D20).
import 'package:attune/core/flags/couple_link_couple_side.dart';
import 'package:attune/core/flags/couple_link_flag.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/device/trip_phone.dart';
import 'package:attune/features/dating/domain/services/dating_feature_flags.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The couple link's fixed refusals (any other answer is `failed`).
const datingLinkReasons = {
  'invalid',
  'unavailable',
  'reverify_device',
  'match_unavailable',
  'request_unavailable',
  'closed',
  'not_yet',
  'not_ready',
  'asked',
  'asked_you',
  'linked',
  'busy',
};

String _fixed(Object? reason) =>
    reason is String && datingLinkReasons.contains(reason) ? reason : 'failed';

/// What the chat shows of the link, for this side (the server's `link`).
enum DatingLinkState {
  /// Either has said We met: this side may ask.
  none,

  /// This side asked; waiting for the other.
  asked,

  /// The other side asked: the card and the sheet.
  askedYou,

  /// The other side said Not right now to this side's request (14 days).
  notReady,

  /// The couple linked (this conversation ended with it).
  linked,
}

class DatingLink {
  const DatingLink({required this.state, this.requestId, this.moment = false});

  final DatingLinkState state;
  final String? requestId;

  /// [DatingLinkState.linked]: "You decided together." is still to show.
  final bool moment;

  static DatingLink? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final state = switch (raw['state']) {
      'none' => DatingLinkState.none,
      'asked' => DatingLinkState.asked,
      'asked_you' => DatingLinkState.askedYou,
      'not_ready' => DatingLinkState.notReady,
      'linked' => DatingLinkState.linked,
      _ => null,
    };
    if (state == null) return null;
    final id = raw['request_id'];
    final requestId = id is String ? id : null;
    if ((state == DatingLinkState.asked || state == DatingLinkState.askedYou) &&
        requestId == null) {
      return null;
    }
    return DatingLink(
      state: state,
      requestId: requestId,
      moment: raw['moment'] == true,
    );
  }
}

/// The link page's read: the other person's first name and the link.
class DatingLinkPage {
  const DatingLinkPage({
    this.ok = false,
    this.reason,
    this.displayName = '',
    this.link,
  });

  static const failed = DatingLinkPage(reason: 'failed');
  static const busy = DatingLinkPage(reason: 'busy');

  final bool ok;
  final String? reason;
  final String displayName;
  final DatingLink? link;

  factory DatingLinkPage.fromJson(Object? raw) {
    if (raw is! Map) return failed;
    if (raw['ok'] != true) return DatingLinkPage(reason: _fixed(raw['reason']));
    final name = raw['display_name'];
    return DatingLinkPage(
      ok: true,
      displayName: name is String ? name.trim() : '',
      link: DatingLink.fromJson(raw['link']),
    );
  }
}

/// An answer of asking, the second Yes, Not right now or taking it back.
class DatingLinkAnswer {
  const DatingLinkAnswer({
    required this.ok,
    this.reason,
    this.requestId,
    this.relationshipId,
  });

  static const failed = DatingLinkAnswer(ok: false, reason: 'failed');
  static const busy = DatingLinkAnswer(ok: false, reason: 'busy');

  final bool ok;
  final String? reason;
  final String? requestId;
  final String? relationshipId;

  factory DatingLinkAnswer.fromJson(Object? raw) {
    if (raw is! Map) return failed;
    if (raw['ok'] != true) {
      return DatingLinkAnswer(ok: false, reason: _fixed(raw['reason']));
    }
    String? text(String key) => raw[key] is String ? raw[key] as String : null;
    return DatingLinkAnswer(
      ok: true,
      requestId: text('request_id'),
      relationshipId: text('relationship_id'),
    );
  }
}

/// What the Relationship home's `link_offer` card shows (C-4).
enum DatingPostLinkOffer {
  none,

  /// "You decided together.", once.
  linked,

  /// "Delete your Dating profile and preferences?", from 30 days on.
  delete,
}

/// One message of the How we met card, as both saw it.
class DatingHowWeMetItem {
  const DatingHowWeMetItem({
    required this.mine,
    required this.text,
    required this.at,
    this.questionId,
  });

  final bool mine;
  final String text;
  final DateTime at;
  final String? questionId;

  static DatingHowWeMetItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text'];
    final at =
        raw['at'] is String ? DateTime.tryParse(raw['at'] as String) : null;
    if (text is! String || at == null) return null;
    final q = raw['question_id'];
    return DatingHowWeMetItem(
      mine: raw['mine'] == true,
      text: text,
      at: at.toUtc(),
      questionId: q is String ? q : null,
    );
  }
}

abstract class DatingLinkGateway {
  /// The link page's read of [matchId].
  Future<DatingLinkPage> page(String matchId);

  /// Step 1: this side's Yes ("Ask {Name}").
  Future<DatingLinkAnswer> ask(
    String key,
    String matchId, {
    required bool keep,
  });

  /// Step 3: the second Yes ("Yes, let's").
  Future<DatingLinkAnswer> confirm(
    String key,
    String requestId, {
    required bool keep,
  });

  /// Step 2: "Not right now".
  Future<DatingLinkAnswer> decline(String requestId);

  /// The asker takes it back.
  Future<DatingLinkAnswer> cancel(String requestId);

  /// The match date for About us's chip; null when there is none.
  Future<DateTime?> origin(String relationshipId);

  /// How we met; null when there is no card (or it can't be read).
  Future<List<DatingHowWeMetItem>?> howWeMet(String relationshipId);

  /// The Relationship home's card for the signed-in person.
  Future<DatingPostLinkOffer> offer();

  /// The card answered: [offer] 'linked' (seen) or 'delete' (Keep for now).
  Future<bool> dismiss(DatingPostLinkOffer offer);
}

class DatingLinkRepository implements DatingLinkGateway {
  DatingLinkRepository(
    this._rpcOf, {
    required CoupleLinkCoupleCall couple,
    Future<bool> Function()? showSameGender,
  }) : _couple = couple,
       _showSameGender = showSameGender;

  /// The chat side: Dating's client (with this phone's id), built only when
  /// the chat side calls (final client fix I-1: the couple side never
  /// needs it).
  final DatingRpc Function() _rpcOf;
  DatingRpc get _rpc => _rpcOf();

  /// Final client fix (I-1): the couple side, on the app's client.
  final CoupleLinkCoupleCall _couple;

  /// This phone's "Show it on this phone anyway" for the signed-in account.
  final Future<bool> Function()? _showSameGender;

  Future<bool> _show() async {
    try {
      return await (_showSameGender?.call() ?? Future.value(false));
    } catch (_) {
      return false;
    }
  }

  Future<DatingLinkAnswer> _answer(
    String fn,
    Map<String, dynamic> params,
  ) async {
    try {
      return DatingLinkAnswer.fromJson(await _rpc.call(fn, params));
    } on DatingBusy {
      return DatingLinkAnswer.busy;
    } catch (_) {
      return DatingLinkAnswer.failed;
    }
  }

  @override
  Future<DatingLinkPage> page(String matchId) async {
    try {
      return DatingLinkPage.fromJson(
        await _rpc.call('get_dating_couple_link', {
          'p_match_id': matchId,
          'p_show_same_gender': await _show(),
        }),
      );
    } on DatingBusy {
      return DatingLinkPage.busy;
    } catch (_) {
      return DatingLinkPage.failed;
    }
  }

  @override
  Future<DatingLinkAnswer> ask(
    String key,
    String matchId, {
    required bool keep,
  }) async => _answer('request_dating_couple_link', {
    'p_key': key,
    'p_match_id': matchId,
    'p_keep_messages': keep,
    'p_show_same_gender': await _show(),
  });

  @override
  Future<DatingLinkAnswer> confirm(
    String key,
    String requestId, {
    required bool keep,
  }) async => _answer('confirm_dating_couple_link', {
    'p_key': key,
    'p_request_id': requestId,
    'p_keep_messages': keep,
    'p_show_same_gender': await _show(),
  });

  @override
  Future<DatingLinkAnswer> decline(String requestId) =>
      _answer('decline_dating_couple_link', {'p_request_id': requestId});

  @override
  Future<DatingLinkAnswer> cancel(String requestId) =>
      _answer('cancel_dating_couple_link', {'p_request_id': requestId});

  @override
  Future<DateTime?> origin(String relationshipId) async {
    try {
      final r = await _couple('get_dating_link_origin', {
        'p_relationship_id': relationshipId,
      });
      if (r is! Map || r['ok'] != true || r['matched_at'] is! String) {
        return null;
      }
      return DateTime.tryParse(r['matched_at'] as String)?.toUtc();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<DatingHowWeMetItem>?> howWeMet(String relationshipId) async {
    try {
      final r = await _couple('get_how_we_met', {
        'p_relationship_id': relationshipId,
      });
      if (r is! Map || r['ok'] != true || r['items'] is! List) return null;
      final items = [
        for (final i in (r['items'] as List).map(DatingHowWeMetItem.fromJson))
          if (i != null) i,
      ];
      return items.isEmpty ? null : items;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DatingPostLinkOffer> offer() async {
    try {
      final r = await _couple('get_dating_post_link_offer', {});
      if (r is! Map || r['ok'] != true) return DatingPostLinkOffer.none;
      return switch (r['offer']) {
        'linked' => DatingPostLinkOffer.linked,
        'delete' => DatingPostLinkOffer.delete,
        _ => DatingPostLinkOffer.none,
      };
    } catch (_) {
      return DatingPostLinkOffer.none;
    }
  }

  @override
  Future<bool> dismiss(DatingPostLinkOffer offer) async {
    if (offer == DatingPostLinkOffer.none) return false;
    try {
      final r = await _couple('dismiss_dating_post_link_offer', {
        'p_offer': offer == DatingPostLinkOffer.linked ? 'linked' : 'delete',
      });
      return r is Map && r['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}

final datingLinkGatewayProvider = Provider<DatingLinkGateway>(
  (ref) => DatingLinkRepository(
    () => ref.read(datingRpcProvider),
    couple: ref.watch(coupleLinkCoupleCallProvider),
    // The account signed in at each call (D8).
    showSameGender:
        () => DatingTripPhone.showFor(ref.read(datingAccountProvider)),
  ),
);

/// The controller's ruling (R-W9-16, as amended in Task 5's fix rounds 1
/// and 2): whether dating_couple_link is on, for [account]. ONE
/// get_dating_home() read, on the app's own client with no install id
/// (coupleLinkFlagReadProvider: every couple makes it, Dating or not; it
/// names no other person, so it takes no "Show it on this phone anyway"),
/// kept for the process once it answers; another account reads anew (D8);
/// never re-read on resume once answered (it is not one of
/// FeatureFlagRefresher's flags). A read that fails is off (fail closed);
/// because the home's tabs stay mounted, a failed read is asked again on
/// the next resume or reconnect, and only while it has failed (one that
/// doesn't answer within [kCoupleLinkReadTimeout] has failed). It never
/// reads documentationFlagsProvider: that is the manual's (about ten reads,
/// re-read on every resume), and a Relationship home that watched it made
/// every couple pay for them.
final datingCoupleLinkReadProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, account) async {
      final Object? raw;
      try {
        // Final client fix (M-2): a read that hangs fails, and is retried.
        raw = await ref
            .read(coupleLinkFlagReadProvider)()
            .timeout(kCoupleLinkReadTimeout);
      } catch (_) {
        // Fix round 2 (I-1): read again on the next resume or reconnect.
        final life = AppLifecycleListener(onResume: ref.invalidateSelf);
        ref.onDispose(life.dispose);
        ref.listen<AsyncValue<bool>>(datingOnlineProvider, (previous, next) {
          if (previous?.valueOrNull == false && next.valueOrNull == true) {
            ref.invalidateSelf();
          }
        });
        return false;
      }
      ref.keepAlive();
      return DatingFeatureFlags.flagsFrom(
        raw,
      ).contains(DatingFeatureFlags.coupleLink);
    });

/// Whether this client knows dating_couple_link is on for the signed-in
/// account. Not known (signed out, still reading, a failed read), or off:
/// nothing below asks the server anything.
final datingCoupleLinkOnProvider = Provider.autoDispose<bool>((ref) {
  final account = ref.watch(datingAccountProvider);
  if (account == null) return false;
  return ref.watch(datingCoupleLinkReadProvider(account)).valueOrNull ?? false;
});

/// The Relationship home's card for [account] (null: signed out, none).
final datingPostLinkOfferProvider = FutureProvider.autoDispose
    .family<DatingPostLinkOffer, String?>((ref, account) async {
      if (account == null || !ref.watch(datingCoupleLinkOnProvider)) {
        return DatingPostLinkOffer.none;
      }
      return ref.read(datingLinkGatewayProvider).offer();
    });

/// The match date of [relationshipId], read by a member (I-12).
final datingLinkOriginProvider = FutureProvider.autoDispose
    .family<DateTime?, (String?, String)>((ref, key) async {
      if (key.$1 == null || !ref.watch(datingCoupleLinkOnProvider)) {
        return null;
      }
      return ref.read(datingLinkGatewayProvider).origin(key.$2);
    });

/// How we met of [relationshipId], read by a member.
final datingHowWeMetProvider = FutureProvider.autoDispose
    .family<List<DatingHowWeMetItem>?, (String?, String)>((ref, key) async {
      if (key.$1 == null || !ref.watch(datingCoupleLinkOnProvider)) {
        return null;
      }
      return ref.read(datingLinkGatewayProvider).howWeMet(key.$2);
    });
