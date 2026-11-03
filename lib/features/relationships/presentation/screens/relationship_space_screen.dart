import 'dart:async';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/core/notifications/presentation/widgets/push_ask_row.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/couple_profile/presentation/widgets/about_us_card.dart';
import 'package:attune/features/me/presentation/widgets/journal_reminder_row.dart';
import 'package:attune/features/me/presentation/widgets/more_ways_sheet.dart';
import 'package:attune/features/me/presentation/widgets/your_space_section.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/pending_invite_guide.dart';
import 'package:attune/features/relationships/data/invite_device_store.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/invite_error_copy.dart';
import 'package:attune/features/relationships/presentation/widgets/relationship_lifecycle_card.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// R3 · Your space while you wait (Spec 1 §3.8): Tab 2 on the Relationship
/// path when not linked. Pending: the invite (Send again, Cancel this
/// invite), today's waiting guidance, a first note and a quiz. None: "Invite
/// your partner". Paused or inside the ending window: the lifecycle card.
/// After the window: one "More ways" row. Never anything about Dating, in
/// any state (§3.8, review R-5).
///
/// Spec 1 W4b, under flow_couples_v2: the partner is named from R1's
/// first name (this phone only); "Invite your partner" and "Send again"
/// open R1's share step; day 7 offers "Send a new invite"; day 30 asks
/// once; every invite error is the app's own words.
class RelationshipSpaceScreen extends ConsumerStatefulWidget {
  const RelationshipSpaceScreen({super.key, required this.home});

  final HomeSnapshot home;

  @override
  ConsumerState<RelationshipSpaceScreen> createState() =>
      _RelationshipSpaceScreenState();
}

class _RelationshipSpaceScreenState
    extends ConsumerState<RelationshipSpaceScreen> {
  RelationshipInvite? _invite;
  Duration? _age;
  bool _busy = false;
  String? _error;

  LinkState get _link => widget.home.link;

  /// Day 30's line (§3.8 R3): shown in this visit, once per phone.
  bool _day30 = false;

  /// Final review #3: day 7's "Keep waiting" (flow_couples_v2) snoozes the
  /// prompt for this visit: the waiting state, the code there is, nothing
  /// minted (the R3 no-mint ruling).
  bool _day7Snoozed = false;

  /// The wait the guide shows: just under day 7 while it is snoozed.
  Duration? get _guideAge {
    final age = _age;
    if (!_day7Snoozed || age == null || age < PendingInviteGuide.pivotAfter) {
      return age;
    }
    return PendingInviteGuide.pivotAfter - const Duration(seconds: 1);
  }

  /// Review M-2: a failed "Send a new invite" keeps its words through the
  /// pending → none turn its withdraw causes.
  bool _keepError = false;

  bool get _couplesV2 => ref.read(flowCouplesV2Provider);

  InviteDeviceStore? get _device {
    final userId = ref.read(homeAuthProvider).currentUser?.id;
    if (userId == null) return null;
    try {
      return InviteDeviceStore(
        ref.read(sharedPreferencesProvider),
        userId: userId,
      );
    } catch (_) {
      return null;
    }
  }

  /// The invited partner's first name: the server's once linked, else
  /// (flow_couples_v2) the one typed at R1 on this phone.
  String? get _partnerName {
    final name = widget.home.linkDetail.partnerFirstName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return _couplesV2 ? _device?.partnerFirstName : null;
  }

  @override
  void initState() {
    super.initState();
    if (_link == LinkState.pending) _loadInvite();
  }

  @override
  void didUpdateWidget(covariant RelationshipSpaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.home.link != _link) {
      // Review M-3: the invite "Invite your partner" just made stays when
      // the home turns pending; it is fetched only when none is held.
      if (_link != LinkState.pending) _invite = null;
      if (!_keepError) _error = null;
      _keepError = false;
      if (_link == LinkState.pending && _invite == null) _loadInvite();
    }
  }

  RelationshipInviteService get _invites =>
      ref.read(invitePartnerServiceProvider);

  /// The home's refresh, read now: a call that ends after the person has
  /// left must not use `ref` again (it throws once the screen is gone).
  Future<void> Function() _homeRefresher() {
    final userId = ref.read(homeAuthProvider).currentUser?.id;
    if (userId == null) return () async {};
    final notifier = ref.read(homeStateProvider(userId).notifier);
    return () async {
      await notifier.refresh();
    };
  }

  /// The live code: create-relationship-invite returns the open invite (or
  /// mints one); [forceNew] is day 7's new code.
  ///
  /// Ruling (B6 review M-6, §3.8 R3): under flow_couples_v2 the wait is
  /// read first, and from day 7 nothing is minted here: codes are never
  /// renewed silently; a new one comes only from "Send a new invite".
  Future<void> _loadInvite({bool forceNew = false}) async {
    final invites = _invites;
    final refreshHome = _homeRefresher();
    final couplesV2 = _couplesV2;
    final device = couplesV2 ? _device : null;
    _keepError = false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final waited =
          couplesV2 && !forceNew ? await invites.inviteAge() : null;
      final renewDue =
          waited != null && waited >= PendingInviteGuide.pivotAfter;
      final invite =
          renewDue ? null : await invites.createInvite(forceNew: forceNew);
      final age = waited ?? await invites.inviteAge();
      if (!mounted) return;
      final showDay30 =
          device != null &&
          age != null &&
          age >= const Duration(days: 30) &&
          !device.day30Done;
      if (showDay30) {
        ref.read(metricCounterProvider).bump(ClientMetricKey.inviteDay30Shown);
        unawaited(device.markDay30Done());
      }
      setState(() {
        _invite = invite;
        _age = age;
        if (showDay30) _day30 = true;
      });
    } on RelationshipInviteException catch (error) {
      if (!mounted) return;
      if (error.alreadyActiveRelationship) {
        await refreshHome();
        return;
      }
      setState(
        () => _error = inviteErrorCopy(AppLocalizations.of(context)!, error),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context)!.flow_saveFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inviteNow() async {
    final refreshHome = _homeRefresher();
    if (_couplesV2) {
      await _openShareStep();
    } else {
      await _loadInvite();
    }
    await refreshHome();
  }

  /// R1's share step (flow_couples_v2): the registers and the code.
  Future<void> _openShareStep() async {
    await context.push(RouteNames.invitePartner);
    if (!mounted) return;
    if (_link == LinkState.pending) await _loadInvite();
  }

  /// Day 7 and day 30's "Send a new invite" (§3.8 R3): the old code stops
  /// working, a new one is made, and the share step opens with it.
  ///
  /// [metric]: day 7's `invite_new_day7`; day 30 passes none (it is
  /// counted when shown, `invite_day30_shown`; review M-1).
  Future<void> _sendNewInvite({ClientMetricKey? metric}) async {
    final invites = _invites;
    final refreshHome = _homeRefresher();
    final loc = AppLocalizations.of(context)!;
    final metrics = ref.read(metricCounterProvider);
    setState(() {
      _busy = true;
      _error = null;
      _day30 = false;
    });
    try {
      await invites.withdrawPendingInvites();
      final invite = await invites.createInvite();
      if (metric != null) metrics.bump(metric);
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _age = Duration.zero;
      });
    } on RelationshipInviteException catch (error) {
      _keepError = true;
      if (mounted) setState(() => _error = inviteErrorCopy(loc, error));
      return;
    } catch (_) {
      _keepError = true;
      if (mounted) setState(() => _error = loc.flow_inviteErrorTryAgain);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
      await refreshHome();
    }
    if (mounted) await _openShareStep();
  }

  Future<void> _dismissDay30() async {
    setState(() => _day30 = false);
  }

  /// "Cancel this invite" (§3.8): back to the path they came from, if any.
  Future<void> _cancelInvite() async {
    final loc = AppLocalizations.of(context)!;
    final name = widget.home.linkDetail.partnerFirstName;
    final ok = await showFlowConfirm(
      context,
      title: loc.flow_cancelThisInviteTitle,
      body:
          name == null || name.isEmpty
              ? loc.flow_cancelInviteBody
              : loc.flow_cancelInviteBodyNamed(name),
      confirm: loc.flow_cancelThisInviteConfirm,
      cancel: loc.flow_cancelInviteKeep,
    );
    if (!ok || !mounted) return;
    final refreshHome = _homeRefresher();
    setState(() => _busy = true);
    try {
      await ref
          .read(homeStateServiceProvider)
          .withdrawPendingInvites(returnToPreviousPath: true);
    } catch (_) {
      if (mounted) setState(() => _error = loc.flow_saveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await refreshHome();
  }

  /// Day 7's "Use Attune on my own for now" (Q7): the invites go, the path
  /// stays Relationship.
  Future<void> _onMyOwn() async {
    final invites = _invites;
    final refreshHome = _homeRefresher();
    final failed = AppLocalizations.of(context)!.flow_saveFailed;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await invites.withdrawPendingInvites();
    } catch (_) {
      // Said in words, never silent (§2.3).
      if (mounted) setState(() => _error = failed);
    }
    if (mounted) setState(() => _busy = false);
    await refreshHome();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final link = _link;
    final children = <Widget>[
      const SpaceHeader(),
      const SizedBox(height: Spacing.md),
      if (link == LinkState.paused || link == LinkState.endedWindow)
        const RelationshipLifecycleCard(),
      if (link == LinkState.pending) ...[
        _InviteSection(
          invite: _invite,
          busy: _busy,
          // Review I-1: a code that failed to load can be tried again, and
          // the invite can be cancelled without it (the server withdraws).
          onRetry: _error == null ? null : () => _loadInvite(),
          onCancel: _cancelInvite,
          onSendAgain: _couplesV2 ? _openShareStep : null,
        ),
        if (_day30) ...[
          const SizedBox(height: Spacing.md),
          _Day30Card(
            partnerName: _partnerName,
            busy: _busy,
            onSend: () => _sendNewInvite(),
            onDismiss: _dismissDay30,
          ),
        ],
        // W3c (§3.8 R2, §2.4): the heads-up ask, while notifications are off.
        PushAskRow(
          askContext: PushAskContext.r2,
          reason: _partnerName == null
              ? loc.flow_pushAskR2
              : loc.flow_pushAskR2Named(_partnerName!),
          action: loc.flow_pushTurnOn,
        ),
        const SizedBox(height: Spacing.md),
        PendingInviteGuide(
          age: _guideAge,
          busy: _busy,
          onReflect: () => context.pushNamed('reflectionJournal'),
          onKeepWaiting:
              _couplesV2
                  ? () => setState(() => _day7Snoozed = true)
                  : () => _loadInvite(),
          onUseAlone: _onMyOwn,
          onInviteSomeoneElse: () => _loadInvite(forceNew: true),
          v2: _couplesV2,
          partnerName: _partnerName,
          onSendNewInvite:
              () => _sendNewInvite(metric: ClientMetricKey.inviteNewDay7),
        ),
        const SizedBox(height: Spacing.md),
        _WhileYouWait(),
        // Spec 1 W5 (§3.8 R3): About us, the draft (couple_profile on).
        AboutUsCard(partnerName: _partnerName),
        const SizedBox(height: Spacing.sm),
        Text(
          _partnerName == null
              ? loc.flow_waitReceipts
              : loc.flow_waitReceiptsNamed(_partnerName!),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      if (link == LinkState.none) ...[
        FlowPrimaryButton(
          // Review M-5 (§3.8 R3): "Invite {name}" when R1's name is known.
          label:
              _couplesV2 && _partnerName != null
                  ? loc.flow_invitePartnerNamed(_partnerName!)
                  : loc.flow_invitePartnerTitle,
          busy: _busy,
          onPressed: _inviteNow,
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: Spacing.sm),
        FlowErrorLine(text: _error!, liveRegion: true),
      ],
      const SizedBox(height: Spacing.md),
      YourSpaceSection(
        extraRows: [
          // W3c: J3 on the Relationship space too.
          const JournalReminderRow(),
          // After the window only (§3.8; never inside it, 09 P15).
          if (link == LinkState.afterEnding) MoreWaysRow(home: widget.home),
        ],
      ),
      const SizedBox(height: Spacing.xxl * 2),
    ];
    return AllowLargeText(
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: children,
          ),
        ),
      ),
    );
  }
}

class _InviteSection extends StatelessWidget {
  const _InviteSection({
    required this.invite,
    required this.busy,
    required this.onCancel,
    this.onRetry,
    this.onSendAgain,
  });

  final RelationshipInvite? invite;
  final bool busy;
  final VoidCallback? onCancel;

  /// "Send again" under the card (flow_couples_v2): R1's share step.
  final VoidCallback? onSendAgain;

  /// Shown when the code couldn't be loaded (review I-1).
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final current = invite;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      loc.flow_invitePartnerTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (onCancel != null)
                  PopupMenuButton<void>(
                    tooltip: loc.flow_inviteMenu,
                    itemBuilder:
                        (_) => [
                          PopupMenuItem<void>(
                            onTap: onCancel,
                            child: Text(loc.flow_cancelThisInvite),
                          ),
                        ],
                  ),
              ],
            ),
            if (current != null) ...[
              InviteCard(invite: current),
              if (onSendAgain != null) ...[
                const SizedBox(height: Spacing.sm),
                FlowPrimaryButton(
                  label: loc.flow_r3SendAgain,
                  busy: busy,
                  onPressed: onSendAgain,
                ),
              ],
            ] else if (busy)
              const Padding(
                padding: EdgeInsets.all(Spacing.md),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (onRetry != null) ...[
              const SizedBox(height: Spacing.sm),
              FlowSecondaryButton(label: loc.flow_tryAgain, onPressed: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}

class _WhileYouWait extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        child: Column(
          children: [
            SpaceRow(
              title: loc.flow_waitWriteNote,
              subtitle: '',
              icon: Icons.edit_note_outlined,
              onTap: () => context.pushNamed('reflectionJournal'),
            ),
            SpaceRow(
              title: loc.flow_waitQuiz,
              subtitle: '',
              icon: Icons.psychology_outlined,
              onTap: () => context.pushNamed('quizEntry', extra: 'attachment'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Day 30, once (§3.8 R3): "Want to send {name} a new invite?" with
/// "Send a new invite" and a close button. Codes are never renewed
/// silently.
class _Day30Card extends StatelessWidget {
  const _Day30Card({
    required this.partnerName,
    required this.busy,
    required this.onSend,
    required this.onDismiss,
  });

  final String? partnerName;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final name = partnerName;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    name == null ? loc.flow_day30Unnamed : loc.flow_day30(name),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: loc.flow_day30Dismiss,
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            FlowSecondaryButton(
              label: loc.flow_guideSendNew,
              busy: busy,
              onPressed: onSend,
            ),
          ],
        ),
      ),
    );
  }
}
