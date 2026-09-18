// lib/features/ai_assistant/presentation/screens/assist_sheet.dart
//
// Assist mode (AI Assistant spec §5): the Ideas input (optional 1-300
// char instruction) or Nearby flow (location disclosure -> permission
// -> generate), the private preview once a draft resolves, and the
// Share/Edit-as-mine/Close actions.
//
// Pushed via MaterialPageRoute, matching AskAttuneModeSheet's own
// wiring shape (Task 4) rather than a modal bottom sheet — "sheet" here
// names the feature's screen, the same way AskAttuneModeSheet itself is
// a full Scaffold despite its name.
//
// [onShared] / [onEditAsMine] are explicit callbacks rather than a
// Navigator-result convention: this screen is always pushed, so the
// caller (the chat screen, wiring this sheet's outcome back into the
// composer or just popping) decides what "done" means. `onEditAsMine`
// receives ONLY the draft's `replyText` — see `_handleEditAsMine` below
// for why nothing else about the draft is reachable from that path.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/domain/entities/message.dart';
import '../../data/models/assist_draft_model.dart';
import '../../data/repositories/ai_assistant_repository.dart';
import '../../data/repositories/assistant_error.dart';
import '../../data/services/raw_location_service.dart';
import '../providers/ai_assistant_providers.dart';

/// Which Assist branch this sheet instance serves (spec §5.1). Mirrors
/// `AiAssistantRepository.requestAssist`'s `assistKind` wire values
/// (`'ideas'` / `'nearby'`) — no other client file in this feature has
/// introduced a typed enum for this yet (Tasks 2-4 all pass the bare
/// wire string straight through), so this is this task's own addition,
/// matching the brief's own stated `AssistSheet({..., required
/// AssistKind kind})` interface.
enum AssistKind {
  ideas,
  nearby;

  String get wireValue => switch (this) {
    AssistKind.ideas => 'ideas',
    AssistKind.nearby => 'nearby',
  };
}

/// Spec §5.2's exact Nearby location disclosure copy. Must be shown
/// BEFORE any OS permission prompt — see `_NearbyDisclosure` below,
/// which renders this and offers Allow/Not now with no call to
/// `RawLocationService` or the repository until Allow is tapped.
const String kNearbyLocationDisclosure =
    'Attune will use your approximate location to suggest nearby '
    'places. This is only used for this request and is not stored.';

/// Spec §11's exact expired-draft copy ("This suggestion expired—ask
/// again" in the spec's own em-dash-less prose; rendered here with a
/// spaced en dash to match this codebase's other user-facing copy
/// conventions elsewhere in the AI Assistant screens, e.g.
/// AskAttuneModeSheet's own punctuation) — never a generic failure
/// message, and never attempted via the RPC (see `_handleShare`).
const String kDraftExpiredMessage = 'This suggestion expired — ask again';

const int kIdeasInstructionMaxLength = 300;

class AssistSheet extends ConsumerStatefulWidget {
  const AssistSheet({
    super.key,
    required this.message,
    required this.kind,
    required this.onShared,
    required this.onEditAsMine,
  });

  final Message message;
  final AssistKind kind;

  /// Called after `Share in chat` succeeds. The caller (chat screen)
  /// decides what happens next (e.g. popping this route) — this sheet
  /// does not pop itself, matching the brief's "assert via a passed-in
  /// callback ... matching however this codebase's other sheets signal
  /// completion" guidance where no existing sheet in this feature has
  /// an established Navigator-result convention to copy yet.
  final VoidCallback onShared;

  /// Called when "Edit as my message" is tapped, with ONLY the draft's
  /// `replyText`. Never carries `assistant_payload`, sources, or any
  /// Attune label — sending happens later via the ordinary composer's
  /// own Send button, not as a side effect of this tap.
  final ValueChanged<String> onEditAsMine;

  @override
  ConsumerState<AssistSheet> createState() => _AssistSheetState();
}

class _AssistSheetState extends ConsumerState<AssistSheet> {
  final _instructionController = TextEditingController();
  bool _nearbyDisclosureAccepted = false;
  bool _sharing = false;
  String? _shareErrorMessage;

  @override
  void dispose() {
    _instructionController.dispose();
    super.dispose();
  }

  String get _requestId =>
      '${widget.message.id}-${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _generateIdeas() async {
    final instruction = _instructionController.text.trim();
    await ref
        .read(assistDraftProvider.notifier)
        .requestAssist(
          requestId: _requestId,
          messageId: widget.message.id,
          assistKind: AssistKind.ideas.wireValue,
          userInstruction: instruction.isEmpty ? null : instruction,
        );
  }

  Future<void> _generateNearby(RequesterLocation location) async {
    await ref
        .read(assistDraftProvider.notifier)
        .requestAssist(
          requestId: _requestId,
          messageId: widget.message.id,
          assistKind: AssistKind.nearby.wireValue,
          requesterLocation: location,
        );
  }

  Future<void> _handleNearbyAllow() async {
    setState(() => _nearbyDisclosureAccepted = true);
    final locationService = ref.read(rawLocationServiceProvider);
    final result = await locationService.getCurrentPosition();
    switch (result) {
      case RawPositionSuccess(
        :final latitude,
        :final longitude,
        :final accuracyM,
      ):
        await _generateNearby((
          latitude: latitude,
          longitude: longitude,
          accuracyM: accuracyM,
        ));
      case RawPositionDenied():
      case RawPositionServiceDisabled():
      case RawPositionFailure():
        // Declining/failing must not call the repository at all — this
        // IS the "declining consumes no quota" guarantee. Returning to
        // the disclosure (rather than showing a separate error state)
        // lets the user retry Allow without losing their place.
        if (mounted) setState(() => _nearbyDisclosureAccepted = false);
    }
  }

  Future<void> _handleShare(AssistDraftModel draft) async {
    if (DateTime.now().isAfter(draft.expiresAt)) {
      // Checked client-side, BEFORE calling the repository at all:
      // `share_ai_assist_draft` only raises a bare SQL exception on an
      // expired draft (20260950080000_ai_assist_draft_and_share_rpcs.sql),
      // which AiAssistantRepository's transport-error mapping folds
      // into the same generic `internalError()` as every other
      // unmapped RPC failure — there is no dedicated "expired"
      // AssistantError subtype to branch on AFTER the call. Spec §11's
      // "it never posts stale content" is a proactive guarantee, so
      // this sheet enforces it proactively rather than trying to
      // recognize the failure after attempting to post.
      setState(() => _shareErrorMessage = kDraftExpiredMessage);
      return;
    }

    setState(() {
      _sharing = true;
      _shareErrorMessage = null;
    });
    try {
      final repository = ref.read(aiAssistantRepositoryProvider);
      await repository.shareDraft(draft.draftId);
      if (!mounted) return;
      widget.onShared();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _shareErrorMessage = _errorMessageFor(error);
      });
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _handleEditAsMine(AssistDraftModel draft) {
    // Deliberately extracts ONLY replyText. `draft` itself carries
    // `suggestedPlanningItem`/`sources` depending on branch, but
    // neither is read here — there is no path from this method to
    // `assistant_payload`, and no RPC/repository call happens on this
    // path at all.
    final replyText = switch (draft) {
      AssistDraftIdeas(replyText: final text) => text,
      AssistDraftNearby(replyText: final text) => text,
    };
    widget.onEditAsMine(replyText);
  }

  void _handleClose() {
    ref.read(assistDraftProvider.notifier).clear();
    Navigator.of(context).pop();
  }

  String _errorMessageFor(Object error) {
    return switch (error) {
      AssistantRateLimitedError(retryAfterSeconds: final seconds) =>
        seconds != null
            ? 'Try again in $seconds seconds.'
            : 'Try again later.',
      AssistantConsentRequiredError() =>
        "Waiting for your partner's consent.",
      AssistantLocationRequiredError() =>
        'Location is required for Nearby suggestions.',
      AssistantNoResultsError() =>
        "Couldn't find anything nearby — try again.",
      AssistantTargetUnavailableError() =>
        'This message is no longer available.',
      AssistantProviderUnavailableError() =>
        "Attune couldn't reach its provider — try again.",
      AssistantRequestInProgressError() => 'Already working on this — hang on.',
      AssistantResultUnavailableError() => kDraftExpiredMessage,
      AssistantUnsupportedRequestError() =>
        "Attune can't help with that request.",
      AssistantInvalidInputError() => 'Something about this request was invalid.',
      AssistantUnauthenticatedError() => 'Please sign in and try again.',
      AssistantInternalError() => 'Something went wrong — try again.',
      _ => 'Something went wrong — try again.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final draftAsync = ref.watch(assistDraftProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.kind == AssistKind.ideas ? 'Get ideas' : 'Nearby',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _handleClose,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.kind == AssistKind.ideas)
              _IdeasInput(
                controller: _instructionController,
                loading: draftAsync.isLoading,
                onGenerate: _generateIdeas,
              )
            else
              _NearbyInput(
                disclosureAccepted: _nearbyDisclosureAccepted,
                loading: draftAsync.isLoading,
                onAllow: _handleNearbyAllow,
              ),
            const SizedBox(height: 24),
            draftAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorNotice(message: _errorMessageFor(error)),
              data: (draft) {
                if (draft == null) return const SizedBox.shrink();
                return _DraftPreview(
                  draft: draft,
                  sharing: _sharing,
                  shareError: _shareErrorMessage,
                  onShare: () => _handleShare(draft),
                  onEditAsMine: () => _handleEditAsMine(draft),
                  onClose: _handleClose,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _IdeasInput extends StatefulWidget {
  const _IdeasInput({
    required this.controller,
    required this.loading,
    required this.onGenerate,
  });

  final TextEditingController controller;
  final bool loading;
  final Future<void> Function() onGenerate;

  @override
  State<_IdeasInput> createState() => _IdeasInputState();
}

class _IdeasInputState extends State<_IdeasInput> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _overLimit =>
      widget.controller.text.length > kIdeasInstructionMaxLength;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Anything specific? (optional)',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'e.g. something low-key, indoors',
            border: const OutlineInputBorder(),
            errorText: _overLimit
                ? 'Keep it under $kIdeasInstructionMaxLength characters'
                : null,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: (widget.loading || _overLimit)
              ? null
              : () => widget.onGenerate(),
          child: widget.loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Generate'),
        ),
      ],
    );
  }
}

class _NearbyInput extends StatelessWidget {
  const _NearbyInput({
    required this.disclosureAccepted,
    required this.loading,
    required this.onAllow,
  });

  final bool disclosureAccepted;
  final bool loading;
  final Future<void> Function() onAllow;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    // The disclosure is shown up to and including while the location
    // read/generate request is in flight (disclosureAccepted only ever
    // flips back to false on decline/failure) — there is no separate
    // "requesting location..." screen to keep this minimal; the
    // `loading` branch above covers the in-flight visual instead.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kNearbyLocationDisclosure,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => onAllow(),
          child: const Text('Allow'),
        ),
      ],
    );
  }
}

class _DraftPreview extends StatelessWidget {
  const _DraftPreview({
    required this.draft,
    required this.sharing,
    required this.shareError,
    required this.onShare,
    required this.onEditAsMine,
    required this.onClose,
  });

  final AssistDraftModel draft;
  final bool sharing;
  final String? shareError;
  final VoidCallback onShare;
  final VoidCallback onEditAsMine;
  final VoidCallback onClose;

  String get _replyText => switch (draft) {
    AssistDraftIdeas(replyText: final text) => text,
    AssistDraftNearby(replyText: final text) => text,
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Private preview — only you can see this',
            style: textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(_replyText, style: textTheme.bodyLarge),
          if (draft is AssistDraftNearby)
            ...[
              const SizedBox(height: 12),
              for (final source in (draft as AssistDraftNearby).sources)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(source.name, style: textTheme.bodyMedium),
                ),
            ],
          if (shareError != null) ...[
            const SizedBox(height: 12),
            Text(
              shareError!,
              style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: sharing ? null : onShare,
                child: sharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Share in chat'),
              ),
              OutlinedButton(
                onPressed: sharing ? null : onEditAsMine,
                child: const Text('Edit as my message'),
              ),
              TextButton(
                onPressed: sharing ? null : onClose,
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}
