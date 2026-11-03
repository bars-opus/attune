import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/presentation/screens/about_us_question_flow.dart';
import 'package:attune/features/couple_profile/presentation/screens/about_us_screen.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/relationships/data/invite_device_store.dart';
import 'package:attune/features/relationships/data/relationship_lifecycle_service.dart';
import 'package:attune/features/settings/models/settings_config.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Where About us is entered (Spec 1 §3.8): R3's card during the wait
/// (the draft; widgets/about_us_card.dart), Together's "Start with" rows
/// and Settings -> Your relationship after linking, and the anniversary
/// reminder's sheet. Never before an invite exists. All behind
/// couple_profile (effective).

/// `/about-us/<relationship id>`, or `/about-us/draft` for the draft.
String aboutUsLocation(String? relationshipId) =>
    '/about-us/${relationshipId ?? 'draft'}';

/// One question, pushed over the current screen (an edit, or Together's
/// "Add your anniversary" as AU6).
Future<void> openAboutUsQuestion(
  BuildContext context,
  AboutUsTarget target,
  AboutUsQuestion question,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder:
        (route) => AboutUsQuestionFlow(
          target: target,
          only: question,
          onDone: () => Navigator.of(route).pop(),
        ),
  ),
);

/// Settings -> Your relationship -> "About us" (§3.8), after linking (the
/// shared space, also read-only while paused or in the ending window), or
/// the draft while an invite is pending.
SettingsConfig? aboutUsSetting(BuildContext context, WidgetRef ref) {
  if (!ref.watch(coupleProfileEnabledProvider)) return null;
  final userId = ref.watch(homeAuthProvider).currentUser?.id;
  if (userId == null) return null;
  final home = ref.watch(homeStateProvider(userId));
  final link = home.link;
  if (link != LinkState.linked &&
      link != LinkState.paused &&
      link != LinkState.endedWindow &&
      link != LinkState.pending) {
    return null;
  }
  final loc = AppLocalizations.of(context)!;
  return SettingsConfig(
    id: 'about_us',
    title: loc.aboutUs_title,
    subtitle: loc.aboutUs_settingsSubtitle,
    icon: Icons.favorite_border_rounded,
    type: SettingsItemType.navigation,
    iconColor: Colors.pink,
    order: 0,
    onTap: () async {
      if (link == LinkState.pending) {
        // Fix round 1 (review M-4): the draft names the partner R1 typed,
        // as R3's card does.
        await context.push(
          aboutUsLocation(null),
          extra: _pendingPartnerName(ref, home, userId),
        );
        return;
      }
      final id =
          home.linkDetail.relationshipId ??
          await ref.read(activeRelationshipIdProvider.future);
      if (id != null && context.mounted) {
        await context.push(aboutUsLocation(id));
      }
    },
  );
}

/// Preflight F-5: how long the anniversary reminder's About us check may
/// take before its offline state is shown (the service's own bound is
/// 15 s, too long for a tap).
const aboutUsReminderProbeBound = Duration(seconds: 2);

/// What the check found for one reminder.
enum _ReminderLink { follows, other, offline }

/// What the reminder's sheet was closed with.
enum _SheetChoice { change, form, times }

Future<_ReminderLink> _probeReminder(
  ProviderContainer container,
  AboutUsTarget target,
  String reminderId,
) async {
  try {
    final profile = await container
        .read(coupleProfileServiceProvider)
        .fetch(target)
        .timeout(aboutUsReminderProbeBound);
    return profile.anniversaryReminderId == reminderId
        ? _ReminderLink.follows
        : _ReminderLink.other;
  } on AboutUsOffline {
    return _ReminderLink.offline;
  } on TimeoutException {
    return _ReminderLink.offline;
  } catch (_) {
    // A refusal (the space can't be read): the edit form opens, and the
    // server's guard keeps About us's date.
    return _ReminderLink.other;
  }
}

/// The invited partner's first name while the invite waits: the server's,
/// else the one typed at R1 on this phone (RelationshipSpaceScreen's rule).
String? _pendingPartnerName(WidgetRef ref, HomeSnapshot home, String userId) {
  final server = home.linkDetail.partnerFirstName?.trim();
  if (server != null && server.isNotEmpty) return server;
  try {
    final typed =
        InviteDeviceStore(
          ref.read(sharedPreferencesProvider),
          userId: userId,
        ).partnerFirstName?.trim();
    return typed == null || typed.isEmpty ? null : typed;
  } catch (_) {
    return null;
  }
}

/// Together's anniversary reminder follows About us (§5.2): its sheet says
/// so and offers "Change in About us" (AU6) instead of the edit form.
/// True when a sheet was shown: [reminderId] is that reminder, or About us
/// couldn't be reached within [aboutUsReminderProbeBound] (F-5: the offline
/// state, with Try again, never a long wait or a form that can't save).
/// False for any other reminder or type, with couple_profile off, or when
/// About us refuses the read (the edit form opens, and the server's guard
/// keeps the date).
///
/// W5 final review I-2 (F-4 ruling) and M-2: with [onReminderTimes], the
/// sheet also offers "Reminder times and note", which opens the reminder
/// form locked (only the lead times and the note change, as the guard
/// allows). It is offered offline too, so the couple can always open
/// their own anniversary reminder.
Future<bool> showAboutUsReminderLink(
  BuildContext context, {
  required String reminderId,
  required String relationshipId,
  required String reminderType,
  required String title,
  Future<void> Function()? onReminderTimes,
}) async {
  if (reminderType != 'anniversary') return false;
  final ProviderContainer container;
  try {
    container = ProviderScope.containerOf(context, listen: false);
  } catch (_) {
    return false;
  }
  if (!container.read(coupleProfileEnabledProvider)) return false;
  final target = AboutUsTarget.shared(relationshipId);
  Future<_ReminderLink> probe() =>
      _probeReminder(container, target, reminderId);
  final first = await probe();
  if (first == _ReminderLink.other || !context.mounted) return false;
  final choice = await showModalBottomSheet<_SheetChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder:
        (sheet) => _AboutUsReminderSheet(
          title: title,
          first: first,
          probe: probe,
          offersTimes: onReminderTimes != null,
        ),
  );
  if (!context.mounted) return true;
  switch (choice) {
    case _SheetChoice.change:
      unawaited(
        openAboutUsQuestion(context, target, AboutUsQuestion.anniversary),
      );
      return true;
    case _SheetChoice.form:
      // Back online, and it isn't About us's reminder: the form.
      return false;
    case _SheetChoice.times:
      await onReminderTimes?.call();
      return true;
    case null:
      return true;
  }
}

class _AboutUsReminderSheet extends StatefulWidget {
  const _AboutUsReminderSheet({
    required this.title,
    required this.first,
    required this.probe,
    this.offersTimes = false,
  });

  final String title;
  final _ReminderLink first;
  final Future<_ReminderLink> Function() probe;

  /// Offers "Reminder times and note" (the locked form).
  final bool offersTimes;

  @override
  State<_AboutUsReminderSheet> createState() => _AboutUsReminderSheetState();
}

class _AboutUsReminderSheetState extends State<_AboutUsReminderSheet> {
  late _ReminderLink _link = widget.first;
  bool _busy = false;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    final link = await widget.probe();
    if (!mounted) return;
    if (link == _ReminderLink.other) {
      Navigator.of(context).pop(_SheetChoice.form);
      return;
    }
    setState(() {
      _busy = false;
      _link = link;
    });
    if (link == _ReminderLink.offline) {
      SemanticsService.announce(
        AppLocalizations.of(context)!.aboutUs_reminderOffline,
        Directionality.of(context),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final offline = _link == _ReminderLink.offline;
    return AllowLargeText(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            0,
            Spacing.lg,
            Spacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  widget.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              if (offline)
                // Fix round 1 (review M-2a): about the reminder tapped,
                // which may not be About us's.
                FlowErrorLine(
                  text: loc.aboutUs_reminderOffline,
                  liveRegion: true,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                )
              else
                Text(
                  loc.aboutUs_reminderFollows,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              const SizedBox(height: Spacing.lg),
              if (offline)
                FlowPrimaryButton(
                  label: loc.flow_tryAgain,
                  busy: _busy,
                  onPressed: _retry,
                )
              else
                FlowPrimaryButton(
                  label: loc.aboutUs_reminderChange,
                  onPressed:
                      () => Navigator.of(context).pop(_SheetChoice.change),
                ),
              const SizedBox(height: Spacing.sm),
              if (widget.offersTimes) ...[
                FlowSecondaryButton(
                  label: loc.aboutUs_reminderTimes,
                  onPressed:
                      () => Navigator.of(context).pop(_SheetChoice.times),
                ),
                const SizedBox(height: Spacing.sm),
              ],
              FlowSecondaryButton(
                label: loc.flow_close,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `/about-us/:relationshipId` (P-13): About us once the signed-in flags
/// are known (flowFlagsKnownProvider: unknown is not off, so a phone that
/// has never had them waits, or says it couldn't check and offers Try
/// again, and never closes About us for good); with couple_profile off it
/// calls [onUnavailable] (Home), so no deep link reaches About us.
class AboutUsRoutePage extends ConsumerStatefulWidget {
  const AboutUsRoutePage({
    super.key,
    required this.target,
    required this.onClose,
    required this.onUnavailable,
    this.partnerName,
  });

  final AboutUsTarget target;
  final VoidCallback onClose;
  final VoidCallback onUnavailable;
  final String? partnerName;

  @override
  ConsumerState<AboutUsRoutePage> createState() => _AboutUsRoutePageState();
}

class _AboutUsRoutePageState extends ConsumerState<AboutUsRoutePage> {
  bool _leaving = false;

  Widget _leave() {
    if (!_leaving) {
      _leaving = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onUnavailable();
      });
    }
    return const Scaffold(body: SizedBox.shrink());
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(flowFlagsKnownProvider)) {
      final loc = AppLocalizations.of(context)!;
      final checking = ref.watch(flowFlagsProvider).isLoading;
      return FlowFrame(
        title: loc.aboutUs_title,
        onBack: widget.onClose,
        body:
            checking
                ? LinearProgressIndicator(semanticsLabel: loc.aboutUs_title)
                : FlowErrorLine(
                  text: loc.aboutUs_loadFailed,
                  liveRegion: true,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
        actions: [
          if (!checking)
            FlowPrimaryButton(
              label: loc.flow_tryAgain,
              onPressed: () => ref.invalidate(flowFlagsProvider),
            ),
        ],
      );
    }
    if (!ref.watch(coupleProfileEnabledProvider)) return _leave();
    _leaving = false;
    return AboutUsScreen(
      target: widget.target,
      partnerName: widget.partnerName,
      onClose: widget.onClose,
    );
  }
}
