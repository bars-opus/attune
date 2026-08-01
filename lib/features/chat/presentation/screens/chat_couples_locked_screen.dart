// lib/features/chat/presentation/screens/chat_couples_locked_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/utils/relationship_status_display.dart';
import 'package:attune/core/widgets/profile_avatar.dart';
import 'package:attune/features/auth/intro/widgets/intro_guide_widget.dart';
import 'package:attune/features/onboarding/presentation/widgets/invite_card.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';
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
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        // AppBar centers `leading` in a fixed-width box (leadingWidth,
        // default 56) rather than sizing that box to its child — without
        // this, ProfileAvatar's own `size` correctly resizes the circle
        // itself but the surrounding AppBar slot never shrinks/grows to
        // match, so the change reads as "doing nothing" in the toolbar.

        // leading: Center(
        //   child: ProfileAvatar(
        //     avatarUrl: '',
        //     currentUserId: currentUserId,
        //     size: 30.h,
        //     enableHero: false,
        //     icon: statusIconFor(myStatusDisplay),
        //     backgroundColor: statusColorFor(myStatusDisplay, colorScheme),
        //   ),
        // ),
        // centerTitle: false,
        leadingWidth: 100.w,
        leading: Padding(
          padding: const EdgeInsets.only(left: Spacing.lg),
          child: Text(
            'Chat',
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
        title: GestureDetector(
          onTap: () {
            BottomSheetUtils.showDocumentationBottomSheet(
              context: context,
              // Info items are typically view-only (no agree/decline)
              showButtons: false,
              maxHeight: 700,
              // Dynamic sizing: full guide gets 90% height, others get 70%

              // Dynamic content: guide shows full DocumentationScreen, others show legal docs
              widget: DocumentationScreen(),
            );
          },
          child: SizedBox(
            width: 30,
            height: 30,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(BorderRadiusTokens.md),
              child: Image.asset(
                color: colorScheme.primary,
                'assets/images/attune_logo_white.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        actions: [
          AppIconButton(
            icon: Icons.menu,
            onPressed: () {
              context.pushNamed('settings');
            },
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(Spacing.md.h),
        children: [
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
                    onRetry: _createInvite,
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
                Gap(Spacing.md.h),
              ],
            ),
          ),
          _ReflectionEntryCard(
            onTap: () => context.pushNamed('healingJourney'),
          ),

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
          Gap(Spacing.xxl.h * 3),
        ],
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
        onTap: () {},
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // The invite that started the pending track was already created
    // elsewhere (onboarding, or a prior visit here) — this screen only
    // creates a NEW one on retry after an error. Absent both, there is
    // nothing to show but the waiting message above; the code is not
    // re-fetchable from the client (RelationshipInviteService only
    // creates or accepts, it does not look up an existing one), so a
    // returning user who already sent their invite sees the waiting copy
    // without the code repeated — a real gap, but not one guessable data
    // can fill without a new read endpoint.
    if (invite != null) return InviteCard(invite: invite!);
    if (isCreating) return const Center(child: CircularProgressIndicator());
    if (errorMessage != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            errorMessage!,
            style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
          ),
          Gap(Spacing.sm.h),
          AppButton(
            label: 'Try again',
            prefixIcon: Icons.refresh,
            variant: ButtonVariant.outline,
            onPressed: onRetry,
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}
