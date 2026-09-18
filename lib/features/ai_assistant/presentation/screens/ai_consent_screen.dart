// lib/features/ai_assistant/presentation/screens/ai_consent_screen.dart
//
// The standalone AI-processing consent screen (AI Assistant spec §10.1):
// the approved third-party AI disclosure, a Grant/Decline choice, and
// the "waiting for your partner" state. Spec §3's "the first use also
// shows the approved ... disclosure and consent state" routes here from
// `AskAttuneModeSheet`'s own `_ConsentDisclosure` (see that file) rather
// than duplicating the grant flow in two places.
//
// Disclosure copy note (spec §14.1 gate 2): the wording below is a
// reasonable, spec-consistent placeholder-free draft — NOT final. Exact
// legal/product wording for §10.1's disclosure is a release-gate item
// this task cannot resolve unilaterally; see this task's report.
//
// Withdrawal lives on THIS screen, not a separate AI-settings screen:
// there is no existing dedicated AI-settings screen in this codebase to
// route to (chat_settings_screen.dart and the plain settings/ feature
// have no AI-consent-adjacent precedent), and this is the single place
// a user would naturally look to change a decision they made here. See
// the task report for the full reasoning.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/ai_assistant_repository.dart';
import '../providers/ai_assistant_providers.dart';

class AiConsentScreen extends ConsumerWidget {
  const AiConsentScreen({super.key, required this.relationshipId});

  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final consentAsync = ref.watch(aiConsentStatusProvider(relationshipId));

    return Scaffold(
      appBar: AppBar(
        title: Text('AI assistance', style: textTheme.titleMedium),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: consentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const _AiConsentErrorState(),
        data: (consent) => _AiConsentBody(
          relationshipId: relationshipId,
          consent: consent,
        ),
      ),
    );
  }
}

class _AiConsentErrorState extends StatelessWidget {
  const _AiConsentErrorState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          "Couldn't load AI assistance settings right now.",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

/// Renders exactly one of three states (spec §10.1), matching
/// `_ConsentGatedModeChoice`'s own three-state split in
/// ask_attune_mode_sheet.dart:
///
///  - caller has not granted: the disclosure + Grant/Decline choice;
///  - caller granted but partner has not: confirmation + "waiting for
///    your partner" + a "Withdraw consent" affordance;
///  - both granted: confirmation + a "Withdraw consent" affordance.
class _AiConsentBody extends ConsumerStatefulWidget {
  const _AiConsentBody({required this.relationshipId, required this.consent});

  final String relationshipId;
  final AiConsentStatus consent;

  @override
  ConsumerState<_AiConsentBody> createState() => _AiConsentBodyState();
}

class _AiConsentBodyState extends ConsumerState<_AiConsentBody> {
  bool _submitting = false;
  String? _errorMessage;

  Future<void> _recordConsent(String action) async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final repository = ref.read(aiAssistantRepositoryProvider);
      await repository.recordConsent(widget.relationshipId, action);
      ref.invalidate(aiConsentStatusProvider(widget.relationshipId));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = action == 'granted'
            ? "Couldn't record your consent. Please try again."
            : "Couldn't withdraw consent. Please try again.";
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmWithdraw() async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Withdraw AI assistance consent?'),
        content: const Text(
          'Neither you nor your partner will be able to use Ask Attune '
          'until consent is granted again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Withdraw',
              style: TextStyle(color: colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _recordConsent('withdrawn');
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final consent = widget.consent;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.privacy_tip_outlined, color: colorScheme.primary, size: 40),
          const SizedBox(height: 16),
          Text('AI assistance', style: textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(
            'Ask Attune sends the text of the message you choose, and '
            'your reply if you send one, to a third-party AI provider so '
            'it can generate ideas or a private read on a message. This '
            'text is never used to train the provider\'s models, and it '
            'is not stored by the provider beyond what is needed to '
            'return the result. Both partners in this relationship must '
            'agree before either of you can use Ask Attune on any '
            'message.',
            key: const ValueKey('ai-consent-disclosure-text'),
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Policy version ${consent.policyVersion}',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          if (_errorMessage != null) ...[
            Text(
              _errorMessage!,
              style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          if (!consent.callerGranted) ..._buildUngrantedActions(),
          if (consent.callerGranted) ..._buildGrantedState(consent, textTheme, colorScheme),
        ],
      ),
    );
  }

  List<Widget> _buildUngrantedActions() {
    return [
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const ValueKey('ai-consent-decline-button'),
              onPressed: _submitting ? null : () => Navigator.of(context).pop(),
              child: const Text('Decline'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              key: const ValueKey('ai-consent-grant-button'),
              onPressed: _submitting ? null : () => _recordConsent('granted'),
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('I understand'),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildGrantedState(
    AiConsentStatus consent,
    TextTheme textTheme,
    ColorScheme colorScheme,
  ) {
    return [
      Row(
        key: const ValueKey('ai-consent-granted-confirmation'),
        children: [
          Icon(Icons.check_circle_outline, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text("You've granted consent.", style: textTheme.bodyMedium),
          ),
        ],
      ),
      if (!consent.bothGranted) ...[
        const SizedBox(height: 16),
        Container(
          key: const ValueKey('ai-consent-waiting-for-partner'),
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
      ],
      const SizedBox(height: 24),
      OutlinedButton(
        key: const ValueKey('ai-consent-withdraw-button'),
        onPressed: _submitting ? null : _confirmWithdraw,
        style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
        child: _submitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Withdraw consent'),
      ),
    ];
  }
}
