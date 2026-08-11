// lib/features/chat/presentation/screens/chat_couples_locked_screen.dart

import 'package:attune/app/documentations/user_manual/data/chat_docs.dart';
import 'package:attune/app/documentations/user_manual/data/healing_docs.dart';
import 'package:attune/core/intro/presentation/screens/feature_intro_flow_screen.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/utils/relationship_status_display.dart';
import 'package:attune/core/widgets/animated_circle.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_card.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/features/healing/presentation/widgets/healing_self_report_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_qr_code.dart';

/// What a non-couples user sees on the Chat tab.
///
/// Master Spec §9 line 2741 ("Personal mode: personal reflection workspace
/// or onboarding CTA, depending MVP scope") deliberately leaves the exact
/// treatment open — "depending MVP scope" is not a locked requirement, so
/// there is no single spec-mandated layout to match here. §8.9 does still
/// require Personal mode's real reflection journal to stay reachable (it is
/// explicitly listed as AVAILABLE, not a locked/future feature) — so this
/// screen keeps that live and tappable rather than locking everything.
///
/// Design: show the couples chat surface as it would actually look
/// (ConversationsScreen's own card language — CircleAvatar, name, preview,
/// status pill), with the conversation content itself replaced by a lock
/// overlay, so a personal-mode user can see what they're missing rather
/// than reading a bare sentence. Below that, two real actions: invite a
/// partner (couplesPending track) or open Dating mode (post-launch design,
/// self-gates via DatingDashboardScreen — this screen just navigates
/// there, it never decides Dating mode's own availability).
class ChatCouplesLockedScreen extends ConsumerStatefulWidget {
  const ChatCouplesLockedScreen({
    super.key,
    required this.isPendingCouples,
    required this.onInviteSent,
  });

  /// True when this user already generated an invite and is waiting on
  /// their partner (OnboardingMode.couplesPending) — shows the pending
  /// invite instead of "invite a partner" as a fresh action.
  final bool isPendingCouples;

  /// Called after a fresh invite is successfully created and the local
  /// OnboardingMode is persisted as couplesPending, so the app shell
  /// (HomeScreen owns the OnboardingStore future) can reload and re-route
  /// — this screen has no way to trigger that itself, since the store load
  /// lives above it in the tree.
  final VoidCallback onInviteSent;

  @override
  ConsumerState<ChatCouplesLockedScreen> createState() =>
      _ChatCouplesLockedScreenState();
}

class _ChatCouplesLockedScreenState
    extends ConsumerState<ChatCouplesLockedScreen> {
  final _inviteService = RelationshipInviteService();

  RelationshipInvite? _invite;
  bool _isCreatingInvite = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    // A returning couplesPending user (app restart, re-navigation) has no
    // locally-held invite — `_invite` only ever lived in this State object,
    // never persisted. ATTUNE_MASTER_SPEC.md: "Invite codes are reusable
    // until accepted or expired," and create-relationship-invite already
    // returns the existing live invite instead of minting a new one, so
    // silently re-fetching here re-displays the same code rather than
    // creating a duplicate. onInviteSent() is NOT called from this path —
    // the user is already on the couplesPending track, so there is nothing
    // new for the app shell to persist.
    if (widget.isPendingCouples) {
      _loadExistingInvite();
    }
  }

  Future<void> _loadExistingInvite() async {
    setState(() {
      _isCreatingInvite = true;
      _errorMessage = null;
    });

    try {
      final invite = await _inviteService.createInvite();
      if (!mounted) return;
      setState(() => _invite = invite);
    } catch (error) {
      if (!mounted) return;
      // Reaching here means the server already considers this inviter's
      // relationship active — widget.isPendingCouples was stale (a real
      // race: HomeScreen's own local mode hasn't caught up yet to a
      // partner's just-landed acceptance). Showing this as an error would
      // be wrong AND get the user stuck, since nothing else prompts a
      // resync from this screen. Trigger one directly instead — see
      // relationshipModeResyncSignal's doc in home_screen.dart — so
      // HomeScreen swaps this screen out for the real chat on its own.
      if (error is RelationshipInviteException &&
          error.alreadyActiveRelationship) {
        relationshipModeResyncSignal.value++;
        return;
      }
      setState(() {
        _errorMessage =
            error is RelationshipInviteException
                ? error.message
                : 'Could not load your invite.';
      });
    } finally {
      if (mounted) setState(() => _isCreatingInvite = false);
    }
  }

  Future<void> _onHealingEntryTap() async {
    final colorScheme = Theme.of(context).colorScheme;
    final hasActiveSoloJourney = await ref.read(
      hasActiveSoloHealingJourneyProvider.future,
    );
    if (!mounted) return;

    if (hasActiveSoloJourney) {
      context.push(RouteNames.healingJourney);
      return;
    }

    final started = await BottomSheetUtils.showDocumentationBottomSheet<bool>(
      context: context,
      backgroundColor: colorScheme.neutral,
      widget: const HealingSelfReportSheet(),
    );
    if (!mounted) return;
    if (started == true) {
      context.push(RouteNames.healingJourney);
    }
  }

  Future<void> _createInvite() async {
    setState(() {
      _isCreatingInvite = true;
      _errorMessage = null;
    });

    try {
      final invite = await _inviteService.createInvite();
      if (!mounted) return;
      setState(() => _invite = invite);
      widget.onInviteSent();
    } catch (error) {
      if (!mounted) return;
      // See _loadExistingInvite's identical check — local state claiming
      // this user isn't coupled yet is stale if the server already has an
      // active relationship for them; resync instead of showing an error.
      if (error is RelationshipInviteException &&
          error.alreadyActiveRelationship) {
        relationshipModeResyncSignal.value++;
        return;
      }
      setState(() {
        _errorMessage =
            error is RelationshipInviteException
                ? error.message
                : 'Could not create invite.';
      });
    } finally {
      if (mounted) setState(() => _isCreatingInvite = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      // No AppBar: TripleTapDetector's invisible quick-exit gesture zone is
      // centered at the very top of every screen (same region a centered
      // AppBar title occupies). Keeping the title/menu row inside the body
      // (below the top inset, not overlapping that zone) avoids fighting it
      // for hit-test priority — see _AttuneLogoButton's own doc for why the
      // logo itself moved further down into the column instead of living
      // here too.
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(Spacing.md.h),
          children: [
            Align(
              alignment: Alignment.topRight,
              child: AppIconButton(
                icon: Icons.menu,
                // TEMP preview hook: pushes FeatureIntroFlowScreen directly
                // instead of RouteNames.healingJourney (FeatureIntroFlowGate
                // + SeenFeatureIntroStore), so the intro shows every tap for
                // UI iteration — the real route only shows it once per
                // device, which made it invisible after the first visit.
                // Same module/copy/launchLabel the real healingJourney route
                // passes to FeatureIntroFlowGate — see app_router.dart.
                onPressed: () {
                  context.pushNamed('settings');
                },
              ),
            ),
            Gap(Spacing.md.h),
            // Real, functional — Personal mode's reflection journal is
            // explicitly AVAILABLE per §8.9, not locked.
            CardInkWell(
              child: Column(
                children: [
                  Gap(Spacing.md.h),

                  // Gap(Spacing.lg.h),
                  // AppDivider(), Gap(Spacing.lg.h),
                  // Locked preview — same card language ConversationsScreen uses
                  // for a real conversation, so a personal-mode user sees the
                  // actual couples chat surface rather than reading about it.
                  // if (!widget.isPendingCouples)
                  _WelcomEntryCard(isPendingCouples: widget.isPendingCouples),
                  Gap(Spacing.md.h),

                  // Gap(Spacing.xl.h),
                  if (widget.isPendingCouples)
                    _PendingInviteSection(
                      invite: _invite,
                      isPendingCouples: widget.isPendingCouples,
                      isCreating: _isCreatingInvite,
                      errorMessage: _errorMessage,
                      onRetry: _loadExistingInvite,
                    )
                  else ...[
                    if (!_inviteService.isConfigured)
                      Text(
                        'Invites are unavailable right now. Please try again later.',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.error,
                        ),
                      )
                    else if (_isCreatingInvite)
                      const Center(child: CircularLoadingIndicator())
                    else if (_invite != null)
                      InviteCard(invite: _invite!)
                    else ...[
                      if (_errorMessage != null) ...[
                        Text(
                          _errorMessage!,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.error,
                          ),
                        ),
                        Gap(Spacing.sm.h),
                      ],

                      Gap(Spacing.smMd.h),
                      AppButton(
                        height: 40.h,
                        elevation: 0,
                        animateButton: false,
                        prefixIconColor: colorScheme.background,
                        size: ButtonSize.small,
                        label: 'Invite your partner',
                        prefixIcon: Icons.person_add_alt_outlined,
                        onPressed:
                            _inviteService.isConfigured ? _createInvite : null,
                      ),
                    ],
                    // Hidden once an invite exists: get_dating_eligibility()
                    // already returns reason: 'relationship_active' and
                    // refuses Dating Mode entirely while the caller has a
                    // pending relationship (20260703194500_dating_mode_v1_1.sql)
                    // — a sent invite creates exactly that pending row, so
                    // this button would just lead to a dead end. Hiding it
                    // matches the backend's own rule instead of just
                    // tidying the UI.
                    if (_invite == null) ...[
                      Gap(Spacing.smMd.h),
                      AppButton(
                        height: 40.h,
                        animateButton: false,
                        size: ButtonSize.small,
                        label: 'Meet someone in Dating mode',
                        variant: ButtonVariant.outline,
                        prefixIconColor: colorScheme.primary,
                        prefixIcon: Icons.favorite_border,
                        onPressed: () => context.push(RouteNames.datingMode),
                      ),
                    ],
                    Gap(Spacing.xl.h),
                  ],
                  Gap(Spacing.md.h),
                ],
              ),
            ),

            // if (!widget.isPendingCouples)
            CardInkWell(
              child: Column(
                children: [
                  _LockedConversationPreview(
                    colorScheme: colorScheme,
                    isPendingCouples: widget.isPendingCouples,
                  ),
                  AppDivider(),
                  _ReflectionEntryCard(
                    colorScheme: colorScheme,
                    isPendingCouples: widget.isPendingCouples,
                    onTap: () => context.pushNamed('reflectionJournal'),
                  ),

                  if (!_isCreatingInvite)
                    if (_invite == null) ...[
                      AppDivider(),
                      _HealingEntryCard(onTap: _onHealingEntryTap),
                    ],
                ],
              ),
            ),

            Gap(Spacing.xxl.h * 3),
          ],
        ),
      ),
    );
  }
}

class _WelcomEntryCard extends StatelessWidget {
  final bool isPendingCouples;

  const _WelcomEntryCard({required this.isPendingCouples});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context)!;
    final overview =
        isPendingCouples
            ? 'Once your partner accepts and completes their own onboarding, A private private chat would open for the two of you to start atunning.'
            : 'Welcome back to Attune. To start bonding with your partner, send them an invite. '
                'If you\'re not in a relationship but ready to start dating, you can explore your '
                'options by tapping "Meet someone in Dating mode."';

    return Column(
      children: [
        Gap(Spacing.xl.h),

        // Two bundled stand-in avatars (bitmale.png/bitfemale.png) — rather
        // than the old abstract morphing shape, so this card visually
        // previews the "you + them" pairing "Invite Partner" below is
        // actually offering. Not real account photos: there is no partner
        // yet, and this card only shows before an invite exists (see the
        // !isPendingCouples gate this card is built under).
        GestureDetector(
          onTap: () {
            // Navigator.of(context).push(
            //   MaterialPageRoute(
            //     builder:
            //         (context) => FeatureIntroFlowScreen(
            //           module: HealingDocs(),
            //           briefParagraph:
            //               'Healing Mode is private and self-paced. It\'s not therapy, it '
            //               'doesn\'t diagnose you or your relationship, and your former '
            //               'partner is never told you\'re using it.',
            //           launchLabel: 'Enter Healing Mode',
            //           onComplete: () {
            //             Navigator.of(context).pop();
            //             context.push(RouteNames.healingJourney);
            //           },
            //         ),
            //   ),
            // );
          },
          child: const _StackedInviteAvatars(),
        ),
        Gap(Spacing.lg.h),
        Center(
          child: Text(
            isPendingCouples
                ? 'Your invite\nis pending'
                : 'Invite\nYour Partner',
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
              fontSize: FontSizeTokens.xxl.sp,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        if (!isPendingCouples)
          Text(
            'A private space to build a more stronger bond.',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
        Gap(isPendingCouples ? Spacing.sm : Spacing.lg.h),
        GestureDetector(
          onTap: () {
            BottomSheetUtils.showDocumentationBottomSheet(
              context: context,
              widget: ReadAll(body: overview),
            );
          },
          child: Column(
            crossAxisAlignment:
                isPendingCouples
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
            children: [
              Text(
                overview,
                style:
                    isPendingCouples
                        ? textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface,
                        )
                        : textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                        ),
                maxLines: 4,
                textAlign:
                    isPendingCouples ? TextAlign.center : TextAlign.start,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                loc.commonLearnMore,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: FontSizeTokens.xs.sp,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Mirrors ConversationsScreen's own _ReflectionCard so the real entry
/// point looks identical whether you arrive here or already have chat.
class _ReflectionEntryCard extends StatelessWidget {
  final bool isPendingCouples;
  final ColorScheme colorScheme;
  const _ReflectionEntryCard({
    required this.colorScheme,
    required this.isPendingCouples,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InfoRowWidget(
      subtitle:
          'A private space for your own reflection work. This never sends messages to anyone, just reflections to heal after breakup or prepare for dating.',
      title: 'Personal reflections',
      icon: Icons.self_improvement_outlined,
      subTitleMaxLines: 5,
      iconSize: 25.h,
      showDivider: false,
      onTap: onTap,
      disableTrailing: false,
      showAvatar: true,
      showTrailingArrow: false,
      trailing: Icon(Icons.chevron_right_rounded, size: 25.h),
    );
  }
}

/// Entry point into a self-reported (no tracked relationship) Healing
/// Mode journey. Shown only alongside the intro carousel, i.e. only for a
/// true single with no pending invite — see the enclosing conditional in
/// build() above.
class _HealingEntryCard extends StatelessWidget {
  const _HealingEntryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InfoRowWidget(
      subtitle:
          'Start a private healing journey, even if it wasn\'t tracked in Attune.',
      title: 'Healing from a breakup?',
      icon: Icons.healing_outlined,
      subTitleMaxLines: 5,
      iconSize: 25.h,
      showDivider: false,
      onTap: onTap,
      disableTrailing: false,
      showAvatar: true,
      showTrailingArrow: false,
      trailing: Icon(Icons.chevron_right_rounded, size: 25.h),
    );
  }
}

/// A non-interactive stand-in for a real conversation card — same visual
/// shape ConversationsScreen._ConversationCard uses (avatar, name, preview,
/// status pill), with a lock overlay instead of real content. Shows what
/// couples chat looks like without pretending there is a real conversation
/// underneath it.
class _LockedConversationPreview extends StatelessWidget {
  final bool isPendingCouples;
  const _LockedConversationPreview({
    required this.colorScheme,
    required this.isPendingCouples,
  });

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final docs = ChatDocs();

    return InfoRowWidget(
      subtitle:
          'A shared chat opens once you and a partner are both connected. Invite your lover, or meet someone new in Dating mode.',
      title: 'Chat is for couples',
      icon: Icons.chat_bubble_outline,
      iconSize: 25.h,
      showAvatar: true,
      // iconColor: colorScheme.error,
      // backgroundColor: colorScheme.error.withOpacity(0.1),
      subTitleMaxLines: 5,

      showDivider: false,
      onTap: () {
        BottomSheetUtils.showDocumentationBottomSheet(
          context: context,
          showButtons: false,
          widget: DocumentationTabView(
            module: docs,
            showDocumentationFirst: true,
          ),
        );
      },
      disableTrailing: false,

      showTrailingArrow: false,
      trailing: Icon(Icons.lock, size: 25.h, color: colorScheme.error),
    );
  }
}

class _PendingInviteSection extends StatelessWidget {
  const _PendingInviteSection({
    required this.invite,
    required this.isCreating,
    required this.errorMessage,
    required this.onRetry,
    required this.isPendingCouples,
  });

  final RelationshipInvite? invite;
  final bool isCreating;
  final bool isPendingCouples;
  final String? errorMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // `invite` starts null on every build (including after an app restart)
    // and is populated by _ChatCouplesLockedScreenState.initState calling
    // _loadExistingInvite, which re-fetches the caller's existing live
    // invite (create-relationship-invite is idempotent per
    // ATTUNE_MASTER_SPEC.md's "reusable until accepted or expired") rather
    // than minting a new one — so a returning user sees their real,
    // previously-sent code again, not just the waiting message.
    if (invite != null) return InviteCard(invite: invite!);
    if (isCreating) return const Center(child: CircularLoadingIndicator());
    if (errorMessage != null) {
      return ErrorStateWidget(
        subtitle: errorMessage!,
        onPrimaryAction: onRetry,
        primaryActionLabel: 'Try again',
      );
    }
    return const SizedBox.shrink();
  }
}

/// Tappable Attune logo that opens the documentation/guide sheet.
///
/// Only shown above the "Invite your partner" action — i.e. only while chat
/// is genuinely locked with no invite in flight yet (not pending, not
/// already accepted). Once an invite exists or is pending, this branch of
/// the column isn't built at all, so the logo naturally disappears; it was
/// previously pinned in the top bar on every state of this screen, which
/// also fought TripleTapDetector's own top-of-screen gesture zone for the
/// tap (see the comment that used to sit on Scaffold.body above — a plain
/// Row below the top inset avoided that collision, and still does, from its
/// new spot in the column below).
class _AttuneLogoButton extends StatelessWidget {
  final double? size;
  const _AttuneLogoButton({this.size = 30});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      // Opaque so the whole 30x30 box is tappable, not just the
      // non-transparent pixels of the tinted logo PNG.
      behavior: HitTestBehavior.opaque,
      onTap: () {
        BottomSheetUtils.showDocumentationBottomSheet(
          context: context,
          // Info items are typically view-only (no agree/decline)
          showButtons: false,
          // Dynamic content: guide shows the documentation list, others
          // show legal docs. DocumentationList (not DocumentationScreen) —
          // the sheet already supplies its own Scaffold, and a nested
          // Scaffold inside it renders blank instead of showing.
          widget: Padding(
            padding: const EdgeInsets.only(top: Spacing.md),
            child: const DocumentationList(),
          ),
        );
      },
      child: SizedBox(
        width: size ?? 30.h,
        height: size ?? 30.w,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(BorderRadiusTokens.md),
          child: Image.asset(
            color: colorScheme.primary,
            'assets/images/attune_logo_white.png',
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

/// Two overlapping circular avatars — "you" on the left, a blank
/// placeholder for "them" on the right — both sitting on the same
/// horizontal line, same overlap language ReplyAvatarStack uses for reply
/// previews (core/widgets/reply_avatar_stack.dart): left-to-right only, no
/// vertical stagger.
///
/// Both avatars go through ProfileAvatar, which already routes any
/// avatarUrl starting with "http" through CachedNetworkImage internally
/// (see its own doc) — so "mine" loads from the network when a photo
/// exists, and "theirs" (an intentionally empty avatarUrl — there is no
/// partner yet) falls back to ProfileAvatar's own generic person
/// silhouette, with no separate placeholder widget needed.
class _StackedInviteAvatars extends StatelessWidget {
  const _StackedInviteAvatars();

  static const double _avatarSize = 80;
  static const double _xOffset = 60;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: _avatarSize + _xOffset,
      height: _avatarSize,
      child: Stack(
        children: [
          // Right side, same top — the "them" placeholder. A bundled
          // stand-in illustration (bitfemale.png), not a real avatarUrl —
          // there is no partner yet — so this goes through the same
          // circular-clip/border treatment ProfileAvatar gives a real photo
          // rather than through ProfileAvatar itself, which only knows how
          // to load a network or on-disk avatarUrl, not a bundled asset.
          // Painted first (Stack paints later children on top), so yours
          // (below) ends up in front of it.
          Positioned(
            left: _xOffset,
            top: 0,
            child: _AssetAvatar(
              assetPath: 'assets/images/bitfemale.png',
              size: _avatarSize,
              color: Colors.grey.withOpacity(.3),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: _AssetAvatar(
              assetPath: 'assets/images/bitmale.png',
              size: _avatarSize,
              color: Colors.grey[400] ?? Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

/// A bundled asset image in the same circular-clip/bordered-circle shape
/// ProfileAvatar gives a real avatarUrl — kept separate from ProfileAvatar
/// itself rather than stretching it to accept a third image source, since
/// ProfileAvatar's avatarUrl only ever means "network URL" or "on-disk file
/// path," never a Flutter asset key.
class _AssetAvatar extends StatelessWidget {
  const _AssetAvatar({
    required this.assetPath,
    required this.size,
    required this.color,
  });

  final String assetPath;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.surface, width: 3.w),
      ),
      child: ClipOval(child: Image.asset(assetPath, fit: BoxFit.cover)),
    );
  }
}
