import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/i10n/generated/app_localizations.dart';

/// The words a person sees for an invite that failed (Spec 1 W4b; W4 plan
/// P-7): always the app's own `flow_*` copy, never the server's or the
/// service's English. Used by R1 and R3 (RI-3 keeps its own joining words,
/// preflight F-5).
String inviteErrorCopy(
  AppLocalizations loc,
  RelationshipInviteException error,
) {
  if (error.alreadyInRelationship) return loc.flow_joinAlreadyIn;
  if (error.signUpIncomplete) return loc.flow_inviteErrorSignUp;
  return switch (error.kind) {
    InviteRefusalKind.cap => loc.flow_inviteErrorCap,
    InviteRefusalKind.ageRequired => loc.flow_inviteErrorAgeRequired,
    // Preflight F-13: R1 and R3 make an invite; nothing is being linked.
    InviteRefusalKind.notPossible => loc.flow_inviteErrorNotPossible,
    InviteRefusalKind.phoneRequired => loc.flow_joinNotPossible,
    InviteRefusalKind.own => loc.flow_joinOwn,
    InviteRefusalKind.invalid ||
    InviteRefusalKind.alreadyAccepted => loc.flow_joinInvalid,
    InviteRefusalKind.expired => loc.flow_inviteCodeRefused,
    InviteRefusalKind.tryLater => loc.flow_joinTryLater,
    InviteRefusalKind.alreadyInRelationship => loc.flow_joinAlreadyIn,
    InviteRefusalKind.signUpIncomplete => loc.flow_inviteErrorSignUp,
    InviteRefusalKind.hold => loc.flow_holdTitle,
    // Preflight F-4: never RI-3's "couldn't find that invite" on R1/R3.
    InviteRefusalKind.unavailable || null => loc.flow_inviteErrorTryAgain,
  };
}
