import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz_providers;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/together_repository.dart';
import '../../domain/together_need.dart';
import '../together_providers.dart';

String togetherOptionLabel(TogetherOption o) {
  if (o.allDay) {
    final s = DateFormat.MMMEd().format(o.start);
    return o.end == null || o.end == o.start
        ? s
        : '$s – ${DateFormat.MMMEd().format(o.end!)}';
  }
  final s = DateFormat.MMMEd().add_jm().format(o.start);
  return o.end == null ? s : '$s – ${DateFormat.jm().format(o.end!)}';
}

Future<void> _sheet(BuildContext context, Widget child) async {
  final message = await BottomSheetUtils.showDocumentationBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.neutral,
    widget: child,
  );
  if (message != null && context.mounted) context.showSuccessSnackbar(message);
}

Future<void> showProposalSheet(BuildContext context, TogetherNeed need) =>
    _sheet(context, _ProposalSheet(need: need));

Future<void> showSentProposalSheet(BuildContext context, TogetherNeed need) =>
    _sheet(context, _SentProposalSheet(need: need));

Future<void> showHandoffSheet(BuildContext context, TogetherNeed need) =>
    _sheet(context, _HandoffSheet(need: need));

/// Runs a decision, refreshes Together, and closes with [done].
Future<void> _decide(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function(TogetherRepository) action,
  String done,
) async {
  try {
    await action(ref.read(togetherRepositoryProvider));
    ref.invalidate(togetherNeedsProvider);
    ref.invalidate(togetherRangeProvider);
    if (context.mounted) Navigator.of(context).pop(done);
  } on TogetherException catch (e) {
    if (!context.mounted) return;
    context.showErrorSnackbar(
      e.code == 'expired'
          ? 'This suggestion has expired.'
          : 'Could not do that. Please try again.',
    );
  } catch (_) {
    if (context.mounted) {
      context.showErrorSnackbar('Could not do that. Please try again.');
    }
  }
}

class _ProposalSheet extends ConsumerStatefulWidget {
  const _ProposalSheet({required this.need});
  final TogetherNeed need;
  @override
  ConsumerState<_ProposalSheet> createState() => _ProposalSheetState();
}

class _ProposalSheetState extends ConsumerState<_ProposalSheet> {
  String? _chosen;
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function(TogetherRepository) action,
    String done,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    await _decide(context, ref, action, done);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final partner =
        ref.watch(quiz_providers.partnerNameProvider).valueOrNull ??
        'Your partner';
    final need = widget.need;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          BottomSheetHeader(
            title: '$partner suggested',
            actionLabel: 'Accept',
            onPressed:
                _busy
                    ? null
                    : () {
                      final id = _chosen;
                      if (id == null) {
                        context.showErrorSnackbar('Pick a time first');
                        return;
                      }
                      _run(
                        (r) => r.decideProposal(
                          need.itemId,
                          optionId: id,
                          accept: true,
                        ),
                        'Added to Together.',
                      );
                    },
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
            child: Text(
              need.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Gap(Spacing.sm),
          for (final o in need.options)
            RadioListTile<String>(
              value: o.id,
              groupValue: _chosen,
              title: Text(togetherOptionLabel(o)),
              onChanged: (v) => setState(() => _chosen = v),
            ),
          AppDivider(),
          AppTextFormField(
            controller: _note,
            label: 'Add a note (optional)',
            maxLength: 200,
          ),
          InfoRowWidget(
            title: "Can't make these",
            subtitle: '',
            icon: Icons.event_busy_outlined,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap:
                _busy
                    ? null
                    : () => _run(
                      (r) => r.decideProposal(
                        need.itemId,
                        accept: false,
                        note:
                            _note.text.trim().isEmpty
                                ? null
                                : _note.text.trim(),
                      ),
                      'Sent.',
                    ),
          ),
          Gap(Spacing.xl),
        ],
      ),
    );
  }
}

class _SentProposalSheet extends ConsumerWidget {
  const _SentProposalSheet({required this.need});
  final TogetherNeed need;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner =
        ref.watch(quiz_providers.partnerNameProvider).valueOrNull ??
        'your partner';
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          BottomSheetHeader(title: need.title),
          InfoRowWidget(
            title: 'No reply yet',
            subtitle: 'Waiting for $partner',
            icon: Icons.hourglass_empty_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
          ),
          AppDivider(),
          InfoRowWidget(
            title: 'Withdraw',
            subtitle: '',
            icon: Icons.undo_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap:
                () => _decide(
                  context,
                  ref,
                  (r) => r.deleteEvent(need.itemId),
                  'Withdrawn.',
                ),
          ),
          Gap(Spacing.xl),
        ],
      ),
    );
  }
}

class _HandoffSheet extends ConsumerWidget {
  const _HandoffSheet({required this.need});
  final TogetherNeed need;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner =
        ref.watch(quiz_providers.partnerNameProvider).valueOrNull ??
        'Your partner';
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          BottomSheetHeader(title: '$partner asked you to take this on'),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
            child: Text(
              need.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Gap(Spacing.md),
          AppDivider(),
          InfoRowWidget(
            title: "I'll take it",
            subtitle: '',
            icon: Icons.check_circle_outline_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap:
                () => _decide(
                  context,
                  ref,
                  (r) => r.decideHandoff(need.itemId, accept: true),
                  "It's yours.",
                ),
          ),
          AppDivider(),
          InfoRowWidget(
            title: 'Not now',
            subtitle: '',
            icon: Icons.close_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap:
                () => _decide(
                  context,
                  ref,
                  (r) => r.decideHandoff(need.itemId, accept: false),
                  'Sent.',
                ),
          ),
          Gap(Spacing.xl),
        ],
      ),
    );
  }
}
