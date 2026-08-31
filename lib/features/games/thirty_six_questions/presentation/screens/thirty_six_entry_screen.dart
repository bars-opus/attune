import 'dart:async';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/providers/thirty_six_question_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Resume-or-start for the 36 Questions journey.
///
/// This decision lived inside the games hub, which is being removed, and
/// was the only thing standing between the chat sheet and the journey —
/// which is why 36 Questions was the one game routed to the hub rather
/// than to itself.
///
/// Replaces the screen it lands on rather than pushing over it, so Back
/// returns to chat instead of to a spinner that would immediately
/// re-decide.
class ThirtySixEntryScreen extends ConsumerStatefulWidget {
  const ThirtySixEntryScreen({super.key});

  @override
  ConsumerState<ThirtySixEntryScreen> createState() =>
      _ThirtySixEntryScreenState();
}

class _ThirtySixEntryScreenState extends ConsumerState<ThirtySixEntryScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_route());
  }

  Future<void> _route() async {
    try {
      final journey = await ref.read(activeThirtySixJourneyProvider.future);
      if (!mounted) return;

      // An existing journey resumes at its overview: chapters are
      // progressive, so dropping someone into chapter 1 would restart a
      // story they are partway through.
      if (journey != null) {
        context.pushReplacementNamed(
          'thirtySixJourneyOverview',
          extra: journey.id,
        );
        return;
      }

      final relationshipId = await ref.read(
        currentRelationshipIdProvider.future,
      );
      if (!mounted) return;
      if (relationshipId == null) {
        setState(() => _error = 'No active relationship found.');
        return;
      }

      final created = await ref
          .read(thirtySixQuestionRepositoryProvider)
          .createJourney(relationshipId: relationshipId);
      if (!mounted) return;

      final chapter = await ref.read(
        inviteToChapterProvider((journeyId: created.id, chapter: 1)).future,
      );
      if (!mounted) return;

      context.pushReplacementNamed(
        'thirtySixChapterInvitation',
        extra: (
          sessionId: chapter.sessionId,
          chapter: chapter.chapterNumber,
          isInitiator: true,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      // Shown rather than swallowed: this screen has no content of its
      // own, so a silent failure is an indefinite spinner.
      setState(() => _error = 'Could not open 36 Questions.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;

    return Scaffold(
      appBar: AppBar(title: const Text('36 Questions')),
      body: Center(
        child:
            error == null
                ? const CircularProgressIndicator()
                : Padding(
                  padding: EdgeInsets.all(Spacing.lg.w),
                  child: Text(error, textAlign: TextAlign.center),
                ),
      ),
    );
  }
}
