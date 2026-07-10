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
          Text(
            'Browse relationship conversations anonymously. Posting and replies will unlock after phone verification.',
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 24),
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
