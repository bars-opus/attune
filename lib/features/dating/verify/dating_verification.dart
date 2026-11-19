// Spec 2 W4a (§3.3): what the verification calls answer, as the app reads
// them. Codes only: the app never shows a server's or a vendor's text, and
// a code it doesn't know is `unknown` / `failed` (fail closed: never
// "you're verified").

/// A check's state: passed, failed, being looked at, or not done.
enum DatingCheck {
  pass,
  fail,
  review,
  none;

  static DatingCheck of(Object? wire) => switch (wire) {
    'pass' => pass,
    'fail' => fail,
    'review' => review,
    _ => none,
  };
}

/// What a check step ended in (§3.3.2's outcome table).
enum DatingVerifyOutcome {
  verified('verified'),
  retry('retry'),
  anotherWay('another_way'),
  needsId('needs_id'),
  // R-13 (owner ruling 2026-11-09): the estimate was uncertain: the ID route.
  ageUncertain('age_uncertain'),
  photoMismatch('photo_mismatch'),
  farBelow('far_below'),
  idPending('id_pending'),
  dobMismatch('dob_mismatch'),
  ageNotConfirmed('age_not_confirmed'),
  humanPending('human_pending'),
  identityFailed('identity_failed'),
  askForId('ask_for_id'),
  pending('pending'),
  unknown('');

  const DatingVerifyOutcome(this.wire);

  final String wire;

  static DatingVerifyOutcome of(Object? wire) => values.firstWhere(
    (o) => o != unknown && o.wire == wire,
    orElse: () => unknown,
  );
}

/// Why a call was refused (dating-verification's fixed codes).
enum DatingVerifyRefusal {
  unavailable('unavailable'),
  invalid('invalid'),
  notEligible('not_eligible'),
  consentRequired('consent_required'),
  photosRequired('photos_required'),
  ageNotConfirmed('age_not_confirmed'),
  alreadyVerified('already_verified'),
  awaitingReview('awaiting_review'),
  rateLimited('rate_limited'),
  busy('busy'),
  sessionUnavailable('session_unavailable'),
  photosMissing('photos_missing'),
  reverifyDevice('reverify_device'),
  vendorUnavailable('vendor_unavailable'),
  // Spec 2 W4b fix round 1 (I-4 ruling): this phone has no install id, so
  // no check can name it (Task 7: a calm line, never the re-check).
  deviceUnavailable('device_unavailable'),
  // Spec 2 W4 final (server M-4): a check is open on another of the
  // person's phones (never busy); a calm line, nothing read again.
  sessionElsewhere('session_elsewhere'),
  failed('');

  const DatingVerifyRefusal(this.wire);

  final String wire;

  static DatingVerifyRefusal of(Object? wire) => values.firstWhere(
    (r) => r != failed && r.wire == wire,
    orElse: () => failed,
  );
}

/// The open, or the last, verification session (never a vendor reference).
class DatingVerifySession {
  const DatingVerifySession({
    required this.id,
    required this.step,
    required this.state,
    this.kind = 'activation',
    this.attempts = 0,
    this.outcome = DatingVerifyOutcome.unknown,
    this.position,
    this.open = false,
    this.gestures = const [],
  });

  final String id;
  final String kind;

  /// 'liveness', 'id' or 'human'.
  final String step;

  /// 'started', 'awaiting_review', 'passed', 'failed' or 'expired'.
  final String state;
  final int attempts;
  final DatingVerifyOutcome outcome;
  final int? position;
  final bool open;
  final List<String> gestures;

  bool get waiting => open && state == 'awaiting_review';

  static DatingVerifySession? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String || raw['step'] is! String) {
      return null;
    }
    final gestures = raw['gestures'];
    return DatingVerifySession(
      id: raw['id'] as String,
      kind: raw['kind'] is String ? raw['kind'] as String : 'activation',
      step: raw['step'] as String,
      state: raw['state'] is String ? raw['state'] as String : 'expired',
      attempts: raw['attempts'] is int ? raw['attempts'] as int : 0,
      outcome: DatingVerifyOutcome.of(raw['outcome']),
      position: raw['position'] is int ? raw['position'] as int : null,
      open: raw['open'] == true,
      gestures:
          gestures is List ? gestures.whereType<String>().toList() : const [],
    );
  }
}

/// One ID document the person's Dating country accepts.
class DatingIdDocument {
  const DatingIdDocument({required this.code, required this.nameKey});

  final String code;
  final String nameKey;
}

/// get_my_dating_verification(): the person's own verification state.
class DatingVerification {
  const DatingVerification({
    this.available = false,
    this.trustedDevice = true,
    this.age = DatingCheck.none,
    this.identity = DatingCheck.none,
    this.session,
    this.idDocuments = const [],
    this.photosReady = false,
  });

  /// Answered when the read itself fails or isn't an object: nothing runs.
  static const unavailable = DatingVerification();

  final bool available;

  /// false: this phone is not trusted (W4b's re-verification).
  final bool trustedDevice;
  final DatingCheck age;
  final DatingCheck identity;
  final DatingVerifySession? session;
  final List<DatingIdDocument> idDocuments;
  final bool photosReady;

  bool get verified => age == DatingCheck.pass && identity == DatingCheck.pass;

  /// A person or the ID vendor is checking (§3.1 'verifying').
  bool get waiting => session?.waiting ?? false;

  factory DatingVerification.fromJson(Object? raw) {
    if (raw is! Map || raw['ok'] != true) return unavailable;
    final docs = raw['id_documents'];
    return DatingVerification(
      available: raw['available'] == true,
      // Fix round 1 (M-1): only the server's own 'trusted' is trusted.
      trustedDevice: raw['device'] == 'trusted',
      age: DatingCheck.of(raw['age']),
      identity: DatingCheck.of(raw['identity']),
      session: DatingVerifySession.fromJson(raw['session']),
      idDocuments: [
        if (docs is List)
          for (final d in docs.whereType<Map>())
            if (d['code'] is String && d['name_key'] is String)
              DatingIdDocument(
                code: d['code'] as String,
                nameKey: d['name_key'] as String,
              ),
      ],
      photosReady: raw['photos_ready'] == true,
    );
  }
}

/// One dating-verification answer: a refusal, or what the step returned.
class DatingVerifyAnswer {
  const DatingVerifyAnswer({
    required this.ok,
    this.refusal,
    this.outcome = DatingVerifyOutcome.unknown,
    this.position,
    this.sessionId,
    this.vendor,
    this.vendorRef,
    this.gestures = const [],
    this.paths = const [],
    this.attempts = 0,
    this.resumed = false,
  });

  static const failed = DatingVerifyAnswer(
    ok: false,
    refusal: DatingVerifyRefusal.failed,
  );

  final bool ok;
  final DatingVerifyRefusal? refusal;
  final DatingVerifyOutcome outcome;
  final int? position;
  final String? sessionId;
  final String? vendor;

  /// The vendor's session or job for the device's capture view (never
  /// shown, never stored on the device).
  final String? vendorRef;
  final List<String> gestures;
  final List<String> paths;
  final int attempts;
  final bool resumed;

  /// Fix round 1 (I-2): the server may have moved on without this answer
  /// reaching the app (busy, a lost or failed call, a session already
  /// closed), so the flow reads the person's status again before it
  /// offers anything (`rereadDatingVerification`).
  bool get readStatusAgain =>
      !ok &&
      (refusal == null ||
          refusal == DatingVerifyRefusal.busy ||
          refusal == DatingVerifyRefusal.failed ||
          refusal == DatingVerifyRefusal.sessionUnavailable);

  /// Fix round 1 (M-6): the reason to pass to `DatingActionKeys.settle`
  /// if an action is ever keyed (today only the consent is). `failed`'s
  /// wire is the empty code, so a failure is named 'failed' and its key
  /// kept.
  String? get settleReason {
    if (ok) return null;
    final r = refusal;
    return r == null || r == DatingVerifyRefusal.failed ? 'failed' : r.wire;
  }

  factory DatingVerifyAnswer.fromJson(Object? raw) {
    if (raw is! Map) return failed;
    String? text(String key) => raw[key] is String ? raw[key] as String : null;
    List<String> list(String key) =>
        raw[key] is List
            ? (raw[key] as List).whereType<String>().toList()
            : const [];
    final ok = raw['ok'] == true;
    return DatingVerifyAnswer(
      ok: ok,
      refusal: ok ? null : DatingVerifyRefusal.of(raw['reason']),
      outcome: DatingVerifyOutcome.of(raw['outcome']),
      position: raw['position'] is int ? raw['position'] as int : null,
      sessionId: text('session_id'),
      vendor: text('vendor'),
      vendorRef: text('vendor_session') ?? text('vendor_job'),
      gestures: list('gestures'),
      paths: list('paths'),
      attempts: raw['attempts'] is int ? raw['attempts'] as int : 0,
      resumed: raw['resumed'] == true,
    );
  }
}
