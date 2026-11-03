import 'dart:async';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/constants.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/url_launcher_utils.dart';
import 'package:attune/features/auth/sign_up/data/age_gate_store.dart';
import 'package:attune/features/auth/sign_up/domain/birth_date_validator.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/birth_date_step.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/presentation/screens/onboarding_gate_v2.dart'
    show catchUpSignOutProvider;
import 'package:attune/features/settings/data/birth_date_settings_service.dart';
import 'package:attune/features/settings/models/settings_config.dart';
import 'package:attune/home/home_seams.dart' show homeAuthProvider;
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Settings -> Date of birth (Spec 1 §3.15, W6b), for a signed-in account
/// under flow_signin_v2 (where every account has one).
SettingsConfig? birthDateSetting(BuildContext context, WidgetRef ref) {
  if (!ref.watch(flowSignInV2Provider)) return null;
  final loc = AppLocalizations.of(context)!;
  return SettingsConfig(
    id: 'date_of_birth',
    title: loc.flow_dobSettingsTitle,
    subtitle: loc.flow_dobSettingsSubtitle,
    icon: Icons.badge_outlined,
    type: SettingsItemType.navigation,
    routeName: RouteNames.birthDateSettings,
    onTap: () => context.push(RouteNames.birthDateSettings),
    iconColor: Colors.indigo,
    order: 5,
  );
}

/// "Your age: {age}" (never the date); "Fix a mistake" once, within 7 days
/// of the declaration and only while Dating isn't active (the server
/// decides: get_my_birth_date_status); otherwise "To change this, contact
/// support." Fixing it is A2 again; under 18 is X1, as at sign-up.
class BirthDateSettingsScreen extends ConsumerStatefulWidget {
  const BirthDateSettingsScreen({super.key});

  @override
  ConsumerState<BirthDateSettingsScreen> createState() =>
      _BirthDateSettingsScreenState();
}

class _BirthDateSettingsScreenState
    extends ConsumerState<BirthDateSettingsScreen> {
  bool _fixing = false;
  String? _error;
  int _errorCount = 0;

  /// A notice on the status view ("Saved."). Why it can't be fixed is the
  /// status line itself, announced when a fix comes back closed.
  String? _notice;

  /// The under-18 stop runs once, whichever answer starts it.
  bool _stopping = false;

  AppLocalizations get _loc => AppLocalizations.of(context)!;

  void _back() {
    if (_fixing) {
      setState(() {
        _fixing = false;
        _error = null;
      });
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.settings);
    }
  }

  /// Under 18: the server holds the account. Block, clear, sign out, X1
  /// (the gate's order, rulings F-8, W2 M-3 and B3 W2 I-3). Everything is
  /// read now, so the stop finishes even if the screen goes; it runs once.
  Future<void> Function() _underAgeStop() {
    final ageGate = ref.read(ageGateStoreProvider);
    final routing = ref.read(routingNotifierProvider);
    final signOut = ref.read(catchUpSignOutProvider);
    final clearQueue = _queueClearer();
    final router = GoRouter.of(context);
    return () async {
      if (_stopping) return;
      _stopping = true;
      await ageGate.block().timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      );
      routing.setUnderAgeBlocked(true);
      await clearQueue();
      try {
        await signOut();
      } catch (error) {
        debugPrint('[dob-settings] sign-out failed: ${error.runtimeType}');
      }
      router.go('${RouteNames.ageStop}?from=account');
    };
  }

  /// Review B7 I-1: a status under 18 (only ever a held account, e.g. a
  /// correction whose answer was lost) stops as a not_eligible answer
  /// does. M-1: a failed load is announced (iOS reads no live region).
  void _onStatus(
    AsyncValue<BirthDateStatus>? previous,
    AsyncValue<BirthDateStatus> next,
  ) {
    if (next is AsyncError) {
      SemanticsService.announce(
        _loc.flow_dobSettingsLoadFailed,
        Directionality.of(context),
      );
      return;
    }
    if (next is AsyncData<BirthDateStatus> && ageIsUnder18(next.value.age)) {
      unawaited(_underAgeStop()());
    }
  }

  Future<void> _save(DateTime date) async {
    // Read before the call: the stop must finish even if the screen goes.
    final stopUnderAge = _underAgeStop();
    final outcome = await ref
        .read(birthDateSettingsServiceProvider)
        .correct(date);
    switch (outcome) {
      case BirthDateCorrection.notEligible:
        await stopUnderAge();
      case BirthDateCorrection.saved:
        if (!mounted) return;
        ref.invalidate(birthDateStatusProvider);
        setState(() {
          _fixing = false;
          _notice = _loc.flow_dobFixSaved;
        });
        SemanticsService.announce(
          _loc.flow_dobFixSaved,
          Directionality.of(context),
        );
      case BirthDateCorrection.closed:
        // Closed since the screen opened: the status, re-read, says
        // "To change this, contact support."
        if (!mounted) return;
        ref.invalidate(birthDateStatusProvider);
        setState(() {
          _fixing = false;
          _notice = null;
        });
        // Review B7 M-2: the bounce back says why.
        SemanticsService.announce(
          _loc.flow_dobSettingsContact,
          Directionality.of(context),
        );
      case BirthDateCorrection.failed:
        if (!mounted) return;
        setState(() {
          _error = _loc.flow_saveFailed;
          _errorCount++;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = _loc;
    // Above the A2 branch, so the status stays read while A2 shows.
    ref.listen(birthDateStatusProvider, _onStatus);
    if (_fixing) {
      return BirthDateStep(
        order: birthDateOrderFor(
          WidgetsBinding.instance.platformDispatcher.locale,
        ),
        todayUtc: _todayUtc(),
        title: loc.flow_dobFixTitle,
        errorText: _error,
        errorCount: _errorCount,
        onBack: _back,
        onSubmit: _save,
      );
    }
    final theme = Theme.of(context);
    final status = ref.watch(birthDateStatusProvider);
    final textStyle = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurface,
    );
    final waiting = FlowFrame(
      title: loc.flow_dobSettingsTitle,
      onBack: _back,
      body: Center(
        child: CircularProgressIndicator(
          semanticsLabel: loc.flow_accountChecking,
        ),
      ),
    );
    return status.when(
      loading: () => waiting,
      error:
          (_, __) => FlowFrame(
            title: loc.flow_dobSettingsTitle,
            onBack: _back,
            body: FlowErrorLine(
              text: loc.flow_dobSettingsLoadFailed,
              style: theme.textTheme.bodyMedium,
              liveRegion: true,
            ),
            actions: [
              FlowPrimaryButton(
                label: loc.flow_tryAgain,
                onPressed: () => ref.invalidate(birthDateStatusProvider),
              ),
            ],
          ),
      data: (value) {
        final age = value.age;
        // Under 18 is on its way to X1 (_onStatus): nothing to show.
        if (_stopping || ageIsUnder18(age)) return waiting;
        final until = value.correctUntil;
        // Review B7 M-3: the line and the button agree (open needs a date).
        final open = value.canCorrect && until != null;
        final notice = _notice;
        return FlowFrame(
          title: loc.flow_dobSettingsTitle,
          onBack: _back,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                age == null
                    ? loc.flow_dobSettingsNoAge
                    : loc.flow_dobSettingsAge(age),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                open
                    ? loc.flow_dobSettingsFixUntil(MyDateFormat.toDate(until))
                    : loc.flow_dobSettingsContact,
                style: textStyle,
              ),
              if (notice != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(notice, style: textStyle),
                ),
              ],
            ],
          ),
          actions: [
            if (open)
              FlowPrimaryButton(
                label: loc.flow_dobSettingsFix,
                onPressed:
                    () => setState(() {
                      _fixing = true;
                      _notice = null;
                    }),
              )
            else
              FlowPrimaryButton(
                label: loc.flow_holdContact,
                onPressed:
                    () => UrlLauncherUtils.launchEmail(
                      context: context,
                      email: AppConstants.supportEmail,
                    ),
              ),
          ],
        );
      },
    );
  }

  /// What this account left queued on the phone (the gate's clear, W2
  /// M-3): its onboarding scope and the pending invite code. Read before
  /// the call, like the block; never throws.
  Future<void> Function() _queueClearer() {
    final prefs = ref.read(sharedPreferencesProvider);
    String? userId;
    try {
      userId = ref.read(homeAuthProvider).currentUser?.id;
    } catch (error) {
      debugPrint('[dob-settings] no account: ${error.runtimeType}');
    }
    return () async {
      try {
        if (userId != null) {
          await OnboardingStore(
            prefs,
            scope: '${OnboardingStore.userScopePrefix}.$userId',
          ).reset();
        }
        await prefs.remove(OnboardingStore.pendingInviteCodeKey);
      } catch (error) {
        debugPrint('[dob-settings] queue not cleared: ${error.runtimeType}');
      }
    };
  }

  static DateTime _todayUtc() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }
}
