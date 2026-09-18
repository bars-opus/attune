// lib/features/ai_assistant/presentation/screens/ask_attune_mode_sheet.dart
//
// The "Ask Attune" mode-choice screen (AI Assistant spec §3): offers the
// two modes on a target message — Assist ("Get ideas") and Understand
// ("Possible ways to read this") — and gates BOTH behind the shared
// consent state (spec §10.1) before either can proceed.
//
// Pushed via MaterialPageRoute from the focused-message-actions menu,
// the same wiring shape message_bubble.dart already uses for the Info
// action (_buildInfoOpener/_openMessageInfo) — see that file's own
// comment on why the NavigatorState is resolved at long-press time
// rather than inside the tapped callback.
//
// Deliberately takes the [Message] itself, matching MessageInfoScreen's
// own reasoning: this is a point-in-time snapshot of what the menu was
// already showing, so the sheet stays consistent with whatever the user
// long-pressed even if the row changes moments later.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/providers/auth_provider.dart';
import '../../../chat/domain/entities/message.dart';
import '../providers/ai_assistant_providers.dart';
import 'assist_sheet.dart';

class AskAttuneModeSheet extends ConsumerWidget {
  const AskAttuneModeSheet({super.key, required this.message});

  final Message message;

  /// Spec §3: "Understand is available only when
  /// `message.sender_id != auth.uid()`." A UX gate only — the
  /// ai-understand edge function independently enforces the same rule
  /// server-side — but the client must not even offer the option on
  /// the caller's own message.
  bool _understandAvailable(String? currentUserId) {
    if (currentUserId == null) return false;
    return message.senderId != currentUserId;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final currentUserId = ref.watch(currentUserProvider)?.id;
    final understandAvailable = _understandAvailable(currentUserId);

    final relationshipIdAsync = ref.watch(currentRelationshipIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Ask Attune', style: textTheme.titleMedium),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: relationshipIdAsync.when(
        loading:
            () => const Center(child: CircularProgressIndicator()),
        error:
            (_, __) => const _AskAttuneErrorState(
              message: "Couldn't load Ask Attune right now.",
            ),
        data: (relationshipId) {
          if (relationshipId == null) {
            return const _AskAttuneErrorState(
              message: "Couldn't load Ask Attune right now.",
            );
          }
          return _ConsentGatedModeChoice(
            relationshipId: relationshipId,
            message: message,
            understandAvailable: understandAvailable,
            colorScheme: colorScheme,
            textTheme: textTheme,
          );
        },
      ),
    );
  }
}

class _AskAttuneErrorState extends StatelessWidget {
  const _AskAttuneErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

/// Watches [aiConsentStatusProvider] for [relationshipId] and renders
/// exactly one of three states (spec §10.1):
///
///  - not yet loaded / error: a loading/error state, no mode offered;
///  - caller has not granted: the disclosure/consent prompt, neither
///    mode proceeds until it resolves;
///  - caller granted but partner has not: the caller's own state plus
///    "Waiting for your partner's consent" — selecting a mode is a
///    no-op, it must not call either edge function;
///  - both granted: the two mode tiles are live.
class _ConsentGatedModeChoice extends ConsumerWidget {
  const _ConsentGatedModeChoice({
    required this.relationshipId,
    required this.message,
    required this.understandAvailable,
    required this.colorScheme,
    required this.textTheme,
  });

  final String relationshipId;
  final Message message;
  final bool understandAvailable;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consentAsync = ref.watch(aiConsentStatusProvider(relationshipId));

    return consentAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (_, __) => const _AskAttuneErrorState(
            message: "Couldn't load Ask Attune right now.",
          ),
      data: (consent) {
        if (!consent.callerGranted) {
          return _ConsentDisclosure(relationshipId: relationshipId);
        }

        return _ModeChoiceList(
          message: message,
          waitingForPartner: !consent.bothGranted,
          understandAvailable: understandAvailable,
          colorScheme: colorScheme,
          textTheme: textTheme,
        );
      },
    );
  }
}

/// Spec §10.1's first-use disclosure: shown before the caller has
/// granted consent for this relationship. Neither mode is offered here
/// at all — granting is the only action available — so there is no
/// path from this state into either edge function.
class _ConsentDisclosure extends ConsumerStatefulWidget {
  const _ConsentDisclosure({required this.relationshipId});

  final String relationshipId;

  @override
  ConsumerState<_ConsentDisclosure> createState() =>
      _ConsentDisclosureState();
}

class _ConsentDisclosureState extends ConsumerState<_ConsentDisclosure> {
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.privacy_tip_outlined, color: colorScheme.primary, size: 40),
          const SizedBox(height: 16),
          Text(
            'Before you use Ask Attune',
            style: textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            'This feature sends chat text to a third-party AI provider to '
            'generate ideas or a private read on a message. It is never '
            'used to train the provider\'s models. Both partners must '
            'agree before either can use it.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed:
                _submitting
                    ? null
                    : () async {
                      setState(() => _submitting = true);
                      // Task 5/6 own the actual grant RPC call; this
                      // sheet's job is only to show the gate and stop
                      // here until it resolves. Re-reading the provider
                      // is what will surface a grant made elsewhere.
                      ref.invalidate(
                        aiConsentStatusProvider(widget.relationshipId),
                      );
                      if (mounted) setState(() => _submitting = false);
                    },
            child:
                _submitting
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('I understand'),
          ),
        ],
      ),
    );
  }
}

class _ModeChoiceList extends StatelessWidget {
  const _ModeChoiceList({
    required this.message,
    required this.waitingForPartner,
    required this.understandAvailable,
    required this.colorScheme,
    required this.textTheme,
  });

  final Message message;
  final bool waitingForPartner;
  final bool understandAvailable;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (waitingForPartner) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.hourglass_empty, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Waiting for your partner's consent",
                      style: textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          _ModeTile(
            key: const ValueKey('ask-attune-mode-assist'),
            icon: Icons.lightbulb_outline,
            title: 'Get ideas',
            subtitle: 'Create suggestions you can preview and choose to share.',
            enabled: !waitingForPartner,
            onTap: waitingForPartner
                ? null
                : () => _chooseAssistKindThenOpen(context, message),
          ),
          const SizedBox(height: 12),
          if (understandAvailable)
            _ModeTile(
              key: const ValueKey('ask-attune-mode-understand'),
              icon: Icons.psychology_outlined,
              title: 'Possible ways to read this',
              subtitle:
                  "Private to you. Attune cannot know what your partner meant.",
              enabled: !waitingForPartner,
              onTap: waitingForPartner ? null : () {},
            ),
        ],
      ),
    );
  }
}

/// Assist supports two bounded jobs (spec §5.1: Ideas and Nearby), but
/// this screen offers only one "Get ideas" tile, matching the spec's
/// own two-tile layout (Assist vs Understand) exactly — there is no
/// third top-level tile for Nearby. So tapping "Get ideas" asks which
/// of the two Assist jobs the user wants via a lightweight modal picker
/// BEFORE pushing `AssistSheet`, which itself takes a required `kind`
/// (Task 5's own interface) rather than choosing internally.
Future<void> _chooseAssistKindThenOpen(
  BuildContext context,
  Message message,
) async {
  final kind = await showModalBottomSheet<AssistKind>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('assist-kind-ideas'),
              leading: const Icon(Icons.lightbulb_outline),
              title: const Text('Ideas'),
              subtitle: const Text('Brainstorm date themes, activities, gifts.'),
              onTap: () => Navigator.of(sheetContext).pop(AssistKind.ideas),
            ),
            ListTile(
              key: const ValueKey('assist-kind-nearby'),
              leading: const Icon(Icons.place_outlined),
              title: const Text('Nearby'),
              subtitle: const Text('Find real places around a location you choose.'),
              onTap: () => Navigator.of(sheetContext).pop(AssistKind.nearby),
            ),
          ],
        ),
      );
    },
  );
  if (kind == null || !context.mounted) return;

  final navigator = Navigator.of(context);
  // `AssistSheet`'s own two completion callbacks both close it; on
  // "Edit as my message" the edited text is popped as this route's
  // result (`AskAttuneModeSheet`'s own push is currently `void` at its
  // call site in message_bubble.dart, so nothing yet reads this value
  // further up — dropping the text into the live chat composer is a
  // deliberate deferral, see this task's report's deviations section:
  // it requires threading a new callback through
  // message_bubble.dart/message_actions_sheet.dart/chat_screen.dart,
  // none of which are in this task's file list, and chat_screen.dart
  // is exactly the kind of shared/composer-state file a surgical task
  // should not touch without a dedicated review of its own).
  navigator.push<String>(
    MaterialPageRoute(
      builder: (_) => AssistSheet(
        message: message,
        kind: kind,
        onShared: () => navigator.pop(),
        onEditAsMine: (text) => navigator.pop(text),
      ),
    ),
  );
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: colorScheme.primary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
