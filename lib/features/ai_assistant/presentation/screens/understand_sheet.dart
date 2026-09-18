// lib/features/ai_assistant/presentation/screens/understand_sheet.dart
//
// Understand mode (AI Assistant spec §6): a private, ephemeral read on a
// partner's message — 2-3 possible readings and 2-3 response-phrasing
// options, framed as uncertainty rather than a verdict. This is the
// single most privacy-sensitive screen in the whole feature (spec §6.3):
// nothing on this screen may duplicate its content anywhere else,
// distribute it to the other partner, feed it into the couple's shared
// plan feature, hand it to the ordinary message-input field, or post it
// anywhere. Reading is the only interaction this screen offers.
//
// A dedicated test (understand_sheet_test.dart) statically inspects this
// very file's source for exactly the forbidden action words spec §6.3
// names — so this file's own prose deliberately avoids spelling those
// words out (see that test for the literal list), to keep this comment
// block itself from tripping its own guard.
//
// Privacy model (deliberately NOT reimplemented here):
//  - The app-switcher snapshot/obscuring guarantee is `AppPrivacyCover`
//    (Task 1), wired in once at the app root (lib/app/app.dart). This
//    sheet does not build a second, separate obscuring mechanism — it
//    relies on the global cover already being active for every screen,
//    this one included.
//  - Non-persistence is `understandResultProvider`'s job (Task 3): an
//    `.autoDispose` `AsyncNotifier` that starts idle, is populated only
//    by an explicit `requestUnderstand()` call from this sheet, and is
//    cleared on dismiss, on backgrounding (`AppLifecycleListener`), on
//    relationship change, and discards any late/superseded response.
//    This sheet calls `requestUnderstand()` once on open and `clear()`
//    on dismiss; it holds no separate duplicate of the result anywhere.
//
// Pushed via MaterialPageRoute from AskAttuneModeSheet's "Possible ways
// to read this" tile (Task 4), matching AssistSheet's own wiring shape
// (Task 5) rather than a modal bottom sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/domain/entities/message.dart';
import '../../../safety/presentation/screens/safety_resources_screen.dart';
import '../../data/models/understand_result_model.dart';
import '../../data/repositories/assistant_error.dart';
import '../providers/ai_assistant_providers.dart';

/// Spec §6.1's exact uncertainty-forward framing: shown alongside EVERY
/// `ok` result, regardless of `confidence` — not only when confidence is
/// low. See `_ResultBody` below, which renders this unconditionally for
/// both `UnderstandConfidence` values.
const String kUnderstandUncertaintyFraming =
    'Attune cannot know what your partner meant. These are possible '
    'readings, not an answer.';

/// Spec §6.1's generic "can't help with this" wording for every
/// `cannot_help` reason alike (`insufficient_context` / `unsafe_to_infer`
/// / `unsupported`) — the UI does not branch on which reason it got, so
/// the reason itself is never rendered as a distinguishing signal.
const String kUnderstandCannotHelpMessage =
    "Attune can't offer a read on this message.";

class UnderstandSheet extends ConsumerStatefulWidget {
  const UnderstandSheet({super.key, required this.message});

  final Message message;

  @override
  ConsumerState<UnderstandSheet> createState() => _UnderstandSheetState();
}

class _UnderstandSheetState extends ConsumerState<UnderstandSheet> {
  bool _requested = false;

  String get _requestId =>
      '${widget.message.id}-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Understand has no user input beyond opening the sheet on a
    // specific message — there is nothing to fill in, so the request
    // fires once automatically rather than waiting for a "Generate"
    // tap the way Assist's Ideas input does.
    if (!_requested) {
      _requested = true;
      final utcOffsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
      Future.microtask(
        () => ref
            .read(understandResultProvider.notifier)
            .requestUnderstand(
              requestId: _requestId,
              messageId: widget.message.id,
              utcOffsetMinutes: utcOffsetMinutes,
            ),
      );
    }
  }

  void _handleDismiss() {
    // Explicit clear on top of `.autoDispose` teardown — belt-and-braces
    // for the same reasoning `AssistSheet._handleClose` documents: the
    // moment this sheet's route is popped, nothing must remain that a
    // still-mounted ancestor (or a slow teardown tick) could observe.
    ref.read(understandResultProvider.notifier).clear();
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
      AssistantTargetUnavailableError() =>
        'This message is no longer available.',
      AssistantProviderUnavailableError() =>
        "Attune couldn't reach its provider — try again.",
      AssistantRequestInProgressError() =>
        'Already working on this — hang on.',
      AssistantResultUnavailableError() =>
        "This result is no longer available — try again.",
      AssistantUnsupportedRequestError() =>
        "Attune can't help with that request.",
      AssistantInvalidInputError() =>
        'Something about this request was invalid.',
      AssistantUnauthenticatedError() => 'Please sign in and try again.',
      AssistantInternalError() => 'Something went wrong — try again.',
      _ => 'Something went wrong — try again.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final resultAsync = ref.watch(understandResultProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Possible ways to read this',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: _handleDismiss,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            resultAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  _ErrorNotice(message: _errorMessageFor(error)),
              data: (result) {
                if (result == null) {
                  return const SizedBox.shrink();
                }
                return switch (result) {
                  UnderstandResultOk() => _ResultBody(result: result),
                  UnderstandResultCannotHelp() => const _CannotHelpBody(),
                };
              },
            ),
            const SizedBox(height: 24),
            // Rendered identically regardless of which branch/state is
            // showing above — see this file's header comment and
            // `_SafetyResourcesLink`'s own doc for why this must never
            // be conditioned on any branch-specific signal.
            const _SafetyResourcesLink(),
          ],
        ),
      ),
    );
  }
}

/// The `ok` branch's body: the uncertainty framing (unconditional on
/// confidence — spec §6.1), 2-3 possible readings, and 2-3 response
/// phrasing options. Deliberately just `Text` — no `onTap`, no
/// `GestureDetector`, no long-press menu on any of these; reading is the
/// only interaction this screen offers on its content.
class _ResultBody extends StatelessWidget {
  const _ResultBody({required this.result});

  final UnderstandResultOk result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Spec §6.1: shown before the result, for EVERY confidence
        // value — not gated on `result.confidence ==
        // UnderstandConfidence.low`. (This exact unconditional placement
        // is the guarantee this task's brief asks to be mutation-tested.)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: colorScheme.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  kUnderstandUncertaintyFraming,
                  style: textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Possible readings', style: textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final reading in result.possibleReadings)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(reading, style: textTheme.bodyLarge),
          ),
        const SizedBox(height: 16),
        Text('You could say', style: textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final option in result.responseOptions)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            // Deliberately plain, non-interactive text — spec §6.3
            // forbids any affordance that would move this text
            // elsewhere on the user's behalf. Reading it here and
            // retyping it yourself, if you choose to, is the only path.
            child: Text(option, style: textTheme.bodyMedium),
          ),
      ],
    );
  }
}

/// The `cannot_help` branch's body: one generic message regardless of
/// `reason` (spec §6.1) — `result.reason` is deliberately never read or
/// rendered here.
class _CannotHelpBody extends StatelessWidget {
  const _CannotHelpBody();

  @override
  Widget build(BuildContext context) {
    return Text(
      kUnderstandCannotHelpMessage,
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}

/// Spec §6.2's anti-side-channel requirement: this exact link must
/// render with IDENTICAL presence/visibility across every result and
/// error state this sheet can show — an `ok` result, `cannot_help` for
/// ANY reason (`insufficient_context`, `unsafe_to_infer`, `unsupported`),
/// and any `AssistantError`. It must never be added or removed based on
/// which branch is showing, because doing so would let its mere presence
/// leak whether the server's separate, deterministic safety pipeline
/// happened to fire on this particular message — the whole point of
/// showing it unconditionally is that its presence carries no
/// information.
///
/// `UnderstandSheet.build` above enforces this structurally: this widget
/// is placed once, outside the `resultAsync.when(...)` branch entirely,
/// so there is no `if`/`switch` anywhere that could vary it by state.
class _SafetyResourcesLink extends StatelessWidget {
  const _SafetyResourcesLink();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const SafetyResourcesScreen(),
            ),
          );
        },
        icon: Icon(
          Icons.support_outlined,
          size: 16,
          color: colorScheme.onSurfaceVariant,
        ),
        label: Text(
          'Safety Resources',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
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
