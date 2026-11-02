import 'package:attune/i10n/generated/app_localizations.dart';

/// R1's registers (Spec 1 §3.8): how the invite message sounds.
enum InviteRegister { simple, casual, pidgin }

/// Pidgin is offered only after the Ghanaian cultural reviewer confirms
/// its wording (the W4 group gate). Flip to true in the change that records
/// that review; nothing else changes.
const bool kPidginRegisterReviewed = false;

/// The registers R1 offers, in order.
List<InviteRegister> offeredInviteRegisters() => [
  InviteRegister.simple,
  InviteRegister.casual,
  if (kPidginRegisterReviewed) InviteRegister.pidgin,
];

/// The message the invitee receives (§3.8 R1): the opening (with the
/// partner's first name, or without it and its comma), the optional
/// "I found this myself" line, the app link, then the code line, so the
/// code travels in every message. No AI vocabulary.
String inviteMessage(
  AppLocalizations loc, {
  required InviteRegister register,
  required String link,
  required String code,
  String? partnerFirstName,
  bool foundItMyself = false,
}) {
  final name = partnerFirstName?.trim() ?? '';
  final named = name.isNotEmpty;
  final opening = switch (register) {
    InviteRegister.simple =>
      named
          ? loc.flow_inviteMsgSimpleOpen(name)
          : loc.flow_inviteMsgSimpleOpenNoName,
    InviteRegister.casual =>
      named
          ? loc.flow_inviteMsgCasualOpen(name)
          : loc.flow_inviteMsgCasualOpenNoName,
    InviteRegister.pidgin =>
      named
          ? loc.flow_inviteMsgPidginOpen(name)
          : loc.flow_inviteMsgPidginOpenNoName,
  };
  final getLine = switch (register) {
    InviteRegister.simple => loc.flow_inviteMsgSimpleGet(link),
    InviteRegister.casual => loc.flow_inviteMsgCasualGet(link),
    InviteRegister.pidgin => loc.flow_inviteMsgPidginGet(link),
  };
  return [
    opening,
    if (foundItMyself) loc.flow_inviteMsgFoundMyself,
    getLine,
    loc.flow_inviteMsgOpenCode(code),
  ].join('\n');
}
