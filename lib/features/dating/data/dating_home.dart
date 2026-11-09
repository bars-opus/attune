// Spec 2 W3a (§3.1): what get_dating_home() says, and the open countries.
// An unknown or missing state is `unavailable`: the app never shows a state
// the server did not name (fail closed: never "you're live").

enum DatingHomeState {
  featureUnavailable('feature_unavailable'),
  countryClosed('country_closed'),
  regionClosed('region_closed'),
  reverifyDevice('reverify_device'),
  restricted('restricted'),
  hold('hold'),
  ageReview('age_review'),
  unavailable('unavailable'),
  paused('paused'),
  coolOff('cool_off'),
  active('active'),
  gentleWait('gentle_wait'),
  notStarted('not_started'),
  setupInProgress('setup_in_progress');

  const DatingHomeState(this.wire);

  final String wire;

  static DatingHomeState fromWire(Object? value) => values.firstWhere(
    (s) => s.wire == value,
    orElse: () => DatingHomeState.unavailable,
  );
}

/// Why Dating is paused (§4.3); NULL or a reason this app doesn't know is
/// [unknown] and gets the plain paused card (carry 9).
enum DatingPauseReason {
  user('user'),
  relationship('relationship'),
  pathChange('path_change'),
  sameGenderSwitch('same_gender_switch'),
  away('away'),
  accountParked('account_parked'),
  gates('gates'),
  unknown('');

  const DatingPauseReason(this.wire);

  final String wire;

  static DatingPauseReason fromWire(Object? value) => values.firstWhere(
    (r) => r != unknown && r.wire == value,
    orElse: () => DatingPauseReason.unknown,
  );
}

/// "Tell me when it's here" (§2.7): whether it can be asked for here, and
/// whether it already has been.
class DatingNotice {
  const DatingNotice({this.available = false, this.requested = false});

  final bool available;
  final bool requested;

  factory DatingNotice.fromJson(Object? raw) =>
      raw is Map
          ? DatingNotice(
            available: raw['available'] == true,
            requested: raw['requested'] == true,
          )
          : const DatingNotice();
}

class DatingHome {
  const DatingHome({
    required this.state,
    this.country,
    this.region,
    this.openRegions = const [],
    this.pauseReason = DatingPauseReason.unknown,
    this.firstDropAt,
    this.endedAt,
    this.opensAt,
    this.canShorten = false,
    this.canResume,
    this.hasData = false,
    this.nextStep,
    this.notice = const DatingNotice(),
  });

  final DatingHomeState state;
  final String? country;
  final String? region;
  final List<String> openRegions;
  final DatingPauseReason pauseReason;
  final DateTime? firstDropAt;
  final DateTime? endedAt;
  final DateTime? opensAt;
  final bool canShorten;

  /// Paused only (T4 fix round 1, I-2): false while a shared space holds
  /// the pause, true when nothing does (a relationship pause read after
  /// the space ended can resume); null when the server didn't say.
  final bool? canResume;

  /// The person has Dating data to leave or clear (a profile, an
  /// enrolment, a reflection, a notice request), whatever the state (C-2).
  final bool hasData;
  final String? nextStep;
  final DatingNotice notice;

  factory DatingHome.fromJson(Map<String, dynamic> json) {
    DateTime? at(String key) {
      final value = json[key];
      return value is String ? DateTime.tryParse(value) : null;
    }

    String? text(String key) =>
        json[key] is String ? json[key] as String : null;
    final regions = json['open_regions'];
    return DatingHome(
      state: DatingHomeState.fromWire(json['state']),
      country: text('country'),
      region: text('region'),
      openRegions:
          regions is List ? regions.whereType<String>().toList() : const [],
      pauseReason: DatingPauseReason.fromWire(json['pause_reason']),
      firstDropAt: at('first_drop_at'),
      endedAt: at('ended_at'),
      opensAt: at('opens_at'),
      canShorten: json['can_shorten'] == true,
      canResume: json['can_resume'] is bool ? json['can_resume'] as bool : null,
      hasData: json['has_data'] == true,
      nextStep: text('next_step'),
      notice: DatingNotice.fromJson(json['notify']),
    );
  }

  /// Paused only: whether Resume can work now (T12 carry B, shared by the
  /// section and Dating settings). The person's own pause, a gates or a
  /// path-change pause, or one with no reason resume; a relationship
  /// pause only once the server says no shared space holds it. Never
  /// while `can_resume` is false, nor for travel, a parked number or a
  /// same-gender switch (T4 fix round 1, I-2).
  bool get resumeOffered {
    if (state != DatingHomeState.paused || canResume == false) return false;
    return switch (pauseReason) {
      DatingPauseReason.user ||
      DatingPauseReason.gates ||
      DatingPauseReason.pathChange ||
      DatingPauseReason.unknown => true,
      DatingPauseReason.relationship => canResume == true,
      DatingPauseReason.away ||
      DatingPauseReason.accountParked ||
      DatingPauseReason.sameGenderSwitch => false,
    };
  }

  /// A Dating profile exists, so Dating settings have something to show.
  bool get hasProfile => const {
    DatingHomeState.setupInProgress,
    DatingHomeState.gentleWait,
    DatingHomeState.coolOff,
    DatingHomeState.active,
    DatingHomeState.paused,
  }.contains(state);
}

/// One open country (get_dating_availability): its open regions' name keys,
/// or null when every region is open.
class DatingOpenCountry {
  const DatingOpenCountry({required this.code, this.openRegionKeys});

  final String code;
  final List<String>? openRegionKeys;
}

class DatingAvailability {
  const DatingAvailability({this.countries = const []});

  final List<DatingOpenCountry> countries;

  bool isOpen(String? code) => countries.any((c) => c.code == code);

  factory DatingAvailability.fromJson(Map<String, dynamic> json) {
    final raw = json['countries'];
    if (raw is! List) return const DatingAvailability();
    return DatingAvailability(
      countries: [
        for (final c in raw.whereType<Map>())
          if (c['code'] is String)
            DatingOpenCountry(
              code: c['code'] as String,
              openRegionKeys:
                  c['open_regions'] is List
                      ? [
                        for (final r
                            in (c['open_regions'] as List).whereType<Map>())
                          if (r['name_key'] is String) r['name_key'] as String,
                      ]
                      : null,
            ),
      ],
    );
  }
}
