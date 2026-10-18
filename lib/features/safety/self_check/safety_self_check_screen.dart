import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/safety/self_check/safety_self_check_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The four items: HARK's published wording, "within the last year"
/// (plan review M1). Clinician authorship pending, so every line is marked
/// [DRAFT] and the launch-readiness test fails while it is reachable.
const safetySelfCheckItems = <String>[
  '[DRAFT] Within the last year, have you been humiliated or emotionally abused in other ways by your partner?',
  '[DRAFT] Within the last year, have you been afraid of your partner?',
  '[DRAFT] Within the last year, have you been raped or forced to have any kind of sexual activity by your partner?',
  '[DRAFT] Within the last year, have you been kicked, hit, slapped or otherwise physically hurt by your partner?',
];

const _choices = <(String, String)>[
  ('yes', 'Yes'),
  ('no', 'No'),
  ('prefer_not', 'Prefer not to say'),
];

/// Spec 8 (research 06 F14). Just for this person; the answers are never
/// stored and never shown again, here or anywhere.
class SafetySelfCheckScreen extends ConsumerStatefulWidget {
  const SafetySelfCheckScreen({super.key, required this.relationshipId});

  // Opened by constructor only (safety_self_check_row.dart): no route, so
  // no deep link can open it.

  final String relationshipId;

  @override
  ConsumerState<SafetySelfCheckScreen> createState() =>
      _SafetySelfCheckScreenState();
}

class _SafetySelfCheckScreenState extends ConsumerState<SafetySelfCheckScreen> {
  final _answers = <int, String>{};
  bool _sending = false;
  String? _card;

  Future<void> _done() async {
    setState(() => _sending = true);
    try {
      final card = await ref.read(safetySelfCheckServiceProvider).submit(
        widget.relationshipId,
        {for (var i = 0; i < 4; i++) 'q${i + 1}': _answers[i]!},
      );
      if (!mounted) return;
      // The answers leave memory with the questions.
      setState(() {
        _answers.clear();
        _card = card;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't send it. Try again.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final card = _card;
    return Scaffold(
      appBar: AppBar(title: const Text('A private check-in')),
      body: ListView(
        padding: EdgeInsets.all(Spacing.lg.w),
        children:
            card != null
                ? _after(context, card)
                : [
                  Text(
                    'Just for you. Your answers are never stored and never '
                    'shown to anyone, including your partner.',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Gap(Spacing.lg.h),
                  for (var i = 0; i < safetySelfCheckItems.length; i++) ...[
                    Text(safetySelfCheckItems[i], style: text.bodyLarge),
                    Gap(Spacing.sm.h),
                    Wrap(
                      spacing: Spacing.sm.w,
                      children: [
                        for (final (key, label) in _choices)
                          ChoiceChip(
                            key: ValueKey('safety-q${i + 1}-$key'),
                            label: Text(label),
                            selected: _answers[i] == key,
                            onSelected:
                                (_) => setState(() => _answers[i] = key),
                          ),
                      ],
                    ),
                    Gap(Spacing.lg.h),
                  ],
                  FilledButton(
                    onPressed:
                        _sending ||
                                _answers.length < safetySelfCheckItems.length
                            ? null
                            : _done,
                    child: const Text('Done'),
                  ),
                ],
      ),
    );
  }

  List<Widget> _after(BuildContext context, String card) {
    final text = Theme.of(context).textTheme;
    void openResources() => context.push(RouteNames.safetyResources);
    return switch (card) {
      'resources' => [
        Text("You don't have to face this alone.", style: text.titleLarge),
        Gap(Spacing.sm.h),
        Text(
          'Support is private and free to reach. You can call, text or read '
          'at your own pace, and leave whenever you need to.',
          style: text.bodyLarge,
        ),
        Gap(Spacing.lg.h),
        FilledButton(
          onPressed: openResources,
          child: const Text('See support options'),
        ),
      ],
      'plain' => [
        Text('Support is here whenever you want it.', style: text.titleMedium),
        Gap(Spacing.md.h),
        OutlinedButton(
          onPressed: openResources,
          child: const Text('Support options'),
        ),
      ],
      _ => [
        Text('Thank you.', style: text.titleMedium),
        Gap(Spacing.md.h),
        OutlinedButton(
          onPressed: () => Navigator.maybePop(context),
          child: const Text('Close'),
        ),
      ],
    };
  }
}
