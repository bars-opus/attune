// Spec 2 W4b (§3.3.4; carry 9; Task 6 I-4 ruling): what every
// reverify_device answer shows, wherever it comes from (a setup save, a
// lifecycle refusal, the gentle wait, settings, D11). A phone with an
// install id: the calm line and the way to the re-check on this phone
// (/dating/verify, behind the Dating lock). A phone without one: the calm
// device_unavailable line and no way to any check, since every check
// there could only answer the same. Calm in the theme's own colours (never
// error red), read out when it appears; never a server's text.
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_supabase_client.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Whether this phone can be checked: false when it has no install id (or
/// the keystore can't be read), null while that is still being read.
bool? datingDeviceReady(WidgetRef ref) {
  final ready = ref.watch(datingDeviceReadyProvider);
  if (ready.hasError) return false;
  return ready.valueOrNull;
}

class DatingReverifyLine extends ConsumerWidget {
  const DatingReverifyLine({super.key, this.offerCheck = true});

  /// False on the re-check itself (a link there would lead to itself).
  final bool offerCheck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final ready = datingDeviceReady(ref);
    if (ready == false) {
      return DatingCalmLine(loc.dating_deviceUnavailable);
    }
    final line = DatingCalmLine(loc.dating_sectionReverify);
    // Only once the phone is known to have an id (never while it is read).
    if (!offerCheck || ready != true) return line;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        line,
        FlowTextLink(
          label: loc.dating_verifyTitle,
          alignment: AlignmentDirectional.centerStart,
          onPressed: () => context.push(DatingPaths.verify),
        ),
      ],
    );
  }
}

/// Fix round 1 (M-3): whether a Dating read was refused because Dating
/// doesn't trust this phone (the repositories raise `<read>:<reason>`:
/// `profile:`, `lists:`, `photos:`, `preview:`).
bool datingReadNeedsReverify(Object? error) =>
    error is StateError && error.message.endsWith(':reverify_device');
