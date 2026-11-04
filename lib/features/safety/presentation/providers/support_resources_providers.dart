import 'dart:async';

import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/features/safety/data/support_resources_repository.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// support_resources_v2 (Spec 1 §2.5, W7a), from the anon config: live,
/// else the cached copy; off until either is known (today's screen).
final supportResourcesV2Provider = Provider<bool>((ref) {
  final config =
      ref.watch(
        publicAppConfigProvider.select((config) => config.valueOrNull),
      ) ??
      ref.watch(cachedPublicAppConfigProvider);
  return config?.supportResourcesV2 ?? false;
});

final supportResourcesRepositoryProvider = Provider<SupportResourcesRepository>(
  (ref) => SupportResourcesRepository(
    rpc: (fn, params) => Supabase.instance.client.rpc(fn, params: params),
    loadBundled:
        () => rootBundle.loadString('assets/support_resources/catalogue.json'),
  ),
);

/// The country chosen on the screen, this run only: never stored, so
/// nothing on the phone says someone looked for help (plan P-6).
final supportCountryOverrideProvider = StateProvider<String?>((ref) => null);

/// The country to show: the one chosen, else the SIM's, else the phone's
/// region; null when none is known.
final supportCountryProvider = FutureProvider<String?>((ref) async {
  final chosen = ref.watch(supportCountryOverrideProvider);
  if (chosen != null) return normaliseSupportCountry(chosen);
  final device = await ref.watch(deviceCountryProvider.future);
  return normaliseSupportCountry(device.sim ?? device.region);
});

/// autoDispose (final review M-6): a bundle answer (offline) is not kept
/// for the rest of the run; the next open asks the server again. While the
/// screen is open its list never changes under the person's finger.
final supportResourcesProvider = FutureProvider.autoDispose.family<
  SupportResources,
  String?
>((ref, country) => ref.read(supportResourcesRepositoryProvider).load(country));

/// Opens a tel:, sms: or https: link (replaceable in tests). Only ever
/// after the person confirmed it (§3, the manual's promise).
///
/// `launchUrl` directly, never `canLaunchUrl` first (W7 ruling PF-H3):
/// neither the Android `<queries>` nor the iOS `LSApplicationQueriesSchemes`
/// list declares tel: or sms:, so `canLaunchUrl` answers false on real
/// phones and the call would never be offered to the dialer.
final supportLauncherProvider =
    Provider<Future<void> Function(BuildContext context, String url)>(
      (ref) => openSupportUrl,
    );

/// [supportLauncherProvider]'s default: a SnackBar when nothing opened.
Future<void> openSupportUrl(BuildContext context, String url) async {
  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    opened = false;
  }
  if (opened || !context.mounted) return;
  final loc = AppLocalizations.of(context)!;
  // Never animated (§2.2), and spoken on iOS too (§2.3; Android's live
  // region alone reaches TalkBack only).
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(loc.support_cannotOpen)),
    snackBarAnimationStyle: AnimationStyle.noAnimation,
  );
  unawaited(
    SemanticsService.announce(
      loc.support_cannotOpen,
      Directionality.of(context),
    ),
  );
}
