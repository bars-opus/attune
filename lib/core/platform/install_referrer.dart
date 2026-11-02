import 'dart:io' show Platform;

import 'package:attune/core/platform/install_referrer_keys.dart';
import 'package:attune/core/platform/install_referrer_prefill.dart';
import 'package:attune/features/auth/sign_up/domain/invite_code.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:flutter/foundation.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:attune/core/platform/install_referrer_keys.dart';

/// The Play Install Referrer, once (Spec 1 §3.8 RI, W4b): the invite web
/// page appends `invite_code=K7P2QM` to its Play link, so a person who
/// installs from an invite has the code waiting, as if they had opened the
/// link. Android only; iOS types the code. Read once per install, on any
/// outcome, and never sent anywhere (nor logged: only an error's type is).
typedef InstallReferrerSource = Future<String?> Function();

Future<String?> _playReferrer() async {
  final details = await PlayInstallReferrer.installReferrer;
  return details.installReferrer;
}

/// The invite code in a Play referrer string (URL-encoded query, e.g.
/// `utm_source=invite&invite_code=K7P2QM`), or null.
String? inviteCodeFromReferrer(String? referrer) {
  if (referrer == null || referrer.isEmpty) return null;
  try {
    final query = Uri.splitQueryString(referrer);
    final raw = query['invite_code'];
    return raw == null ? null : normalizeInviteCode(raw);
  } catch (_) {
    return null;
  }
}

/// Reads the referrer once and keeps its code for RI-1's code field only
/// (InstallReferrerPrefill; final review #1), unless a link's code is
/// already waiting. Never the claimable invite slot: anyone can craft a
/// Play link with a code, so joining it always takes the person's own tap
/// on RI-1 (and RI-3 under flow_couples_v2), never a silent accept.
/// Never throws; returns the kept code, or null.
///
/// Batch-6 review I-1: [signedIn] (a session at boot) means this is an
/// update's first launch, not the install's: the read is marked done and
/// nothing is stored, so no signed-in account claims a referrer code or
/// loses the code it already had waiting.
Future<String?> readInstallReferrerInvite(
  SharedPreferences prefs, {
  InstallReferrerSource? source,
  bool? isAndroid,
  bool signedIn = false,
}) async {
  try {
    if (!(isAndroid ?? (!kIsWeb && Platform.isAndroid))) return null;
    if (prefs.getBool(kInstallReferrerReadKey) ?? false) return null;
    await prefs.setBool(kInstallReferrerReadKey, true);
    if (signedIn) return null;
    final code = inviteCodeFromReferrer(await (source ?? _playReferrer)());
    if (code == null) return null;
    final anonymous = OnboardingStore(
      prefs,
      scope: OnboardingStore.anonymousScope,
    );
    if (anonymous.pendingInviteCode != null) return null;
    await InstallReferrerPrefill.save(prefs, code);
    return code;
  } catch (error) {
    debugPrint('[install-referrer] not read: ${error.runtimeType}');
    return null;
  }
}
