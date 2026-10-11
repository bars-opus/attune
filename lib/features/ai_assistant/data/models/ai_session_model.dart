// lib/features/ai_assistant/data/models/ai_session_model.dart

/// A session's kind, as `ai_sessions.kind` stores it and
/// `review_context` echoes it.
enum AiSessionKind {
  ideas('ideas'),
  nearby('nearby');

  const AiSessionKind(this.wireValue);

  final String wireValue;

  static AiSessionKind parse(Object? value) =>
      AiSessionKind.values
          .where((candidate) => candidate.wireValue == value)
          .firstOrNull ??
      (throw FormatException('AiSessionKind: unrecognized kind "$value"'));
}

/// A session's visibility, as `ai_sessions.visibility` stores it.
enum AiSessionVisibility {
  private('private'),
  shared('shared');

  const AiSessionVisibility(this.wireValue);

  final String wireValue;

  static AiSessionVisibility parse(Object? value) =>
      AiSessionVisibility.values
          .where((candidate) => candidate.wireValue == value)
          .firstOrNull ??
      (throw FormatException(
        'AiSessionVisibility: unrecognized visibility "$value"',
      ));
}

/// The session state `approve` reports in a **200 body**.
///
/// THERE ARE EXACTLY TWO, AND THAT IS NOT THE COLUMN'S FULL DOMAIN.
/// `ai_sessions.state` holds more values, but `handleApprove` is the
/// only command that returns a state in a success body and it can only
/// ever return `"preparing"` or `"active"`: every other state is §3.1's
/// deliberately indistinguishable `UNAVAILABLE` **error**
/// ("Foreign, ended, expired and unauthorized session IDs return the
/// same unavailable response").
///
/// So there is deliberately no `ended`, `expired` or `unavailable` case
/// here. A caller cannot switch on this enum to render "the session is
/// gone", because liveness is reported through the error code — which
/// is `AiSessionError`'s job — and never through a state value. Adding
/// a case would hand a UI a second, disagreeing source of truth about
/// whether a session exists.
enum AiSessionState {
  preparing('preparing'),
  active('active');

  const AiSessionState(this.wireValue);

  final String wireValue;

  static AiSessionState parse(Object? value) =>
      AiSessionState.values
          .where((candidate) => candidate.wireValue == value)
          .firstOrNull ??
      (throw FormatException(
        'AiSessionState: "$value" is not a state approve can return '
        '(only "preparing" or "active"; every other state is an '
        'UNAVAILABLE error, never a 200 body)',
      ));
}

/// One message of the shared recent window, as `review_context` renders
/// it for the user to review.
///
/// Carries `truncated` because `selectSharedWindow` clips snippets
/// against a **2,400-scalar TOTAL budget** across the whole window, so
/// whether any given message was clipped depends on the others and can
/// change between calls. A UI must show the clip rather than imply the
/// partner will see the whole message.
class AiSessionWindowSnippet {
  /// `handleReviewContext`'s per-window-message projection, transcribed.
  static const Set<String> wireKeys = {'content', 'truncated'};

  final String content;
  final bool truncated;

  const AiSessionWindowSnippet({
    required this.content,
    required this.truncated,
  });

  factory AiSessionWindowSnippet.fromJson(Map<String, dynamic> json) {
    final content = json['content'];
    if (content is! String) {
      throw const FormatException(
        'AiSessionWindowSnippet.fromJson: missing/invalid content',
      );
    }
    final truncated = json['truncated'];
    if (truncated is! bool) {
      throw const FormatException(
        'AiSessionWindowSnippet.fromJson: missing/invalid truncated',
      );
    }
    return AiSessionWindowSnippet(content: content, truncated: truncated);
  }
}

/// The message the user selected at prepare time, as `review_context`
/// renders it.
///
/// **CARRIES ONLY `content`, AND THAT ASYMMETRY WITH
/// [AiSessionWindowSnippet] IS THE SERVER'S, NOT AN OMISSION HERE.**
/// `handleReviewContext` sends `target: {content}` against
/// `window: [{content, truncated}]`. The reason is the same one that
/// makes the approval digest unrecomputable (see
/// [AiSessionApprovalTicket]): the target's text is the **stored**
/// `approved_clipped_text`, frozen once at prepare time per §4.2
/// ("Persist source IDs, versions and snapshot time, not new selections
/// on subsequent turns"), whereas a window snippet is produced by the
/// live selection and re-clipped per call. Flattening the two into one
/// type with a nullable `truncated` would both invent a value the
/// server never sends and erase the evidence of that difference.
class AiSessionTargetSnippet {
  /// `handleReviewContext`'s target projection, transcribed.
  static const Set<String> wireKeys = {'content'};

  final String content;

  const AiSessionTargetSnippet({required this.content});

  factory AiSessionTargetSnippet.fromJson(Map<String, dynamic> json) {
    final content = json['content'];
    if (content is! String) {
      throw const FormatException(
        'AiSessionTargetSnippet.fromJson: missing/invalid content',
      );
    }
    return AiSessionTargetSnippet(content: content);
  }
}

/// THE RENDERABLE HALF of `review_context`'s response: what the user
/// reads before approving.
///
/// **GATE 2: THIS TYPE DOES NOT CARRY THE DIGEST.** Plan C *measured*
/// that recomputing the approval digest from stored rows is impossible
/// — `selectSharedWindow`'s 2,400-scalar total budget re-clips the
/// final snippet, and `review_context` hashes the *target* snippet as
/// stored text while hashing *window* snippets as the live selection
/// produced them — so a client that recomputed and compared would see
/// a spurious mismatch, which renders to the user as "my partner
/// changed the context". The digest and the revision therefore live on
/// [AiSessionApprovalTicket], which carries no snippets, and the two
/// types' field sets are disjoint but for the session id. Nothing in
/// this file can hand a caller the digest and its pre-image inputs at
/// once.
///
/// **AN HONEST LIMIT, recorded rather than quietly worked around:** the
/// SERVER's single `review_context` response *does* contain the digest
/// alongside most of its pre-image — the snippets here *are*
/// `computeApprovalDigest`'s `displayedSnippets`, and `policy_version`,
/// `kind`, `visibility` and `revision` are its other inputs (only
/// `participants` is withheld, and not deliberately). A client cannot
/// change what the server sends. What it can do is refuse to be the
/// type that makes the attempt convenient, which is what this split
/// is. If a later task needs both halves in one place, it should hold
/// the two objects side by side and say why, not merge them.
class AiSessionContextReview {
  /// The keys of `handleReviewContext`'s response this type reads.
  /// Exposed so the gate-2 split is a checkable property rather than a
  /// claim in a comment: a test asserts this set is disjoint from
  /// [AiSessionApprovalTicket.wireKeysRead] but for `session_id`, and
  /// that the two together cover all eleven keys the server sends.
  static const Set<String> wireKeysRead = {
    'session_id',
    'kind',
    'visibility',
    'include_window',
    'utc_offset_minutes',
    'window',
    'target',
  };

  /// Keys `review_context` sends that **NEITHER** half of the split
  /// reads, with the reason — so the split cannot be a way to drop a
  /// field silently. A test asserts
  /// `wireKeysRead ∪ AiSessionApprovalTicket.wireKeysRead ∪
  /// wireKeysDeliberatelyDropped` equals the server's full eleven.
  ///
  /// `civil_day_start_utc` is the only one. It is a **civil-day value**,
  /// which is precisely the class gate 2 names as a digest input not to
  /// be exposed beside the digest — and it would have to go on the
  /// ticket, not here, to be of any use for a comparison, since the
  /// renderable half has no digest to compare against. It is also no
  /// longer part of the pre-image at all: Ruling 35 (N3) removed
  /// `utc_offset_minutes`/`civil_day_start_utc` from
  /// `computeApprovalDigest` and bumped `DIGEST_FORMAT_VERSION` to v2,
  /// because binding the offset meant two partners in different
  /// timezones could never activate a shared session. The server still
  /// echoes it, and nothing in this client needs it: a UI renders the
  /// day from [utcOffsetMinutes] and the device clock, and the
  /// *selection* it governs has already happened server-side.
  ///
  /// Dropping it is therefore the conservative choice, and it is
  /// recorded here rather than left as an absence someone later reads
  /// as an oversight and "fixes" by adding it to the ticket.
  static const Set<String> wireKeysDeliberatelyDropped = {
    'civil_day_start_utc',
  };

  /// The **request** body keys the `review_context` command accepts,
  /// transcribed from `handleReviewContext`'s own `allowed` set minus
  /// `command` (which the repository's `_invoke` adds).
  ///
  /// **`set_include_window` IS ONE OF THEM.** §4.3's window toggle
  /// rides on this command rather than being a tenth command, because
  /// "the toggle invalidates approvals and bumps the revision, so the
  /// ONLY useful thing to do after it is re-read the context — which is
  /// what review_context does. Making it a separate command would
  /// guarantee a client that toggled and then approved against the
  /// stale revision it still held." A client that modelled
  /// `review_context` as purely read-only would have no way to turn the
  /// window on or off at all.
  ///
  /// It is OPTIONAL: when absent this command is read-only, exactly as
  /// before the toggle existed. `utc_offset_minutes`, by contrast, is
  /// REQUIRED on every call — `isValidUtcOffsetMinutes` refuses an
  /// absent or out-of-range value with `INVALID_INPUT` rather than
  /// clamping, because a clamped offset would compute a different civil
  /// day than the user saw. (The offset is no longer *hashed* — Ruling
  /// 35 / N3 dropped it from the pre-image so two partners in different
  /// timezones can agree — but it still decides *which* messages the
  /// window selects.)
  static const Set<String> reviewCommandBodyKeys = {
    'session_id',
    'utc_offset_minutes',
    'set_include_window',
  };

  final String sessionId;
  final AiSessionKind kind;
  final AiSessionVisibility visibility;

  /// The **stored** window setting the digest was computed under —
  /// after any toggle this same call applied. `handleReviewContext`
  /// returns it "so a client can see whether its toggle took effect
  /// without a second read": a client that asked for `true` and reads
  /// `false` back has learnt the server narrowed it (a private or
  /// Nearby session cannot have a window at all, per the
  /// `ai_sessions_window_only_shared_ideas` CHECK), which is a
  /// different outcome from an error.
  final bool includeWindow;

  /// The offset this review was computed against. Echoed so a UI can
  /// confirm the civil day it displayed is the one the server selected
  /// from.
  final int utcOffsetMinutes;

  /// The shared recent window, empty when [includeWindow] is false
  /// **and also** when it is true but no messages were eligible. Empty
  /// is never a terminal state; it is not evidence of anything about
  /// the session's liveness.
  final List<AiSessionWindowSnippet> window;

  /// The message `prepare` attached, or null when it attached none.
  /// Null rather than an empty snippet, because a blank quote card is
  /// not the same thing as no quote card.
  final AiSessionTargetSnippet? target;

  const AiSessionContextReview({
    required this.sessionId,
    required this.kind,
    required this.visibility,
    required this.includeWindow,
    required this.utcOffsetMinutes,
    required this.window,
    required this.target,
  });

  factory AiSessionContextReview.fromJson(Map<String, dynamic> json) {
    final sessionId = json['session_id'];
    if (sessionId is! String || sessionId.isEmpty) {
      throw const FormatException(
        'AiSessionContextReview.fromJson: missing/invalid session_id',
      );
    }
    final includeWindow = json['include_window'];
    if (includeWindow is! bool) {
      throw const FormatException(
        'AiSessionContextReview.fromJson: missing/invalid include_window',
      );
    }
    final offset = json['utc_offset_minutes'];
    if (offset is! int) {
      throw const FormatException(
        'AiSessionContextReview.fromJson: missing/invalid '
        'utc_offset_minutes',
      );
    }
    final rawWindow = json['window'];
    if (rawWindow is! List) {
      throw const FormatException(
        'AiSessionContextReview.fromJson: missing/invalid window',
      );
    }
    final rawTarget = json['target'];
    if (rawTarget != null && rawTarget is! Map) {
      throw const FormatException(
        'AiSessionContextReview.fromJson: invalid target',
      );
    }
    return AiSessionContextReview(
      sessionId: sessionId,
      kind: AiSessionKind.parse(json['kind']),
      visibility: AiSessionVisibility.parse(json['visibility']),
      includeWindow: includeWindow,
      utcOffsetMinutes: offset,
      window: rawWindow
          .map(
            (snippet) => AiSessionWindowSnippet.fromJson(
              Map<String, dynamic>.from(snippet as Map),
            ),
          )
          .toList(growable: false),
      target: rawTarget == null
          ? null
          : AiSessionTargetSnippet.fromJson(
              Map<String, dynamic>.from(rawTarget as Map),
            ),
    );
  }
}

/// THE OPAQUE HALF of `review_context`'s response: the
/// revision/digest/policy triple a client echoes straight back to
/// `approve`.
///
/// **THE DIGEST IS OPAQUE — CARRY IT, ECHO IT, NEVER DERIVE IT.**
/// Gate 2. Plan C measured two independent reasons recomputation from
/// stored rows is impossible:
///
///   * `selectSharedWindow`'s 2,400-scalar **total** budget re-clips
///     the final snippet, so a snippet's stored text and the text that
///     was hashed can differ;
///   * `review_context` hashes the **target** snippet as stored text
///     while hashing **window** snippets as the live selection produced
///     them.
///
/// That is why `approve` keeps doing existence/version revalidation
/// server-side (`frozenSnapshotStillApprovable`) instead of asking for
/// a recomputation, and why §4.3 only ever says "the client submits
/// revision/digest, not replacement content".
///
/// **THIS TYPE THEREFORE CARRIES NO SNIPPET, NO MESSAGE OFFSET AND NO
/// CIVIL-DAY VALUE** — see [wireKeysRead], whose disjointness from
/// [AiSessionContextReview.wireKeysRead] a test asserts. There is no
/// `computeDigest`, no `expectedDigest` and no `matchesSnippets`; the
/// digest is a `String` whose only supported operation is
/// [toApproveBody].
///
/// **THE REVISION AND THE DIGEST ARE ONE UNIT.** A window toggle bumps
/// the revision *and* changes the digest, and
/// `approve_ai_session_context` matches the revision while
/// `activate_ai_session` compares the digests, so sending a new
/// revision with an old digest reads to the user as "my partner changed
/// the context" (`CONTEXT_CHANGED`). Both fields are final and there is
/// no copy-with, so the pair cannot be split apart after the fact.
///
/// The remedy for a `CONTEXT_CHANGED` is always "call `review_context`
/// again and approve the *new* ticket it returns", never "recompute and
/// retry".
class AiSessionApprovalTicket {
  /// The keys of `handleReviewContext`'s response this type reads. See
  /// [AiSessionContextReview.wireKeysRead] for how the split is tested.
  static const Set<String> wireKeysRead = {
    'session_id',
    'revision',
    'policy_version',
    'digest',
  };

  final String sessionId;

  /// `ai_sessions.revision` **after** any window toggle the same
  /// `review_context` call applied — the server re-reads the row rather
  /// than assuming, because "computing the digest from an assumed
  /// revision is how two partners end up approving different integers".
  final int revision;

  /// The server's own current consent policy version. Echoed back so
  /// `approve` can detect that the policy moved between review and
  /// approval (a `CONTEXT_CHANGED`, not something to overwrite).
  /// `handleApprove` records the approval against **its own** current
  /// version regardless, and refuses a mismatch — a client literal like
  /// `"v1"` would record every approval against a version the consent
  /// system does not own.
  final String policyVersion;

  /// The opaque 64-character lowercase-hex digest. Validated by SHAPE
  /// here, mirroring `handleApprove`'s own `/^[0-9a-f]{64}$/`: a
  /// truncated or re-cased digest must fail at this boundary with a
  /// clear cause rather than being stored and later compared unequal,
  /// which the server's own comment notes "would read to the user as
  /// 'my partner changed the context'".
  final String digest;

  const AiSessionApprovalTicket({
    required this.sessionId,
    required this.revision,
    required this.policyVersion,
    required this.digest,
  });

  factory AiSessionApprovalTicket.fromJson(Map<String, dynamic> json) {
    final sessionId = json['session_id'];
    if (sessionId is! String || sessionId.isEmpty) {
      throw const FormatException(
        'AiSessionApprovalTicket.fromJson: missing/invalid session_id',
      );
    }
    final revision = json['revision'];
    if (revision is! int || revision < 1) {
      throw const FormatException(
        'AiSessionApprovalTicket.fromJson: missing/invalid revision',
      );
    }
    final policyVersion = json['policy_version'];
    if (policyVersion is! String || policyVersion.isEmpty) {
      throw const FormatException(
        'AiSessionApprovalTicket.fromJson: missing/invalid policy_version',
      );
    }
    final digest = json['digest'];
    if (digest is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw const FormatException(
        'AiSessionApprovalTicket.fromJson: digest must be 64 lowercase '
        'hex characters',
      );
    }
    return AiSessionApprovalTicket(
      sessionId: sessionId,
      revision: revision,
      policyVersion: policyVersion,
      digest: digest,
    );
  }

  /// The `approve` command's request body, minus `command` (which the
  /// repository's `_invoke` adds).
  ///
  /// The key set is exactly `handleApprove`'s own `allowed` set minus
  /// `command`, and a test asserts that equality. **Every command
  /// branch rejects unknown body keys strictly** against its own
  /// allowlist, so an extra key here — even a benign one — is an
  /// `INVALID_INPUT` on every call rather than something the server
  /// ignores. There is no actor field: the actor comes from the
  /// verified user on every branch.
  Map<String, Object> toApproveBody() => {
    'session_id': sessionId,
    'revision': revision,
    'digest': digest,
    'policy_version': policyVersion,
  };
}

/// `approve`'s success body: **THREE fields, not two.**
///
/// `handleApprove` returns `{approved, activated, state}` on all three
/// of its 200 paths — the already-active retry, the
/// `APPROVAL_REQUIRED`-from-`activate_ai_session` first-approver case,
/// and the ordinary activation.
///
/// **[state] IS REQUIRED AND WAITING-NESS IS READ FROM IT, NEVER
/// INFERRED FROM `!activated`.** `state` is what a UI actually renders
/// ("waiting for your partner"), and inferring it from `activated:
/// false` is the same shape of mistake as inferring an error from an
/// HTTP status: it happens to agree on today's two bodies and would
/// silently diverge the moment a third disposition exists.
/// [AiSessionApprovalResult.fromJson] therefore throws on a missing
/// `state` rather than defaulting it, which makes the inference
/// unavailable rather than merely discouraged.
///
/// A first approver's `{approved: true, activated: false, state:
/// "preparing"}` is a **SUCCESS**, not an error:
/// `handleApprove`'s own comment is that reporting it as
/// `APPROVAL_REQUIRED` "would tell a partner who did everything right
/// that they failed".
class AiSessionApprovalResult {
  /// `handleApprove`'s success-body key set, transcribed.
  static const Set<String> wireKeys = {'approved', 'activated', 'state'};

  final bool approved;
  final bool activated;
  final AiSessionState state;

  const AiSessionApprovalResult({
    required this.approved,
    required this.activated,
    required this.state,
  });

  /// True when this caller's approval landed but the session is still
  /// `preparing` — a shared session whose partner has not approved yet.
  ///
  /// Reads [state], not [activated], deliberately: the state is the
  /// rendered truth.
  bool get isWaitingForPartner => state == AiSessionState.preparing;

  factory AiSessionApprovalResult.fromJson(Map<String, dynamic> json) {
    final approved = json['approved'];
    if (approved is! bool) {
      throw const FormatException(
        'AiSessionApprovalResult.fromJson: missing/invalid approved',
      );
    }
    final activated = json['activated'];
    if (activated is! bool) {
      throw const FormatException(
        'AiSessionApprovalResult.fromJson: missing/invalid activated',
      );
    }
    if (!json.containsKey('state')) {
      throw const FormatException(
        'AiSessionApprovalResult.fromJson: missing state — waiting-ness '
        'must never be inferred from activated',
      );
    }
    return AiSessionApprovalResult(
      approved: approved,
      activated: activated,
      state: AiSessionState.parse(json['state']),
    );
  }
}

/// The lifecycle state a POLL can observe, which is a strictly wider set
/// than the one [AiSessionState] models.
///
/// ## WHY THIS IS A SECOND ENUM AND NOT A THIRD CASE ON [AiSessionState]
///
/// [AiSessionState] is deliberately approve-only: its `parse` THROWS for
/// anything but `preparing`/`active`, with the message "every other
/// state is an UNAVAILABLE error, never a 200 body". That contract is
/// correct for `approve` and must not be loosened — adding `closed` to
/// it would make a closed session a legal approval response, which §3.1
/// forbids.
///
/// But `read_state` genuinely CAN report `closed`, and that is the whole
/// point of polling it: `end_ai_session` sets `state = 'closed'` and
/// bumps the revision in the same statement, with its own comment saying
/// why — "advance `revision` so a revision-polling client can observe
/// the purge (F6)". So the poll needs a type that can hold `closed`
/// without either throwing or pretending a closed session is active.
/// Widening [AiSessionState] to serve the poll would have broken
/// `approve`; this is the narrower change.
enum AiSessionPolledState {
  preparing('preparing'),
  active('active'),
  closed('closed');

  const AiSessionPolledState(this.wireValue);

  final String wireValue;

  static AiSessionPolledState parse(Object? value) =>
      AiSessionPolledState.values
          .where((candidate) => candidate.wireValue == value)
          .firstOrNull ??
      (throw FormatException(
        'AiSessionPolledState: "$value" is not an ai_sessions.state '
        '(only "preparing", "active" or "closed")',
      ));
}

/// The `read_state` command's whole response: `{revision, state}`.
///
/// ## WHAT IS ABSENT HERE IS THE SECURITY PROPERTY (RULING 6)
///
/// This type has exactly TWO fields, and the migration
/// (20260953200600) argues each omission individually rather than
/// leaving it implied. The one that matters most: **`attempt_count` and
/// `last_admitted_at` are NOT here, because they MOVE ON A SAFETY
/// REFUSAL WHEN THE REVISION DOES NOT.** A refusal is admitted before
/// it is refused, so either field would let a partner polling this
/// surface see "something was attempted and nothing committed" — a
/// refusal with the serial numbers filed off, and precisely the
/// disclosure the edge function names in its own words at the
/// `generate` redirect branch ("bumping the revision for 'unsupported'
/// but not 'unsafe_to_assist' discloses the detector to a partner
/// polling session_revision — §8.1 forbids exactly that").
///
/// So no field may be added to this class without re-arguing Ruling 6.
/// `revision` and `state` are both unmoved by a refusal, which is what
/// makes polling them safe, and a contract test asserts that directly
/// with a precondition proving the refusal happened.
///
/// ## AN ABSENT STATE IS NOT "ENDED"
///
/// `read_ai_session_state` is SILENT (zero rows) for every unauthorized
/// outcome — unknown session, non-member, withdrawn consent, expired, a
/// shared session this actor never approved — byte-identically, for the
/// same §7.2 reason `read` returns an empty transcript rather than an
/// error. The repository therefore reports a null for "no answer", and
/// **null must never be read as "the session ended"**: a session that
/// really ended reports `closed` EXPLICITLY, and that is the only
/// evidence of ending this surface offers.
class AiSessionStateSnapshot {
  /// `ai_sessions.revision` — the §6.2 optimistic-concurrency token, and
  /// the value the poll compares against the one it already holds.
  final int revision;

  /// The session's lifecycle state. `closed` is a real answer, not an
  /// error: it is how a poll learns the partner ended the session.
  final AiSessionPolledState state;

  const AiSessionStateSnapshot({
    required this.revision,
    required this.state,
  });

  factory AiSessionStateSnapshot.fromJson(Map<String, dynamic> json) {
    final revision = json['revision'];
    if (revision is! int) {
      throw const FormatException(
        'AiSessionStateSnapshot.fromJson: missing/invalid revision',
      );
    }
    if (!json.containsKey('state')) {
      throw const FormatException(
        'AiSessionStateSnapshot.fromJson: missing state',
      );
    }
    return AiSessionStateSnapshot(
      revision: revision,
      state: AiSessionPolledState.parse(json['state']),
    );
  }
}
