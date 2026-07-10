// Add to your chat composer widget

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/settings/utility/settings_exports.dart';

class TranslatorButton extends ConsumerWidget {
  final TextEditingController composerController;
  final VoidCallback onTranslate;

  const TranslatorButton({
    super.key,
    required this.composerController,
    required this.onTranslate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasText = composerController.text.trim().isNotEmpty;

    return IconButton(
      icon: const Icon(Icons.help_outline, size: 22),
      tooltip: 'Help me say this',
      onPressed: hasText ? onTranslate : null,
      color:
          hasText
              ? colorScheme.primary
              : colorScheme.onSurface.withOpacity(0.3),
    );
  }
}
