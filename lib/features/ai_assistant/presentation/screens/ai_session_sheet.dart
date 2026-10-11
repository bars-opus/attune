// lib/features/ai_assistant/presentation/screens/ai_session_sheet.dart
//
// Multi-turn AI Sessions (spec §3-§8): the preparation screen
// (kind/visibility choice), the approval step over the reviewed
// context, and the live transcript with its instruction field.
//
// Pushed via MaterialPageRoute, matching AssistSheet's and
// AskAttuneModeSheet's own convention — "sheet" names the feature's
// screen, and this one owns its own input field rather than reusing the
// chat composer instance, for the same reason AssistSheet does.
//
// ## RULING 6 LIVES IN THIS FILE, and it is the reason for
// [AiSessionRedirectNotice]
//
// `generate` returns TWO different `kind: "redirect"` shapes that
// deliberately share the kind AND the reason set: a safety refusal with
// a server-rendered `copy` and an EMPTY `offered`, and the model's
// ordinary redirect with NO `copy`. §8.1 forbids disclosing which
// detector fired, to either party.
//
// Task 4 closed the MODEL surface structurally — `_copy` is private and
// reachable only through a total `resolveCopy({genericRedirectCopy})`.
// But a model-level closure is not enough here, because **a different
// widget tree for the two shapes is a visible oracle to anyone watching
// the screen.** A different icon, a different alignment, an extra
// badge, a changed container colour or a second analytics event would
// each reconstruct "a safety detector fired" from the UI alone, in the
// one place a probing requester can reach.
//
// So there is exactly ONE redirect widget, it is reached from exactly
// ONE state field, and it renders the two shapes through ONE call:
// `resolveCopy(genericRedirectCopy: kAiSessionGenericRedirectCopy)`.
// It never asks which shape it got, and it has nothing to ask with.
// A widget test renders both shapes and compares the resulting trees
// element by element; another reads this file's declarations and fails
// on `offered.isEmpty` or any other proxy.
//
// RULING 15 extends the same rule to `publish_nearby`, which can answer
// a redirect at HTTP 200. On that path a redirect is ALWAYS a safety
// refusal (the handler has no ordinary-redirect branch), so a
// publish-specific notice would announce the detector outright. It
// lands in the same state field and therefore the same widget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/ai_session_model.dart';
import '../../data/models/ai_session_turn_model.dart';
import '../../data/models/place_source_model.dart';
import '../../data/repositories/ai_session_error.dart';
import '../../data/services/ai_session_capabilities.dart';
import '../providers/ai_assistant_providers.dart';
import '../providers/ai_session_provider.dart';

// ---------------------------------------------------------------------
// Copy. Exported as constants so a test asserts the SAME string the
// widget renders rather than a transcription that can drift.
// ---------------------------------------------------------------------

const String kAiSessionIdeasLabel = 'Ideas';
const String kAiSessionNearbyLabel = 'Nearby';
const String kAiSessionPrivateLabel = 'Just me';
const String kAiSessionSharedLabel = 'Both of us';
const String kAiSessionStartLabel = 'Start';
const String kAiSessionApproveLabel = 'Approve and start';
const String kAiSessionReReviewLabel = 'Review again';
const String kAiSessionRefreshLabel = 'Check again';
const String kAiSessionShareLabel = 'Share to chat';
const String kAiSessionPublishLabel = 'Share with your partner';
const String kAiSessionDiscardLabel = 'Discard';
const String kAiSessionEndLabel = 'End session';
const String kAiSessionIncludeWindowLabel = 'Include recent messages';
const String kAiSessionTruncatedLabel = 'Shortened';

/// Deliberately ABSENT from the sheet: there is no "Retry" for a
/// `CONTEXT_CHANGED`. The remedy is always to re-review and approve the
/// digest the server returns — a client cannot recompute the digest
/// (gate 2), so a retry would resend one the server already rejected.
/// Named here only so a test can assert it is nowhere on screen.
const String kAiSessionRetryLabel = 'Retry';

const String kAiSessionWaitingForPartnerMessage =
    'Waiting for your partner to approve.';
const String kAiSessionContextChangedMessage =
    'The context changed. Review it again before starting.';
const String kAiSessionEmptyTranscriptMessage =
    'Nothing here yet. Ask for something below.';
const String kAiSessionEndedMessage = 'This session has ended.';
const String kAiSessionUnavailableMessage =
    'Sessions are not available right now.';

/// The copy an ordinary redirect shows.
///
/// **Passed to `resolveCopy` as the REQUIRED `genericRedirectCopy`**, so
/// the call site gets back whichever string should be shown without
/// ever learning which shape it received. It is required rather than
/// defaulted on the model precisely so a caller cannot discover the
/// server's copy by comparing against a known default.
const String kAiSessionGenericRedirectCopy =
    'I can help with ideas or places nearby. Want to try one of those?';

/// §8.1 requires the safety-resources link be OFFERED, and
/// `show_safety_resources` is constant-true on every path including the
/// allowed one — so it is read from the field rather than hardcoded,
/// and its value is never treated as a signal (being constant, it
/// cannot be one).
const String kAiSessionSafetyResourcesLabel = 'Support resources';

// ---------------------------------------------------------------------
// The sheet
// ---------------------------------------------------------------------

class AiSessionSheet extends ConsumerStatefulWidget {
  const AiSessionSheet({
    super.key,
    required this.relationshipId,
    required this.initialKind,
    required this.utcOffsetMinutes,
    required this.onShared,
    this.targetMessageId,
  });

  final String relationshipId;

  /// Which kind the entry point asked for. Still changeable on the
  /// preparation screen when the capability allows it.
  final AiSessionKind initialKind;

  /// **The offset the UI DISPLAYED**, passed in by the caller rather
  /// than computed here, so one value reaches `prepare` and every
  /// `review_context`. The server refuses out of range rather than
  /// clamping, because a clamped offset computes a different civil day
  /// than the user saw (§4.2).
  final int utcOffsetMinutes;

  /// Called with the new `public.messages` id after `share_answer`
  /// succeeds. An explicit callback rather than a Navigator result,
  /// matching AssistSheet's own convention: this screen is always
  /// pushed, so the caller decides what "done" means.
  final ValueChanged<String> onShared;

  final String? targetMessageId;

  @override
  ConsumerState<AiSessionSheet> createState() => _AiSessionSheetState();
}

class _AiSessionSheetState extends ConsumerState<AiSessionSheet> {
  final _instructionController = TextEditingController();
  late AiSessionKind _kind = widget.initialKind;
  AiSessionVisibility _visibility = AiSessionVisibility.private;
  bool _includeWindow = false;

  @override
  void initState() {
    super.initState();
    // THE POLL'S START, driven by the PHASE rather than by a command's
    // return value (spec §6.1 as amended).
    //
    // It arms when the sheet first reaches a phase where a change this
    // actor did not cause can happen behind their back, and only then:
    //
    //   * `waitingForPartner` — this actor approved first and holds a
    //     200 `{activated: false}`. The partner's later approval is
    //     reported to the PARTNER; nothing tells this actor, so without
    //     the poll this wait never ends on its own.
    //   * `active` — a partner's committed turn, and a partner's `end`,
    //     both bump the revision.
    //
    // NOT armed in `choosing` or `reviewing`: there is no session id
    // yet in the first, and in the second this actor holds its own
    // `review_context` response and has nothing to wait on.
    //
    // `listenManual` rather than a `ref.listen` in `build`: this is a
    // side effect on a transition, and `build` must stay free of them.
    // The subscription is closed in `dispose` below.
    //
    // THE NOTIFIER IS CAPTURED HERE, NOT READ IN `dispose`. `ref` throws
    // `Bad state: Cannot use "ref" after the widget was disposed` once
    // the element is unmounted, so a `dispose` that reaches the
    // controller through `ref.read` (which `_controller` does) crashes
    // every teardown of this sheet. MEASURED, not anticipated: my first
    // version did exactly that and took 18 previously-passing widget
    // tests in this file down with it, all with that StateError thrown
    // "while finalizing the widget tree". The notifier itself outlives
    // the widget — it is owned by the provider container — so holding it
    // is safe where re-reading it is not.
    _pollController = ref.read(aiSessionControllerProvider.notifier);
    _phaseSubscription = ref.listenManual<AiSessionViewState>(
      aiSessionControllerProvider,
      (previous, next) {
        if (next.phase == AiSessionPhase.waitingForPartner ||
            next.phase == AiSessionPhase.active) {
          _pollController.startPolling();
        } else if (next.phase == AiSessionPhase.ended) {
          // Belt-and-braces: the controller already stops itself when
          // the poll OBSERVES `closed`, but this covers the path where
          // THIS actor called `end` and the phase moved without a tick.
          _pollController.stopPolling();
        }
      },
    );
  }

  /// The controller, captured in [initState] so [dispose] can stop the
  /// poll without touching `ref`. See the note there.
  late final AiSessionController _pollController;

  ProviderSubscription<AiSessionViewState>? _phaseSubscription;

  @override
  void dispose() {
    // STOP 1 OF 4: the sheet is closing, so the poll must not outlive
    // it. Uses the CAPTURED notifier, never `ref` — see initState. The
    // controller's own `ref.onDispose` is the backstop for the
    // autoDispose teardown; this is the explicit close.
    _pollController.stopPolling();
    _phaseSubscription?.close();
    _instructionController.dispose();
    super.dispose();
  }

  /// A canonical v4 UUID from the `uuid` package this repository
  /// already depends on and uses in `chat_state.dart`,
  /// `create_planning_goal_screen.dart` and elsewhere.
  ///
  /// **Not hand-rolled, and the reason is load-bearing rather than
  /// stylistic.** The key BECOMES the session id (Plan C Ruling 5), and
  /// `parsePrepareRequest` runs `isCanonicalUuid` over it — so a key
  /// that is merely v4-SHAPED is an invalid session id and an
  /// `INVALID_INPUT` on every call. The same generator produces each
  /// `request_id`, which `admit_ai_session_generation` fingerprints:
  /// reusing one with a different revision is `REQUEST_CONFLICT`, so a
  /// generator with a collision window would turn two legitimate turns
  /// into a conflict.
  String _newUuidV4() => const Uuid().v4();

  AiSessionController get _controller =>
      ref.read(aiSessionControllerProvider.notifier);

  Future<void> _start() {
    return _controller.prepare(
      idempotencyKey: _newUuidV4(),
      relationshipId: widget.relationshipId,
      kind: _kind,
      visibility: _visibility,
      utcOffsetMinutes: widget.utcOffsetMinutes,
      targetMessageId: widget.targetMessageId,
      includeWindow: _includeWindow,
    );
  }

  Future<void> _generate() async {
    final instruction = _instructionController.text.trim();
    if (instruction.isEmpty) return;
    _instructionController.clear();
    await _controller.generate(
      requestId: _newUuidV4(),
      userInstruction: instruction,
    );
  }

  Future<void> _share(int ordinal) async {
    final messageId = await _controller.shareAnswer(ordinal);
    if (messageId != null && mounted) widget.onShared(messageId);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiSessionControllerProvider);
    final capabilities =
        ref.watch(aiSessionCapabilitiesProvider).valueOrNull ??
        AiSessionCapabilities.unavailable;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _kind == AiSessionKind.ideas
              ? kAiSessionIdeasLabel
              : kAiSessionNearbyLabel,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        actions: [
          if (state.phase == AiSessionPhase.active ||
              state.phase == AiSessionPhase.waitingForPartner)
            TextButton(
              onPressed: state.busy ? null : _controller.end,
              child: const Text(kAiSessionEndLabel),
            ),
        ],
      ),
      body: SafeArea(
        child: switch (state.phase) {
          AiSessionPhase.choosing => _Preparation(
            state: state,
            capabilities: capabilities,
            kind: _kind,
            visibility: _visibility,
            includeWindow: _includeWindow,
            onKind: (kind) => setState(() => _kind = kind),
            onVisibility: (visibility) =>
                setState(() => _visibility = visibility),
            onIncludeWindow: (value) => setState(() => _includeWindow = value),
            onStart: _start,
          ),
          AiSessionPhase.reviewing => _Approval(
            state: state,
            onApprove: _controller.approve,
            onReReview: () => _controller.refreshContext(
              utcOffsetMinutes: widget.utcOffsetMinutes,
            ),
          ),
          AiSessionPhase.waitingForPartner => _WaitingForPartner(
            state: state,
            onRefresh: () => _controller.refreshContext(
              utcOffsetMinutes: widget.utcOffsetMinutes,
            ),
          ),
          AiSessionPhase.active => _Transcript(
            state: state,
            controller: _instructionController,
            onGenerate: _generate,
            onShare: _share,
            onPublish: _controller.publishStaged,
            onDiscard: _controller.discardStaged,
            onDismissRedirect: _controller.dismissRedirect,
          ),
          AiSessionPhase.ended => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(kAiSessionEndedMessage),
            ),
          ),
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Preparation
// ---------------------------------------------------------------------

class _Preparation extends StatelessWidget {
  const _Preparation({
    required this.state,
    required this.capabilities,
    required this.kind,
    required this.visibility,
    required this.includeWindow,
    required this.onKind,
    required this.onVisibility,
    required this.onIncludeWindow,
    required this.onStart,
  });

  final AiSessionViewState state;
  final AiSessionCapabilities capabilities;
  final AiSessionKind kind;
  final AiSessionVisibility visibility;
  final bool includeWindow;
  final ValueChanged<AiSessionKind> onKind;
  final ValueChanged<AiSessionVisibility> onVisibility;
  final ValueChanged<bool> onIncludeWindow;
  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) {
    // EVERY availability question is asked of the capability service,
    // never of `feature_flags` directly — the RLS policy on that table
    // hides every `ai_%` key from the client, so a direct read would
    // return no rows and every flag would read false forever (PF2).
    //
    // And each field is read INDEPENDENTLY: §12 requires subcapability
    // independence, so no capability is inferred from another.
    final kinds = <AiSessionKind>[
      if (capabilities.sessionsPrivate || capabilities.sessionsShared)
        AiSessionKind.ideas,
      if (capabilities.sessionsNearby) AiSessionKind.nearby,
    ];
    final visibilities = <AiSessionVisibility>[
      if (capabilities.sessionsPrivate) AiSessionVisibility.private,
      if (capabilities.sessionsShared) AiSessionVisibility.shared,
    ];

    if (kinds.isEmpty || visibilities.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(kAiSessionUnavailableMessage),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What kind?', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final candidate in kinds)
                ChoiceChip(
                  label: Text(
                    candidate == AiSessionKind.ideas
                        ? kAiSessionIdeasLabel
                        : kAiSessionNearbyLabel,
                  ),
                  selected: kind == candidate,
                  onSelected: (_) => onKind(candidate),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Who can see it?', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final candidate in visibilities)
                ChoiceChip(
                  label: Text(
                    candidate == AiSessionVisibility.private
                        ? kAiSessionPrivateLabel
                        : kAiSessionSharedLabel,
                  ),
                  selected: visibility == candidate,
                  onSelected: (_) => onVisibility(candidate),
                ),
            ],
          ),
          // The recent window is offered only for a SHARED, non-Nearby
          // session — the server's own two shape rules ("private and
          // Nearby sessions do not have recent windows") — and only
          // when its OWN flag is on: it is the one subcapability that
          // puts the partner's chat text into a provider prompt, so it
          // is separately killable.
          if (visibility == AiSessionVisibility.shared &&
              kind == AiSessionKind.ideas &&
              capabilities.sessionsRecentWindow) ...[
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(kAiSessionIncludeWindowLabel),
              value: includeWindow,
              onChanged: onIncludeWindow,
            ),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 16),
            AiSessionErrorNotice(error: state.error!),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: state.busy ? null : () => onStart(),
            child: state.busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(kAiSessionStartLabel),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Approval
// ---------------------------------------------------------------------

class _Approval extends StatelessWidget {
  const _Approval({
    required this.state,
    required this.onApprove,
    required this.onReReview,
  });

  final AiSessionViewState state;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReReview;

  @override
  Widget build(BuildContext context) {
    final review = state.review;
    final textTheme = Theme.of(context).textTheme;
    // A CONTEXT_CHANGED's remedy is RE-REVIEW, never a retry: a client
    // cannot recompute the digest (gate 2), so resending the same
    // approval could only be rejected again.
    final contextChanged = state.error is AiSessionContextChangedError;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Review what Attune will see', style: textTheme.titleSmall),
          const SizedBox(height: 12),
          if (review != null) ...[
            if (review.target != null) ...[
              Text(review.target!.content, style: textTheme.bodyMedium),
              const SizedBox(height: 12),
            ],
            for (final snippet in review.window)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(snippet.content, style: textTheme.bodyMedium),
                    // SHOWN rather than implied: `selectSharedWindow`
                    // clips against a 2,400-scalar TOTAL budget across
                    // the whole window, so whether any given message
                    // was clipped depends on the others and can change
                    // between calls.
                    if (snippet.truncated)
                      Text(
                        kAiSessionTruncatedLabel,
                        style: textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
          ],
          if (contextChanged) ...[
            const SizedBox(height: 16),
            Text(
              kAiSessionContextChangedMessage,
              style: textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: state.busy ? null : () => onReReview(),
              child: const Text(kAiSessionReReviewLabel),
            ),
          ] else if (state.error != null) ...[
            const SizedBox(height: 16),
            AiSessionErrorNotice(error: state.error!),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: state.busy ? null : () => onApprove(),
            child: state.busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(kAiSessionApproveLabel),
          ),
        ],
      ),
    );
  }
}

/// `{approved: true, activated: false, state: "preparing"}` is a **200
/// SUCCESS**, not an error, so this is a plain informational state with
/// no error styling.
///
/// The refresh is MANUAL and deliberately so: gate 1 means
/// `session_revision` reaches only the actor who caused the bump, so the
/// partner — the party that must notice an approval — cannot read a
/// revision move from any command. Nothing here assumes they can; Task
/// 8 owns the polling problem.
class _WaitingForPartner extends StatelessWidget {
  const _WaitingForPartner({required this.state, required this.onRefresh});

  final AiSessionViewState state;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(kAiSessionWaitingForPartnerMessage),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: state.busy ? null : () => onRefresh(),
              child: const Text(kAiSessionRefreshLabel),
            ),
            if (state.error != null) ...[
              const SizedBox(height: 16),
              AiSessionErrorNotice(error: state.error!),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// The live transcript
// ---------------------------------------------------------------------

class _Transcript extends StatelessWidget {
  const _Transcript({
    required this.state,
    required this.controller,
    required this.onGenerate,
    required this.onShare,
    required this.onPublish,
    required this.onDiscard,
    required this.onDismissRedirect,
  });

  final AiSessionViewState state;
  final TextEditingController controller;
  final Future<void> Function() onGenerate;
  final Future<void> Function(int ordinal) onShare;
  final Future<void> Function(String requestId) onPublish;
  final Future<void> Function(String requestId) onDiscard;
  final VoidCallback onDismissRedirect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (state.turns.isEmpty)
                // §7.2: `read` returns 200-with-empty-array for a
                // stranger, a non-approver AND a healthy session with no
                // committed turn, all byte-identical. So emptiness is
                // rendered as emptiness and NEVER as "ended" — doing
                // that would turn the server's deliberate silence into
                // a verdict the client is not entitled to draw.
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(kAiSessionEmptyTranscriptMessage),
                ),
              // Rendered IN THE SERVER'S ORDER, with each turn's own
              // ordinal carried through. Nothing indexes this list by
              // ordinal, renumbers it to 1..n, or derives an attempt
              // count from its length — ordinals are 2n-1/2n and MAY BE
              // NON-CONTIGUOUS (a failed attempt leaves a gap), so a
              // renumbered list would share the wrong turn.
              for (final turn in state.turns)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: switch (turn) {
                    AiSessionUserTurn(instruction: final instruction) =>
                      _UserBubble(instruction: instruction),
                    AiSessionIdeasAnswerTurn(replyText: final replyText) =>
                      AiSessionAttuneBubble(
                        replyText: replyText,
                        // The SERVER's ordinal, unchanged.
                        onShare: () => onShare(turn.ordinal),
                      ),
                    AiSessionNearbyResultTurn(
                      replyText: final replyText,
                      sources: final sources,
                    ) =>
                      AiSessionAttuneBubble(
                        replyText: replyText,
                        sources: sources,
                        // A Nearby pair is already shared with the
                        // partner (publishing is what committed it),
                        // and `share_ai_session_turn` allowlists
                        // `ideas_answer` alone — so there is no Share
                        // action here rather than one that would be
                        // refused.
                        onShare: null,
                      ),
                  },
                ),
              // The requester's own staged Nearby result: NOT a
              // transcript turn, because nothing is committed and the
              // partner can see nothing until it is published.
              if (state.pendingStage case final stage?)
                _StagedCard(
                  stage: stage,
                  busy: state.busy,
                  onPublish: () => onPublish(stage.requestId),
                  onDiscard: () => onDiscard(stage.requestId),
                ),
              // ONE slot, BOTH redirect shapes, BOTH commands. See the
              // file header and [AiSessionRedirectNotice].
              if (state.redirect case final redirect?)
                AiSessionRedirectNotice(
                  redirect: redirect,
                  onDismiss: onDismissRedirect,
                ),
              if (state.error != null) AiSessionErrorNotice(error: state.error!),
            ],
          ),
        ),
        _InstructionField(
          controller: controller,
          busy: state.busy,
          onSubmit: onGenerate,
        ),
      ],
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.instruction});

  final String instruction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          instruction,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

/// A committed Attune turn.
///
/// Public so a test can assert a redirect is NOT one of these: §5.3 was
/// amended so no redirect becomes a transcript pair, precisely because a
/// durable redirect is a safety side channel.
class AiSessionAttuneBubble extends StatelessWidget {
  const AiSessionAttuneBubble({
    super.key,
    required this.replyText,
    this.sources,
    this.onShare,
  });

  final String replyText;
  final List<PlaceSourceModel>? sources;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(replyText, style: textTheme.bodyMedium),
            // Source cards. There is no existing card widget to reuse —
            // the brief's sub-step E says to reuse "whatever card widget
            // assist_sheet.dart's own Nearby preview already uses", and
            // that preview renders a bare `Text(source.name)` with no
            // card widget at all, so there is nothing to reuse and this
            // is the first one. It shows the address as well as the
            // name, because both are what the server's own output safety
            // pass covers (§5.3: "prose, proposals and SOURCE DISPLAY
            // STRINGS").
            //
            // GATE 4: NO confirmation badge. The Nearby
            // `confirmation_nonce` is decorative — no issuing RPC,
            // column or table exists — so presenting a confirmation
            // would claim a control the server never issued.
            if (sources != null)
              for (final source in sources!)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(source.name, style: textTheme.titleSmall),
                      if (source.formattedAddress case final address?)
                        Text(address, style: textTheme.bodySmall),
                    ],
                  ),
                ),
            if (onShare != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onShare,
                child: const Text(kAiSessionShareLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StagedCard extends StatelessWidget {
  const _StagedCard({
    required this.stage,
    required this.busy,
    required this.onPublish,
    required this.onDiscard,
  });

  final AiSessionStagedNearbyGeneration stage;
  final bool busy;
  final VoidCallback onPublish;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Only you can see this', style: textTheme.labelMedium),
          const SizedBox(height: 8),
          Text(stage.replyText, style: textTheme.bodyMedium),
          for (final source in stage.sources)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(source.name, style: textTheme.titleSmall),
                  if (source.formattedAddress case final address?)
                    Text(address, style: textTheme.bodySmall),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              FilledButton(
                onPressed: busy ? null : onPublish,
                child: const Text(kAiSessionPublishLabel),
              ),
              // NOT presented as a free undo: the generation consumed
              // quota (the row only reached `staged` via
              // `claim_ai_session_dispatch`, so the provider call really
              // happened) and discarding is terminal and COUNTED.
              TextButton(
                onPressed: busy ? null : onDiscard,
                child: const Text(kAiSessionDiscardLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// **THE ONE REDIRECT WIDGET. RULING 6 AND RULING 15 BOTH LAND HERE.**
///
/// Renders BOTH `kind: "redirect"` shapes — the safety refusal, which
/// carries a server-rendered `copy` and an EMPTY `offered`, and the
/// model's ordinary redirect, which carries NO `copy` — and renders a
/// `publish_nearby` refusal too, through the identical tree.
///
/// **IT NEVER ASKS WHICH IT GOT, AND IT HAS NOTHING TO ASK WITH.**
///
///   * the copy comes from ONE total call,
///     `resolveCopy(genericRedirectCopy: kAiSessionGenericRedirectCopy)`,
///     whose generic argument is REQUIRED so this call site cannot
///     discover the server's string by comparing against a default;
///   * `copy` is private on the model, so `copy != null` cannot compile;
///   * there is no `offered.isEmpty` branch, and that matters
///     independently: a refusal ALWAYS sends `[]`, so emptiness is a
///     strong oracle even though an ordinary redirect may legally send
///     `[]` too. The list is rendered by iteration, which draws nothing
///     when it is empty without ever testing that it is;
///   * `showSafetyResources` is read as a field rather than hardcoded,
///     but it is constant-true at all three of
///     `classifySessionContent`'s return points INCLUDING the allowed
///     one and in both redirect bodies — so it cannot be a signal, and
///     its value is not treated as one;
///   * there is no second analytics or telemetry call on either path,
///     because there is no branch on which to hang one.
///
/// A different icon, alignment, container colour, badge or text style
/// between the two shapes would be a visible oracle to anyone watching
/// the screen — the disclosure §8.1 forbids, in the one place a probing
/// requester can reach — which is why a widget test renders both and
/// compares the trees element by element, and another reads this
/// class's declarations and fails on any proxy.
///
/// It is a NEUTRAL INLINE NOTICE rather than an Attune bubble: §1's
/// "not a conversational AI persona", applied inside the session's own
/// UI, and §5.3's amendment means no redirect is a transcript turn at
/// all.
class AiSessionRedirectNotice extends StatelessWidget {
  const AiSessionRedirectNotice({
    super.key,
    required this.redirect,
    required this.onDismiss,
  });

  final AiSessionGeneratedRedirect redirect;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  // THE ONE CALL. Total, and blind to which shape
                  // arrived.
                  redirect.resolveCopy(
                    genericRedirectCopy: kAiSessionGenericRedirectCopy,
                  ),
                  style: textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          // Rendered BY ITERATION. Nothing tests the list's emptiness —
          // a `for` over an empty list draws nothing without asking,
          // whereas `if (offered.isNotEmpty)` would be the proxy.
          for (final mode in redirect.offered)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                mode == 'ideas' ? kAiSessionIdeasLabel : kAiSessionNearbyLabel,
                style: textTheme.labelLarge,
              ),
            ),
          if (redirect.showSafetyResources)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                kAiSessionSafetyResourcesLabel,
                style: textTheme.labelLarge,
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onDismiss, child: const Text('OK')),
          ),
        ],
      ),
    );
  }
}

/// Maps a §10 error to copy **by its CODE**, never by HTTP status —
/// five codes share 409, so a status-driven mapper would show one
/// message for five different situations with five different remedies.
class AiSessionErrorNotice extends StatelessWidget {
  const AiSessionErrorNotice({super.key, required this.error});

  final Object error;

  static String messageFor(Object error) {
    return switch (error) {
      // `state: "preparing"` is a SUCCESS, so this code never means
      // "waiting" — it belongs to a caller that tried to GENERATE
      // without approval.
      AiSessionApprovalRequiredError() =>
        'Approve the context before asking for something.',
      AiSessionContextChangedError() => kAiSessionContextChangedMessage,
      AiSessionBusyError() => 'Already working on this — hang on.',
      AiSessionRequestConflictError() =>
        'That request was already sent with different details.',
      AiSessionLimitReachedError() =>
        "You've reached the limit for now — try again later.",
      AiSessionRateLimitedError(retryAfterSeconds: final seconds) =>
        seconds != null ? 'Try again in $seconds seconds.' : 'Try again later.',
      AiSessionConsentRequiredError() => "Waiting for your partner's consent.",
      AiSessionUnavailableError() => 'This session is no longer available.',
      AiSessionContextTooLargeError() =>
        'There is too much context — turn off recent messages and try again.',
      AiSessionOverloadedError() => 'Attune is busy — try again shortly.',
      AiSessionLocationRequiredError() =>
        'Location is needed for nearby places.',
      AiSessionLocationExpiredError() =>
        'That location reading is stale — try again.',
      AiSessionRequestFailedError() => "That didn't go through — try again.",
      AiSessionProviderUnavailableError() =>
        "Attune couldn't reach its provider — try again.",
      AiSessionResultUnavailableError() =>
        'That result is no longer available.',
      AiSessionInvalidInputError() =>
        'Something about this request was invalid.',
      // §12's kill path: the SERVER refusing, which is the authority.
      AiSessionFeatureDisabledError() => kAiSessionUnavailableMessage,
      AiSessionInternalError() => 'Something went wrong — try again.',
      _ => 'Something went wrong — try again.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              messageFor(error),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionField extends StatelessWidget {
  const _InstructionField({
    required this.controller,
    required this.busy,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool busy;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !busy,
              decoration: const InputDecoration(
                hintText: 'Ask for something',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  icon: const Icon(Icons.send_rounded),
                  onPressed: () => onSubmit(),
                ),
        ],
      ),
    );
  }
}
