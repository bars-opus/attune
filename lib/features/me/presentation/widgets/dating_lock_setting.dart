import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_colors.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/presentation/widgets/confirm_safety_pin.dart';
import 'package:attune/features/settings/models/settings_config.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Settings -> Safety -> "Dating lock" (Spec 1 §3.9): shown under
/// flow_paths_v2 when the live home state says the path is Dating or
/// something is enrolled (never from the phone; review A-10). Null: hidden.
SettingsConfig? datingLockSetting(
  BuildContext context,
  WidgetRef ref,
  String userId,
) {
  if (userId.isEmpty || !ref.watch(flowPathsV2Provider)) return null;
  final home = ref.watch(homeStateProvider(userId));
  final show = home.path == AppPath.dating || (home.dating?.enrolled ?? false);
  if (!show) return null;
  final loc = AppLocalizations.of(context)!;
  return SettingsConfig(
    id: 'dating_lock',
    rowKey: const ValueKey('dating_lock_switch'),
    title: loc.flow_lockTitle,
    subtitle: loc.flow_lockSubtitle,
    icon: Icons.lock_outline,
    type: SettingsItemType.toggle,
    value: ref.watch(datingLockProvider).valueOrNull ?? false,
    onToggle: (on) => setDatingLock(context, ref, on),
    iconColor: flowAccent(context),
  );
}

/// On: with no Safety PIN, its setup comes first, and the lock is set only
/// once a PIN exists. Off: the PIN is asked first (true when none is set),
/// so someone holding the phone can't turn it off.
Future<void> setDatingLock(
  BuildContext context,
  WidgetRef ref,
  bool on, {
  SafetyPinStore? pins,
}) async {
  final store = pins ?? SafetyPinStore.instance;
  if (on) {
    if (!await store.hasPin()) {
      if (!context.mounted) return;
      await context.push(RouteNames.safetyPin);
      if (!await store.hasPin()) return;
    }
  } else {
    if (!context.mounted) return;
    if (!await confirmSafetyPin(context, store: store)) return;
  }
  await ref.read(datingLockProvider.notifier).set(on);
}
