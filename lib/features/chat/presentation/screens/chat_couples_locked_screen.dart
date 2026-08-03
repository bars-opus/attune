// lib/features/chat/presentation/screens/chat_couples_locked_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/utils/relationship_status_display.dart';
import 'package:attune/core/widgets/profile_avatar.dart';
import 'package:attune/features/auth/intro/widgets/intro_guide_widget.dart';
import 'package:attune/core/widgets/animated_circle.dart';

import 'package:attune/features/onboarding/presentation/widgets/invite_card.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/features/healing/presentation/widgets/healing_self_report_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  late ScrollController _scrollController;
  List<DocumentationModule> modules = [];

  RelationshipInvite? _invite;
  bool _isCreatingInvite = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    DocumentationRegistry.initialize();
    modules = DocumentationRegistry.getAllModules();
    // Schedule the scroll after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && modules.length > 1) {
        // Get the screen width
        final screenWidth = MediaQuery.of(context).size.width;
        final itemWidth = _getItemWidth();

        // Calculate offset to center the second item (index 1)
        // Formula: (itemWidth * index) - (screenWidth/2) + (itemWidth/2)
        final offset = (itemWidth * 1) - (screenWidth / 2) + (itemWidth / 2);

        // Ensure offset is not negative (for first items)
        final clampedOffset = offset.clamp(0.0, double.infinity);

        _scrollController.jumpTo(clampedOffset);
      }
    });

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
    final hasActiveSoloJourney =
        await ref.read(hasActiveSoloHealingJourneyProvider.future);
    if (!mounted) return;

    if (hasActiveSoloJourney) {
      context.push(RouteNames.healingJourney);
      return;
    }

    await BottomSheetUtils.showDocumentationBottomSheet(
      context: context,
      widget: const HealingSelfReportSheet(),
    );
    if (!mounted) return;
    context.push(RouteNames.healingJourney);
  }

  double _getItemWidth() {
    return 250.w; // Your item width
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
      // AppBar title occupies), and it was winning the tap-gesture arena
      // against the logo's own GestureDetector — a single tap on the logo
      // never opened the sheet. Moving these three items into the body as a
      // plain Row (below the top inset, not overlapping that zone) sidesteps
      // the collision entirely instead of fighting over hit-test priority.
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(Spacing.md.h),
          children: [
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: Spacing.sm),
                  child: Text(
                    'Chat',
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ),
                const Spacer(),
                if (_invite != null) ...[
                  AnimatedCircle(
                    size: 50,
                    stroke: 2,
                    animateSize: true,
                    animateShape: true,
                    firstColor: colorScheme.primary,
                    secondColor: colorScheme.primary,
                  ),
                ] else
                  GestureDetector(
                    // Opaque so the whole 30x30 box is tappable, not just the
                    // non-transparent pixels of the tinted logo PNG.
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      BottomSheetUtils.showDocumentationBottomSheet(
                        context: context,
                        // Info items are typically view-only (no agree/decline)
                        showButtons: false,
                        maxHeight: 700,
                        // Dynamic content: guide shows the documentation list,
                        // others show legal docs. DocumentationList (not
                        // DocumentationScreen) — the sheet already supplies its
                        // own Scaffold, and a nested Scaffold inside it renders
                        // blank instead of showing.
                        widget: Padding(
                          padding: const EdgeInsets.only(top: Spacing.md),
                          child: const DocumentationList(),
                        ),
                      );
                    },
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          BorderRadiusTokens.md,
                        ),
                        child: Image.asset(
                          color: colorScheme.primary,
                          'assets/images/attune_logo_white.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                AppIconButton(
                  icon: Icons.menu,
                  onPressed: () {
                    context.pushNamed('settings');
                  },
                ),
              ],
            ),
            Gap(Spacing.md.h),
            // Real, functional — Personal mode's reflection journal is
            // explicitly AVAILABLE per §8.9, not locked.
            CardInkWell(
              child: Column(
                children: [
                  Gap(Spacing.md.h),
                  // AnimatedCircle(
                  //   size: 30,
                  //   stroke: 2,
                  //   animateSize: true,
                  //   animateShape: true,
                  //   firstColor: colorScheme.primary,
                  //   secondColor: colorScheme.primary,
                  // ),
                  // Gap(Spacing.lg.h),
                  // AppDivider(), Gap(Spacing.lg.h),
                  // Locked preview — same card language ConversationsScreen uses
                  // for a real conversation, so a personal-mode user sees the
                  // actual couples chat surface rather than reading about it.
                  _LockedConversationPreview(
                    colorScheme: colorScheme,
                    isPendingCouples: widget.isPendingCouples,
                  ),

                  Gap(Spacing.xl.h),

                  // Gap(Spacing.xl.h),
                  if (widget.isPendingCouples)
                    _PendingInviteSection(
                      invite: _invite,
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
                      const Center(child: CircularProgressIndicator())
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

                      AppButton(
                        height: 40.h,
                        elevation: 0,
                        animateButton: false,
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
                        prefixIcon: Icons.favorite_border,
                        onPressed: () => context.push(RouteNames.datingMode),
                      ),
                    ],
                  ],
                  Gap(Spacing.md.h),
                ],
              ),
            ),
            _ReflectionEntryCard(
              onTap: () => context.pushNamed('reflectionJournal'),
            ),

            if (!_isCreatingInvite)
              if (_invite == null) ...[
                _HealingEntryCard(onTap: _onHealingEntryTap),
                Gap(Spacing.md.h),
                SizedBox(
                  height: 250.h,
                  child: ListView.builder(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    itemCount: modules.length,
                    itemBuilder: (context, index) {
                      final module = modules[index];
                      return SizedBox(
                        width: 250.w, // Make sure items have fixed width
                        child: IntroGuideWidget(module: module),
                      );
                    },
                  ),
                ),
                Gap(Spacing.xxl.h),
                GestureDetector(
                  onTap: () {
                    BottomSheetUtils.showDocumentationBottomSheet(
                      maxHeight: MediaQuery.of(context).size.height * 0.7,
                      context: context,
                      widget: AllLegalDocumentationsScreen(),
                    );
                  },
                  child: Text(
                    loc.authReadLegalities,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      decoration: TextDecoration.underline,
                      letterSpacing: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            Gap(Spacing.xxl.h * 3),
          ],
        ),
      ),
    );
  }
}

/// Mirrors ConversationsScreen's own _ReflectionCard so the real entry
/// point looks identical whether you arrive here or already have chat.
class _ReflectionEntryCard extends StatelessWidget {
  const _ReflectionEntryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CardInkWell(
      child: InfoRowWidget(
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
      ),
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
    return CardInkWell(
      child: InfoRowWidget(
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
      ),
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
    return InfoRowWidget(
      subtitle:
          isPendingCouples
              ? 'Once your partner accepts and completes their own onboarding, this becomes your private chat.'
              : 'A shared chat opens once you and a partner are both connected. Invite your lover, or meet someone new in Dating mode.',
      title:
          isPendingCouples ? 'Your invite is pending' : 'Chat is for couples',
      icon: Icons.send,

      iconSize: 0.h,
      showDivider: false,
      onTap: () {},
      disableTrailing: false,
      showAvatar: false,
      showTrailingArrow: false,
      trailing: Icon(Icons.lock_outline, size: 25.h),
    );
  }
}

class _PendingInviteSection extends StatelessWidget {
  const _PendingInviteSection({
    required this.invite,
    required this.isCreating,
    required this.errorMessage,
    required this.onRetry,
  });

  final RelationshipInvite? invite;
  final bool isCreating;
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
    if (isCreating) return const Center(child: CircularProgressIndicator());
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
