// Spec 2 §3.2 D1 (§3.15: shared-axis on Continue; an 8-item list; a closed
// country is §3.10 instead, opened as its own unanimated page; R-16, R-36).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/features/me/presentation/path_switch.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart'
    show PathChoiceOutcome;
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DatingHowStep extends ConsumerStatefulWidget {
  const DatingHowStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingHowStep> createState() => _DatingHowStepState();
}

class _DatingHowStepState extends ConsumerState<DatingHowStep> {
  bool _switching = false;

  /// T6 fix 1 (M-1): from "Not ready?" until its snackbar closes, D1 takes
  /// no other tap (the person is on 'Just for me' meanwhile).
  bool _switched = false;
  ScaffoldMessengerState? _messenger;
  bool _closedSent = false;

  @override
  void dispose() {
    // M-1: the snackbar never outlives D1 (a screen reader keeps a bar with
    // an action up until it is dismissed).
    final messenger = _messenger;
    if (_switched && messenger != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (messenger.mounted) messenger.hideCurrentSnackBar();
      });
    }
    super.dispose();
  }

  Future<void> _justMe() async {
    if (_switching || _switched) return;
    setState(() => _switching = true);
    final loc = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final reader = MediaQuery.of(context).accessibleNavigation;
    final outcome = await switchPath(
      context,
      ref,
      to: AppPath.justMe,
      oneTap: true,
    );
    if (!mounted) return;
    final done = outcome == PathChoiceOutcome.done;
    setState(() {
      _switching = false;
      _switched = done;
    });
    if (!done) return;
    var undone = false;
    _messenger = messenger;
    final bar = messenger.showSnackBar(
      SnackBar(
        content: Text(loc.dating_justMeDone),
        // §3.0: undo lasts at least 20 s with a screen reader on.
        duration:
            reader ? const Duration(seconds: 20) : const Duration(seconds: 5),
        action: SnackBarAction(
          label: loc.dating_undo,
          onPressed: () async {
            undone = true;
            if (mounted) await switchPath(context, ref, to: AppPath.dating);
          },
        ),
      ),
    );
    await bar.closed;
    if (!mounted) return;
    setState(() => _switched = false);
    if (!undone) widget.nav.toMe();
  }

  /// M-6: a closed country is §3.10's own page (never animated, §3.0).
  void _notOpen(DatingHome home) {
    if (_closedSent) return;
    _closedSent = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(
        DatingPaths.notOpenFor(
          country: home.country,
          region:
              home.state == DatingHomeState.regionClosed ? home.region : null,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final home =
        ref
            .watch(datingHomeProvider(ref.watch(datingAccountProvider)))
            .valueOrNull;
    if (home != null &&
        const {
          DatingHomeState.featureUnavailable,
          DatingHomeState.countryClosed,
          DatingHomeState.regionClosed,
        }.contains(home.state)) {
      _notOpen(home);
      return const Scaffold(body: SizedBox.shrink());
    }
    final open = ref.watch(datingAvailabilityProvider).valueOrNull;
    final first = home?.firstDropAt?.toLocal();
    final items = [
      loc.dating_how1,
      loc.dating_how2,
      loc.dating_how3,
      loc.dating_how4,
      loc.dating_how5,
      if (first != null) loc.dating_how6(MyDateFormat.toDate(first)),
      if (open != null && open.countries.isNotEmpty)
        loc.dating_how7(datingOpenList(loc, open)),
      loc.dating_how8,
    ];
    final style = Theme.of(context).textTheme.bodyLarge;
    final idle = !_switching && !_switched;
    return DatingStepFrame(
      step: 'how',
      title: loc.dating_howTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              // M-5: each item is one node that keeps its number ("1. …").
              child: MergeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i + 1}.  ', style: style),
                    Expanded(child: Text(items[i], style: style)),
                  ],
                ),
              ),
            ),
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.flow_slotSetUp,
        onPressed: idle ? () => widget.nav.next('looking-for') : null,
      ),
      more: [
        FlowSecondaryButton(
          label: loc.flow_slotNotReady,
          busy: _switching,
          onPressed: _switched ? null : _justMe,
        ),
        FlowTextLink(label: loc.dating_setUpLater, onPressed: widget.nav.toMe),
      ],
    );
  }
}
