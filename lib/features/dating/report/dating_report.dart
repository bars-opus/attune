// Spec 2 W7a (§3.7, §6.2, §6.3): a report's categories and answer, the
// restriction its person sees, and the appeal. Every answer is a fixed
// code the app maps to its own copy; a server's text is never shown.
import 'package:attune/i10n/generated/app_localizations.dart';

/// §3.7's 14 categories, in the sheet's order, with their priority (0 is
/// P0). "Also block" starts on for P0 to P2.
enum DatingReportCategory {
  underageRisk('underage_risk', 0),
  csam('csam', 0),
  childSafety('child_safety', 0),
  threatToLife('threat_to_life', 0),
  sextortion('sextortion', 1),
  romanceScam('romance_scam', 1),
  threats('threats', 1),
  entrapment('entrapment', 1),
  harassment('harassment', 2),
  explicitContent('explicit_content', 2),
  impersonation('impersonation', 2),
  hidingRelationship('hiding_relationship', 2),
  spam('spam', 3),
  other('other', 3);

  const DatingReportCategory(this.wire, this.priority);

  final String wire;
  final int priority;

  bool get blockByDefault => priority <= 2;

  static DatingReportCategory? fromWire(Object? wire) {
    for (final c in values) {
      if (c.wire == wire) return c;
    }
    return null;
  }
}

/// §3.7's label, as the person who reports reads it.
String datingReportLabel(AppLocalizations loc, DatingReportCategory c) =>
    switch (c) {
      DatingReportCategory.underageRisk => loc.dating_reportUnderage,
      DatingReportCategory.csam => loc.dating_reportCsam,
      DatingReportCategory.childSafety => loc.dating_reportChildSafety,
      DatingReportCategory.threatToLife => loc.dating_reportThreatToLife,
      DatingReportCategory.sextortion => loc.dating_reportSextortion,
      DatingReportCategory.romanceScam => loc.dating_reportMoney,
      DatingReportCategory.threats => loc.dating_reportThreats,
      DatingReportCategory.entrapment => loc.dating_reportEntrapment,
      DatingReportCategory.harassment => loc.dating_reportHarassment,
      DatingReportCategory.explicitContent => loc.dating_reportExplicit,
      DatingReportCategory.impersonation => loc.dating_reportImpersonation,
      DatingReportCategory.hidingRelationship => loc.dating_reportMarried,
      DatingReportCategory.spam => loc.dating_reportSpam,
      DatingReportCategory.other => loc.dating_reportOther,
    };

/// The codes a report or an appeal answers; anything else is `failed`.
const datingReportReasons = {
  'invalid',
  'report_unavailable',
  'rate_limited',
  'appeal_unavailable',
  'already_appealed',
  'busy',
  'failed',
};

String _fixed(Object? reason) =>
    reason is String && datingReportReasons.contains(reason)
        ? reason
        : 'failed';

DateTime? _time(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toUtc() : null;

/// What a sent report (or an appeal) answers. [testing]: no named
/// moderator reads it yet (§3.7: "In testing, reports go to the test
/// review queue."); [slaHours]: within how many hours at most; [blocked]
/// false: "Also block" was asked and the block didn't go through (Task 1
/// fix round 1, M-1: the server's `"blocked": false`, say the day's block
/// limit or busy; the report itself is in).
class DatingReportAnswer {
  const DatingReportAnswer({
    required this.ok,
    this.reason,
    this.testing = true,
    this.slaHours,
    this.blocked = true,
    this.reviewKnown = true,
  });

  static const busy = DatingReportAnswer(ok: false, reason: 'busy');
  static const failed = DatingReportAnswer(ok: false, reason: 'failed');

  final bool ok;
  final String? reason;
  final bool testing;
  final int? slaHours;
  final bool blocked;

  /// Fix round 1 (M-1): the answer said `review` (a replay whose report
  /// row is gone answers a bare `{ok: true}`): false, the thanks says no
  /// time and never "In testing".
  final bool reviewKnown;

  factory DatingReportAnswer.fromJson(Object? raw) {
    if (raw is! Map) return failed;
    if (raw['ok'] != true) {
      return DatingReportAnswer(ok: false, reason: _fixed(raw['reason']));
    }
    final hours = raw['sla_hours'];
    final review = raw['review'];
    return DatingReportAnswer(
      ok: true,
      testing: review != 'staffed',
      reviewKnown: review == 'staffed' || review == 'testing',
      slaHours: hours is int && hours > 0 ? hours : null,
      blocked: raw['blocked'] != false,
    );
  }
}

enum DatingRestrictionType { hold, ageReview, suspended }

/// W7 final client fix (I-3): where a restriction came from (the server's
/// `source`); null is one this app doesn't know, read as the plain case.
enum DatingRestrictionSource {
  /// A P0 report's interim hold: the spec's "not a decision yet" line.
  p0Interim('p0_interim'),
  moderator('moderator'),
  csam('csam'),
  carried('carried'),

  /// A moderator's Ask for ID: the age check has its reference code.
  idCheck('id_check'),
  ageAssurance('age_assurance');

  const DatingRestrictionSource(this.wire);

  final String wire;

  static DatingRestrictionSource? fromWire(Object? wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }
}

/// I-6: an ID-check reference code as the server makes it (8 characters
/// from 23456789ABCDEFGHJKMNPQRSTUVWXYZ); anything else is no code, so
/// nothing but the code ever reaches a mail subject.
final _idCheckCode = RegExp(r'^[2-9A-HJKMNP-Z]{8}$');

enum DatingAppealState { open, accepted, rejected }

class DatingAppeal {
  const DatingAppeal({required this.state, this.decidedAt});

  final DatingAppealState state;
  final DateTime? decidedAt;

  static DatingAppeal? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final state = switch (raw['state']) {
      'open' => DatingAppealState.open,
      'accepted' => DatingAppealState.accepted,
      'rejected' => DatingAppealState.rejected,
      _ => null,
    };
    if (state == null) return null;
    return DatingAppeal(state: state, decidedAt: _time(raw['decided_at']));
  }
}

/// §3.7 the restriction shown: never who reported, what they wrote or the
/// evidence (the server sends none of it).
class DatingRestriction {
  const DatingRestriction({
    required this.id,
    required this.type,
    this.endsAt,
    this.category,
    this.canAppeal = false,
    this.appeal,
    this.source,
    this.idCheckCode,
  });

  final String id;
  final DatingRestrictionType type;

  /// I-3: the server's source (null: unknown, so the plain hold line).
  final DatingRestrictionSource? source;

  /// I-6: the age check's reference code (Ask for ID's only), for the
  /// person's email to support; null when there is none.
  final String? idCheckCode;

  /// I-3: the spec's interim line ("This isn't a decision yet. We aim to
  /// finish within 24 hours.") only for a P0 report's own interim hold,
  /// and never once an appeal of it was rejected.
  bool get interimHold =>
      type == DatingRestrictionType.hold &&
      source == DatingRestrictionSource.p0Interim &&
      appeal?.state != DatingAppealState.rejected;

  /// Suspended only: null is closed for good.
  final DateTime? endsAt;
  final DatingReportCategory? category;
  final bool canAppeal;
  final DatingAppeal? appeal;

  static DatingRestriction? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    final type = switch (raw['type']) {
      'hold' => DatingRestrictionType.hold,
      'age_review' => DatingRestrictionType.ageReview,
      'suspended' => DatingRestrictionType.suspended,
      _ => null,
    };
    if (type == null) return null;
    final source = DatingRestrictionSource.fromWire(raw['source']);
    final code = raw['id_check_code'];
    return DatingRestriction(
      id: raw['id'] as String,
      type: type,
      endsAt: _time(raw['ends_at']),
      category: DatingReportCategory.fromWire(raw['category']),
      canAppeal: raw['can_appeal'] == true,
      appeal: DatingAppeal.fromJson(raw['appeal']),
      source: source,
      idCheckCode:
          type == DatingRestrictionType.ageReview &&
                  source == DatingRestrictionSource.idCheck &&
                  code is String &&
                  _idCheckCode.hasMatch(code)
              ? code
              : null,
    );
  }
}

/// get_my_dating_restriction's answer.
class DatingRestrictionRead {
  const DatingRestrictionRead({
    required this.ok,
    this.reason,
    this.restriction,
    this.appealAccepted = false,
    this.staffed = false,
  });

  static const none = DatingRestrictionRead(ok: true);
  static const busy = DatingRestrictionRead(ok: false, reason: 'busy');
  static const failed = DatingRestrictionRead(ok: false, reason: 'failed');

  final bool ok;
  final String? reason;
  final DatingRestriction? restriction;
  final bool appealAccepted;

  /// Spec 2 W8b (W7 carry M-6): a person reviews now (the server's
  /// `review: staffed`). Read from the server, anything else (testing, or
  /// no answer) is false and the screen makes no review-time promise.
  /// Fix round 1 (M-2): a read built in code is not staffed unless it says
  /// so (the safe default: no promise).
  final bool staffed;

  /// Task 2 fix round: `{ok: false, reason: busy}` is busy (retryable);
  /// any other refusal is failed.
  factory DatingRestrictionRead.fromJson(Object? raw) {
    if (raw is! Map) return failed;
    if (raw['ok'] != true) return raw['reason'] == 'busy' ? busy : failed;
    return DatingRestrictionRead(
      ok: true,
      restriction: DatingRestriction.fromJson(raw['restriction']),
      appealAccepted: raw['appeal_accepted'] == true,
      staffed: raw['review'] == 'staffed',
    );
  }
}

/// Where a report is about: a conversation, or a card on Today.
sealed class DatingReportTarget {
  const DatingReportTarget(this.id);

  final String id;
}

class DatingReportMatch extends DatingReportTarget {
  const DatingReportMatch(super.id);
}

class DatingReportCard extends DatingReportTarget {
  const DatingReportCard(super.id);
}

/// What the report sheet did, for the screen that opened it.
class DatingReportOutcome {
  const DatingReportOutcome({
    required this.blocked,
    this.alsoBlock = false,
    this.category,
    this.paused = false,
  });

  /// The person asked to block too and the block went through (the
  /// report's answer was ok, without `"blocked": false`).
  final bool blocked;

  /// "Also block" was on when the report was sent.
  final bool alsoBlock;

  /// What was reported.
  final DatingReportCategory? category;

  /// After a money report the person paused Dating from the sheet.
  final bool paused;

  /// Fix round 1 (I-2; R-63, §6.2): a P0 report from a card takes the card
  /// away (the server invalidates the introduction and marks the pair).
  /// Final client fix (I-1): whatever "Also block" did, as W7c's server
  /// does; a block that went through folds the card as a block.
  bool get takesCardAway => category?.priority == 0;
}
