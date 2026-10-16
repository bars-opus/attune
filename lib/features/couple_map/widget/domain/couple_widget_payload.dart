// lib/features/couple_map/widget/domain/couple_widget_payload.dart
import 'dart:convert';

import 'package:attune/features/couple_map/widget/domain/couple_widget_config.dart';
import 'package:attune/features/couple_map/widget/domain/geo_point.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/domain/distance_copy.dart';
import 'package:attune/features/location/domain/partner_distance.dart';
import 'package:attune/features/location/domain/reunion.dart';
import 'package:flutter/foundation.dart';

const neutralHeadline = 'Nothing to show yet';

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

int _daysTo(String date, DateTime now) {
  final at = DateTime.tryParse(date);
  return at == null ? -1 : daysUntil(at, now: now);
}

/// What the app writes to the App Group (spec §4.4). No coordinates,
/// places, names or ids: only lines of copy, a clock offset, my own write
/// time + 3 h, and a reunion date.
@immutable
class CoupleWidgetPayload {
  const CoupleWidgetPayload({
    this.headline,
    this.headlineIsClock = false,
    this.caption,
    this.clockOffsetMinutes,
    this.clockLine = false,
    this.validUntilMs,
    this.reunionDate,
  });

  static const empty = CoupleWidgetPayload();

  final String? headline;

  /// The headline is the partner's live clock (distant tone).
  final bool headlineIsClock;
  final String? caption;
  final int? clockOffsetMinutes;

  /// Show "{clock} there" as its own line.
  final bool clockLine;

  /// The distance part's end; null means there is no distance part.
  final int? validUntilMs;

  /// yyyy-MM-dd, local.
  final String? reunionDate;

  bool get hasDistance => validUntilMs != null;

  Map<String, Object> toJson() => {
    'v': CoupleWidgetConfig.payloadVersion,
    if (headline != null) 'headline': headline!,
    if (headlineIsClock) 'headlineIsClock': true,
    if (caption != null) 'caption': caption!,
    if (clockOffsetMinutes != null) 'clockOffsetMinutes': clockOffsetMinutes!,
    if (clockLine) 'clockLine': true,
    if (validUntilMs != null) 'validUntilMs': validUntilMs!,
    if (reunionDate != null) 'reunionDate': reunionDate!,
  };

  String encode() => jsonEncode(toJson());

  static CoupleWidgetPayload decode(String? raw) {
    if (raw == null) return empty;
    try {
      final m = jsonDecode(raw);
      if (m is! Map || m['v'] != CoupleWidgetConfig.payloadVersion) {
        return empty;
      }
      return CoupleWidgetPayload(
        headline: m['headline'] as String?,
        headlineIsClock: m['headlineIsClock'] == true,
        caption: m['caption'] as String?,
        clockOffsetMinutes: (m['clockOffsetMinutes'] as num?)?.toInt(),
        clockLine: m['clockLine'] == true,
        validUntilMs: (m['validUntilMs'] as num?)?.toInt(),
        reunionDate: m['reunionDate'] as String?,
      );
    } catch (_) {
      return empty;
    }
  }

  /// Keeps only the reunion (calendar data, not location).
  CoupleWidgetPayload withoutDistance() =>
      CoupleWidgetPayload(reunionDate: reunionDate);

  /// What is still true at [now]: the distance part until validUntil, the
  /// reunion until its day has passed.
  CoupleWidgetPayload current(DateTime now) {
    final distanceLive =
        validUntilMs != null && validUntilMs! > now.millisecondsSinceEpoch;
    final reunionLive = reunionDate != null && _daysTo(reunionDate!, now) >= 0;
    final base = distanceLive ? this : withoutDistance();
    if (reunionLive) return base;
    return CoupleWidgetPayload(
      headline: base.headline,
      headlineIsClock: base.headlineIsClock,
      caption: base.caption,
      clockOffsetMinutes: base.clockOffsetMinutes,
      clockLine: base.clockLine,
      validUntilMs: base.validUntilMs,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CoupleWidgetPayload && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}

@immutable
class CoupleWidgetBuild {
  const CoupleWidgetBuild(this.payload, {this.mapSelf, this.mapPartner});
  final CoupleWidgetPayload payload;

  /// The two cells, only when the region map applies (spec §3.3). They
  /// never enter the payload; the frame snaps them before drawing.
  final GeoPoint? mapSelf;
  final GeoPoint? mapPartner;
  bool get hasMap => mapSelf != null && mapPartner != null;
}

/// Turns one presence read into what the widget may show (spec §3.1, §4.2).
CoupleWidgetBuild buildCoupleWidget({
  required CoupleMapPresence presence,
  required Iterable<(String, DateTime)> events,
  required DateTime now,
  DateTime? readAt,
  String? keptReunionDate,
}) {
  final kept =
      CoupleWidgetPayload(
        reunionDate: keptReunionDate,
      ).current(now).reunionDate;
  final none = CoupleWidgetBuild(CoupleWidgetPayload(reunionDate: kept));
  final self = presence.self;
  final partner = presence.partner;
  final raw = presence.partnerDistance;
  if (presence.state.status != PresenceStatus.sharing ||
      self == null ||
      partner == null ||
      raw == null ||
      self.freshness != PresenceFreshness.fresh ||
      partner.freshness != PresenceFreshness.fresh) {
    return none;
  }
  final d = withReunion(raw, events, now: now);
  // From the READ, not the publish: a remembered read re-published later
  // (reminders changed) must not stay up longer (spec §4.2).
  final validUntilMs =
      (readAt ?? now).add(CoupleWidgetConfig.validFor).millisecondsSinceEpoch;
  final apart = '${formatKm(d.km)} apart';
  final offset = d.partnerUtcOffsetMinutes;
  final copy = distanceCopy(d, now: now);
  GeoPoint? at(PresenceArea a) =>
      a.cellLat == null || a.cellLng == null
          ? null
          : (lat: a.cellLat!, lng: a.cellLng!);
  CoupleWidgetBuild withMap(CoupleWidgetPayload p) {
    final a = at(self);
    final b = at(partner);
    if (d.km < CoupleWidgetConfig.mapMinKm || a == null || b == null) {
      return CoupleWidgetBuild(p);
    }
    return CoupleWidgetBuild(p, mapSelf: a, mapPartner: b);
  }

  switch (d.tone) {
    case DistanceTone.together:
    case DistanceTone.nearby:
      return CoupleWidgetBuild(
        CoupleWidgetPayload(
          headline: copy.headline,
          validUntilMs: validUntilMs,
        ),
      );
    case DistanceTone.sameCountry:
      final differs = offset != null && offset != now.timeZoneOffset.inMinutes;
      return withMap(
        CoupleWidgetPayload(
          headline: copy.headline,
          caption: apart,
          clockOffsetMinutes: differs ? offset : null,
          clockLine: differs,
          validUntilMs: validUntilMs,
        ),
      );
    case DistanceTone.countdown:
      final day = DateTime(now.year, now.month, now.day + d.daysUntilTogether!);
      return withMap(
        CoupleWidgetPayload(
          caption: apart,
          clockOffsetMinutes: offset,
          clockLine: offset != null,
          validUntilMs: validUntilMs,
          reunionDate: dateKey(day),
        ),
      );
    case DistanceTone.distant:
      return withMap(
        offset == null
            ? CoupleWidgetPayload(headline: apart, validUntilMs: validUntilMs)
            : CoupleWidgetPayload(
              headlineIsClock: true,
              caption: apart,
              clockOffsetMinutes: offset,
              validUntilMs: validUntilMs,
            ),
      );
  }
}

/// The lines a widget shows at [now]. The reference that W2's Swift and
/// Kotlin mirror, and what the in-app preview renders.
@immutable
class CoupleWidgetView {
  const CoupleWidgetView({
    required this.headline,
    this.caption,
    this.clockLine,
    this.neutral = false,
  });
  final String headline;
  final String? caption;
  final String? clockLine;
  final bool neutral;

  String get semanticsLabel =>
      [headline, caption, clockLine].whereType<String>().join('. ');
}

CoupleWidgetView resolveCoupleWidget(CoupleWidgetPayload stored, DateTime now) {
  final p = stored.current(now);
  final days = p.reunionDate == null ? null : _daysTo(p.reunionDate!, now);
  final offset = p.clockOffsetMinutes;
  final clock =
      offset == null
          ? null
          : '${formatClock(now.toUtc().add(Duration(minutes: offset)))} there';
  String countdown(int d) => switch (d) {
    0 => 'Together today',
    1 => 'Together tomorrow',
    _ => "$d days until you're together",
  };
  if (p.hasDistance) {
    if (days != null) {
      return CoupleWidgetView(
        headline: countdown(days),
        caption: p.caption,
        clockLine: p.clockLine ? clock : null,
      );
    }
    if (p.headlineIsClock && clock != null) {
      return CoupleWidgetView(headline: clock, caption: p.caption);
    }
    if (p.headline != null) {
      return CoupleWidgetView(
        headline: p.headline!,
        caption: p.caption,
        clockLine: p.clockLine ? clock : null,
      );
    }
  }
  if (days != null) {
    return days <= 1
        ? CoupleWidgetView(headline: countdown(days))
        : CoupleWidgetView(
          headline: '$days days',
          caption: "until you're together",
        );
  }
  return const CoupleWidgetView(headline: neutralHeadline, neutral: true);
}
