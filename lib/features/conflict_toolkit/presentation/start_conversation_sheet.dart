import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/conflict_toolkit/data/toolkit_texts.dart';
import 'package:attune/features/conflict_toolkit/presentation/toolkit_overflow.dart';

/// Spec 8 (B3 (d)): what happened, how it felt, what I need, what I'm
/// asking; assembled into the composer, never sent by itself.
Future<String?> showStartConversationSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: const StartConversationSheet(),
          ),
    );

class StartConversationSheet extends StatefulWidget {
  const StartConversationSheet({super.key});

  @override
  State<StartConversationSheet> createState() => _StartConversationSheetState();
}

class _StartConversationSheetState extends State<StartConversationSheet> {
  final _observation = TextEditingController();
  final _feeling = TextEditingController();
  final _request = TextEditingController();
  String? _need;

  @override
  void dispose() {
    for (final c in [_observation, _feeling, _request]) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _text => assembleConversationStart(
    observation: _observation.text,
    feeling: _feeling.text,
    need: _need,
    request: _request.text,
  );

  Widget _field(
    TextEditingController c,
    String key,
    String label,
    String prefix,
  ) => Padding(
    padding: EdgeInsets.only(top: Spacing.sm.h),
    child: TextField(
      key: Key(key),
      controller: c,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(labelText: label, prefixText: prefix),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final preview = _text;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ToolkitSheetTitle(
              title: 'Start a conversation',
              subtitle: 'What happened, not who they are.',
            ),
            _field(_observation, 'start-observation', 'What happened', 'When '),
            _field(_feeling, 'start-feeling', 'How it felt', 'I feel '),
            Gap(Spacing.md.h),
            Text('What I need', style: text.labelLarge),
            Gap(Spacing.xs.h),
            Wrap(
              spacing: Spacing.sm.w,
              runSpacing: Spacing.xs.h,
              children: [
                for (final entry in kConversationNeeds.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _need == entry.key,
                    onSelected:
                        (on) => setState(() => _need = on ? entry.key : null),
                  ),
              ],
            ),
            _field(_request, 'start-request', 'What I am asking', 'Would you '),
            if (preview != null) ...[
              Gap(Spacing.md.h),
              Text(preview, style: text.bodyMedium),
            ],
            Gap(Spacing.md.h),
            FilledButton(
              onPressed:
                  preview == null
                      ? null
                      : () => Navigator.pop(context, preview),
              child: const Text('Add to message'),
            ),
          ],
        ),
      ),
    );
  }
}
