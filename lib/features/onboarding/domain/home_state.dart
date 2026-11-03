import 'package:flutter/foundation.dart';

/// The three ways to use Attune (Spec 1 §1.1), as `users.path` stores them.
enum AppPath {
  relationship('relationship'),
  dating('dating'),
  justMe('just_me');

  const AppPath(this.wire);

  final String wire;

  static AppPath? fromWire(Object? value) {
    for (final path in values) {
      if (path.wire == value) return path;
    }
    return null;
  }
}

/// Tab 2's layout: Chat on the Relationship path, Me on Dating and Just for
/// me (Q6). The only path-derived value the phone may keep (D20).
enum AppTab {
  chat('chat'),
  me('me');

  const AppTab(this.wire);

  final String wire;

  /// Anything but `chat` is Me: an unknown value never opens Chat.
  static AppTab fromWire(Object? value) => value == 'chat' ? chat : me;

  /// The layout a path implies, for a locally made choice before the server
  /// answers (W3a). The server's `tab` always wins once it arrives.
  static AppTab forPath(AppPath path) =>
      path == AppPath.relationship ? chat : me;
}

/// The latest relationship, as get_my_home_state() reads it (spec §4.3).
enum LinkState {
  none('none'),
  pending('pending'),
  linked('linked'),
  paused('paused'),
  endedWindow('ended_window'),
  afterEnding('after_ending');

  const LinkState(this.wire);

  final String wire;

  static LinkState fromWire(Object? value) {
    for (final state in values) {
      if (state.wire == value) return state;
    }
    return none;
  }
}

/// What an account still lacks, in the order the gate asks (spec §3.15).
enum HomeNeed {
  consent('consent'),
  birthDate('birth_date'),
  name('name'),
  path('path'),

  /// A need this build doesn't know (a later wave added it). It keeps the
  /// account incomplete, so an older build never skips a required step
  /// (final review M-5); the gate sends such a person to update the app.
  unknown('unknown');

  const HomeNeed(this.wire);

  final String wire;

  /// Any value this build doesn't recognise reads as [unknown], never as
  /// nothing: a need fails closed.
  static HomeNeed fromWire(Object? value) {
    for (final need in values) {
      if (need.wire == value) return need;
    }
    return unknown;
  }

  /// The needs in server order, an unrecognised one as [unknown].
  static List<HomeNeed> listFromWire(Object? value) => [
    if (value is List)
      for (final item in value) fromWire(item),
  ];
}

/// Which hold an account is under (Spec 1 §4.2 `account_holds`, W6a), as
/// get_my_home_state() names it in `hold_kind`.
enum HoldKind {
  ageReview('age_review'),
  safetyReview('safety_review'),
  recoveryHold('recovery_hold'),

  /// A kind this build doesn't know (a later spec added it). Never an age
  /// hold: get_my_home_state and the access-token hook both name
  /// `age_review` first, so any new age-type kind must reach the app as
  /// `age_review` (and `account_review:age`), never under a new name.
  unknown('unknown');

  const HoldKind(this.wire);

  final String wire;

  /// Null when the server named no kind (no hold, or a server or cache
  /// from before W6a) or sent something that isn't a name (fix round 1,
  /// I#1: malformed data still blocks, as no kind does); a name this build
  /// doesn't know is [unknown].
  static HoldKind? fromWire(Object? value) {
    if (value is! String) return null;
    for (final kind in values) {
      if (kind != unknown && kind.wire == value) return kind;
    }
    return unknown;
  }
}

/// Whether a hold also blocks this phone (X1's 30-day block; rulings N-2,
/// F-8; W3 batch 5 carry; fix round 1, I#1): an age hold does, and so does
/// a hold that names no kind (an older server or cache, where every hold
/// was an age hold; a failed read; a malformed kind). A safety or recovery
/// hold, or a kind this build doesn't know (never an age hold, see
/// [HoldKind.unknown]), shows H1 and never blocks the phone: the next
/// person on it may be someone else entirely.
bool holdBlocksDevice(HoldKind? kind) =>
    kind == null || kind == HoldKind.ageReview;

@immutable
class HomeLink {
  const HomeLink({
    required this.state,
    this.relationshipId,
    this.partnerFirstName,
    this.inviteExpiresAt,
    this.windowEndsAt,
  });

  static const none = HomeLink(state: LinkState.none);

  final LinkState state;
  final String? relationshipId;

  /// A first name only, never a phone number (the server guards this).
  final String? partnerFirstName;
  final DateTime? inviteExpiresAt;
  final DateTime? windowEndsAt;

  factory HomeLink.fromJson(Object? json) {
    if (json is! Map) return none;
    DateTime? at(Object? value) =>
        value is String ? DateTime.tryParse(value) : null;
    return HomeLink(
      state: LinkState.fromWire(json['state']),
      relationshipId: json['relationship_id'] as String?,
      partnerFirstName: json['partner_first_name'] as String?,
      inviteExpiresAt: at(json['invite_expires_at']),
      windowEndsAt: at(json['window_ends_at']),
    );
  }
}

/// The Dating summary from the server seam private.dating_home_summary.
/// Held in memory only, never cached on the phone (D20).
@immutable
class DatingSummary {
  const DatingSummary({required this.enabled, required this.enrolled});

  static const off = DatingSummary(enabled: false, enrolled: false);

  final bool enabled;
  final bool enrolled;

  factory DatingSummary.fromJson(Object? json) =>
      json is Map
          ? DatingSummary(
            enabled: json['enabled'] == true,
            enrolled: json['enrolled'] == true,
          )
          : off;
}

/// One answer from get_my_home_state() (spec §4.3 W1b).
@immutable
class HomeState {
  const HomeState({
    required this.hasAccount,
    required this.path,
    required this.tab,
    required this.pathPrevious,
    required this.needs,
    required this.hold,
    required this.eulaVersion,
    required this.dating,
    required this.link,
    this.holdKind,
  });

  final bool hasAccount;
  final AppPath? path;
  final AppTab tab;
  final AppPath? pathPrevious;
  final List<HomeNeed> needs;

  /// An unresolved account hold: the app shows H1 and nothing else.
  final bool hold;

  /// Which hold (W6a); null when the server named none.
  final HoldKind? holdKind;
  final String? eulaVersion;
  final DatingSummary dating;
  final HomeLink link;

  /// Onboarding is complete when nothing is missing (W3a's v2 gate).
  bool get isComplete => hasAccount && needs.isEmpty;

  factory HomeState.fromJson(Map<String, dynamic> json) => HomeState(
    hasAccount: json['has_account'] == true,
    path: AppPath.fromWire(json['path']),
    tab: AppTab.fromWire(json['tab']),
    pathPrevious: AppPath.fromWire(json['path_previous']),
    needs: HomeNeed.listFromWire(json['needs']),
    hold: json['hold'] == true,
    holdKind: HoldKind.fromWire(json['hold_kind']),
    eulaVersion: json['eula_version'] as String?,
    dating: DatingSummary.fromJson(json['dating']),
    link: HomeLink.fromJson(json['link']),
  );
}
