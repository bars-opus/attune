import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/forums/presentation/widgets/forum_topic_card.dart';

class ForumScreen extends StatelessWidget {
  const ForumScreen();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
        children: [
          SemanticContainerWidget(
            title: 'Read-only guest preview',
            content:
                'Browse relationship conversations anonymously. Posting and replies will unlock after phone verification',
            icon: Icons.visibility_outlined,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.1),
            borderColor: Theme.of(context).colorScheme.primary,
            iconColor: Theme.of(context).colorScheme.primary,
            textTheme: textTheme,
          ),

          Gap(Spacing.xl),
          const ForumTopicCard(
            title: 'Attachment',
            subtitle: 'Anxious, avoidant, secure, and the patterns between.',
            icon: Icons.psychology_alt_outlined,
          ),

          const ForumTopicCard(
            title: 'Conflict',
            subtitle:
                'Repair, difficult talks, tone, timing, and recurring loops.',
            icon: Icons.forum_outlined,
          ),
          const ForumTopicCard(
            title: 'Date ideas',
            subtitle:
                'Small rituals, intentional time, and what actually worked.',
            icon: Icons.favorite_border,
          ),
          const ForumTopicCard(
            title: 'General',
            subtitle: 'Open relationship questions from the Attune community.',
            icon: Icons.notes_outlined,
          ),
        ],
      ),
    );
  }
}
