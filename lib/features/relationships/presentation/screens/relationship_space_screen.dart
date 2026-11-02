import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/notifications/presentation/widgets/push_ask_row.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/me/presentation/widgets/journal_reminder_row.dart';
import 'package:attune/features/me/presentation/widgets/more_ways_sheet.dart';
import 'package:attune/features/me/presentation/widgets/your_space_section.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/onboarding/presentation/screens/invite_partner_screen.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/pending_invite_guide.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
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

  /// The invited partner's first name, if the server gave one.
  String? get _partnerName {
    final name = widget.home.linkDetail.partnerFirstName?.trim();
    return name == null || name.isEmpty ? null : name;
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
      _error = null;
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
  Future<void> _loadInvite({bool forceNew = false}) async {
    final invites = _invites;
    final refreshHome = _homeRefresher();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final invite = await invites.createInvite(forceNew: forceNew);
      final age = await invites.inviteAge();
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _age = age;
      });
    } on RelationshipInviteException catch (error) {
      if (!mounted) return;
      if (error.alreadyActiveRelationship) {
        await refreshHome();
        return;
      }
      setState(() => _error = error.message);
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
    await _loadInvite();
    await refreshHome();
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
        ),
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
          age: _age,
          busy: _busy,
          onReflect: () => context.pushNamed('reflectionJournal'),
          onKeepWaiting: () => _loadInvite(),
          onUseAlone: _onMyOwn,
          onInviteSomeoneElse: () => _loadInvite(forceNew: true),
        ),
        const SizedBox(height: Spacing.md),
        _WhileYouWait(),
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
          label: loc.flow_invitePartnerTitle,
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
  });

  final RelationshipInvite? invite;
  final bool busy;
  final VoidCallback? onCancel;

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
            if (current != null)
              InviteCard(invite: current)
            else if (busy)
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
