// Spec 2 W3c (carries 1, 13): a lifecycle refusal in words, for D13 and
// Dating settings (the section keeps its own copy from Task 4). Calm for
// busy, reverify, not eligible and the pre-W4a gate; error red with an icon
// otherwise. Only the refusal's name reaches here (DatingLifecycleError):
// never the server's text.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DatingCalmLine extends StatelessWidget {
  const DatingCalmLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    ),
  );
}

List<Widget> datingLifecycleErrorRows(
  BuildContext context,
  AppLocalizations loc,
  DatingLifecycleError error, {
  VoidCallback? onVerify,
}) {
  Widget link(String label, VoidCallback onPressed) => FlowTextLink(
    label: label,
    alignment: AlignmentDirectional.centerStart,
    onPressed: onPressed,
  );
  return switch (error) {
    DatingLifecycleError.activationGatesNotMet => [
      DatingCalmLine(loc.dating_readyGates),
      if (onVerify != null) link(loc.dating_verifyTitle, onVerify),
    ],
    DatingLifecycleError.pathNotDating => [
      FlowErrorLine(text: loc.dating_errorPathNotDating, liveRegion: true),
      link(
        loc.dating_openHowYouUse,
        () => context.push(RouteNames.howYouUseAttune),
      ),
    ],
    DatingLifecycleError.consentRequired => [
      FlowErrorLine(text: loc.dating_errorConsent, liveRegion: true),
      link(
        loc.dating_sectionFinish,
        () => context.push(DatingPaths.step('privacy')),
      ),
    ],
    DatingLifecycleError.profileIncomplete ||
    DatingLifecycleError.activationRequired ||
    DatingLifecycleError.enrollmentIncomplete => [
      FlowErrorLine(text: loc.dating_errorIncomplete, liveRegion: true),
      link(
        loc.dating_sectionFinish,
        () => context.push(DatingPaths.step('how')),
      ),
    ],
    DatingLifecycleError.resumeGatesNotMet => [
      FlowErrorLine(text: loc.dating_errorResumeGates, liveRegion: true),
    ],
    // T11 carry B: activation refused as not eligible is the section's own
    // calm "isn't available" (never "can't resume", never why).
    DatingLifecycleError.notEligible => [
      DatingCalmLine(loc.dating_sectionUnavailable),
    ],
    DatingLifecycleError.reverifyDevice => [
      DatingCalmLine(loc.dating_sectionReverify),
    ],
    DatingLifecycleError.busy => [DatingCalmLine(loc.dating_busy)],
    DatingLifecycleError.rateLimited => [
      FlowErrorLine(text: loc.dating_errorRateLimited, liveRegion: true),
    ],
    _ => [FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true)],
  };
}
