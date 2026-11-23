// Spec 2 §3.2 D6 country note (§3.15: no animation; never logged; shown on
// the device only): full screen, the phone variant (R-18), then Save, Set a
// PIN first (the existing PIN setup, then back here), Go back.
import 'dart:async';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum DatingNoteChoice { save, back }

Future<DatingNoteChoice> showDatingCountryNote(
  BuildContext context, {
  required String country,
}) async {
  // Spec 2 W8a round 3 (Re-2-I1): never once Dating is blank (Go back's
  // answer: nothing is saved).
  if (datingSheetRefused) return DatingNoteChoice.back;
  // Round 4: a note removed from outside (the Dating lock's
  // closeDatingSheets) never completes its push, so its going answers too.
  final gone = Completer<DatingNoteChoice?>();
  void end(DatingNoteChoice? value) {
    if (!gone.isCompleted) gone.complete(value);
  }

  unawaited(
    Navigator.of(context)
        .push<DatingNoteChoice>(
          PageRouteBuilder<DatingNoteChoice>(
            // Round 4: a Dating sheet's name, so the Dating lock closes it
            // as it closes every other Dating sheet.
            settings: datingSheetSettings('country-note'),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            // Round 3 (Re-2-I1): a route of its own, over the meet step's
            // page: blank in quick exit's first frame, like every Dating
            // sheet.
            pageBuilder:
                (context, _, __) => _OnGone(
                  onGone: () => end(null),
                  child: DatingSheetTracker(child: _Note(country: country)),
                ),
          ),
        )
        .then(end),
  );
  return await gone.future ?? DatingNoteChoice.back;
}

/// Round 4: tells [onGone] when the note's route has left the tree.
class _OnGone extends StatefulWidget {
  const _OnGone({required this.onGone, required this.child});

  final VoidCallback onGone;
  final Widget child;

  @override
  State<_OnGone> createState() => _OnGoneState();
}

class _OnGoneState extends State<_OnGone> {
  @override
  void dispose() {
    widget.onGone();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Note extends StatelessWidget {
  const _Note({required this.country});

  final String country;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final style = Theme.of(context).textTheme.bodyLarge;
    return FlowFrame(
      title: loc.dating_noteTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            loc.dating_notePhone(datingCountryName(loc, country)),
            style: style,
          ),
          const SizedBox(height: Spacing.md),
          Text(loc.dating_noteThen, style: style),
        ],
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.dating_noteSave,
          onPressed: () => Navigator.of(context).pop(DatingNoteChoice.save),
        ),
        FlowSecondaryButton(
          label: loc.dating_noteSetPin,
          onPressed: () => context.push(RouteNames.safetyPin),
        ),
        FlowTextLink(
          label: loc.dating_noteBack,
          onPressed: () => Navigator.of(context).pop(DatingNoteChoice.back),
        ),
      ],
    );
  }
}
