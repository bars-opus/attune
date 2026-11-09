// Spec 2 §3.2 D6 country note (§3.15: no animation; never logged; shown on
// the device only): full screen, the phone variant (R-18), then Save, Set a
// PIN first (the existing PIN setup, then back here), Go back.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum DatingNoteChoice { save, back }

Future<DatingNoteChoice> showDatingCountryNote(
  BuildContext context, {
  required String country,
}) async {
  final choice = await Navigator.of(context).push<DatingNoteChoice>(
    PageRouteBuilder<DatingNoteChoice>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, __) => _Note(country: country),
    ),
  );
  return choice ?? DatingNoteChoice.back;
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
