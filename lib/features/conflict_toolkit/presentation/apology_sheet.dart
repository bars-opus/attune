import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/conflict_toolkit/data/toolkit_texts.dart';
import 'package:attune/features/conflict_toolkit/presentation/toolkit_overflow.dart';

/// Spec 8 (B3 (c)): four fields in the person's own words, assembled into
/// the composer. Never a request for forgiveness; the recipient has nothing
/// to accept.
Future<String?> showApologySheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: const ApologySheet(),
          ),
    );

class ApologySheet extends StatefulWidget {
  const ApologySheet({super.key});

  @override
  State<ApologySheet> createState() => _ApologySheetState();
}

class _ApologySheetState extends State<ApologySheet> {
  final _did = TextEditingController();
  final _cost = TextEditingController();
  final _repair = TextEditingController();
  final _different = TextEditingController();

  @override
  void dispose() {
    for (final c in [_did, _cost, _repair, _different]) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _text => assembleApology(
    did: _did.text,
    cost: _cost.text,
    repair: _repair.text,
    different: _different.text,
  );

  bool get _asksForgiveness => [
    _did,
    _cost,
    _repair,
    _different,
  ].any((c) => c.text.toLowerCase().contains('forgiv'));

  Widget _field(
    TextEditingController c,
    String key,
    String label,
    String prefix, {
    String? helper,
  }) => Padding(
    padding: EdgeInsets.only(top: Spacing.sm.h),
    child: TextField(
      key: Key(key),
      controller: c,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        helperText: helper,
        helperMaxLines: 2,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final preview = _text;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ToolkitSheetTitle(title: 'Help me apologise'),
            _field(_did, 'apology-did', 'What I did', "I'm sorry I "),
            _field(_cost, 'apology-cost', 'What it cost you', 'I know that '),
            _field(
              _repair,
              'apology-repair',
              "What I'll do to repair it",
              "To make it right, I'll ",
            ),
            _field(
              _different,
              'apology-different',
              "One thing I'll do differently",
              "Next time, I'll ",
            ),
            Gap(Spacing.sm.h),
            Text(
              kApologyLine,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (_asksForgiveness) ...[
              Gap(Spacing.xs.h),
              Text(kNoForgivenessNote, style: text.bodySmall),
            ],
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
