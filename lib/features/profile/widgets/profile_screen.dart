import 'dart:io';

import 'package:attune/core/providers/profile_providers/profile_provider.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/profile/models/profile.dart';
import 'package:attune/features/profile/widgets/profile_header.dart';
import 'package:attune/features/profile/widgets/profile_tabs.dart';
import 'package:attune/features/profile/widgets/tab_bar_delegate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final String currentUserId;
  final String profileUserId;
  // final ProfileSearchResult? profileSearchResult;

  const ProfileScreen({
    super.key,
    required this.currentUserId,
    required this.profileUserId,
    // this.profileSearchResult,
  });

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length:
          buildProfileTabs(
            widget.profileUserId,
            widget.currentUserId == widget.profileUserId,
            false,
          ).length,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  Widget _buildLoadingShimmer(bool isLoading) {
    final loc = AppLocalizations.of(context)!;
    return _buildBody(
      username: '...',
      displayName: 'Loading...',
      bio: '-',
      avatarUrl: '',
      isAuthor: widget.profileUserId == widget.currentUserId,
      bookingCount: 0,
      shopingCount: 0,
      isLoading: isLoading,
      loc: loc,
    );
  }

  Future<void> _startPrivateChat() async {
    final loc = AppLocalizations.of(context)!;
    if (widget.profileUserId == widget.currentUserId) {
      context.showErrorSnackbar(loc.profileScreenCantChatWithYourself);
      return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(loc.profileScreenStartingConversation),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );

      final chatRepository = ref.read(chatRepositoryProvider);
      final relationshipId = await chatRepository.getRelationshipIdForPartner(
        widget.profileUserId,
      );
      if (relationshipId == null) {
        throw Exception('No relationship chat is available for this profile.');
      }
      final conversation = await chatRepository.getConversation(relationshipId);
      if (conversation == null) {
        throw Exception('This relationship chat is unavailable.');
      }

      if (mounted) {
        context.pushNamed('chatScreen', extra: conversation);
      }
    } catch (e) {
      debugPrint('❌ [START-CHAT] error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        context.showErrorSnackbar('${loc.commonSomethingWentWrong}: $e');
      }
    }
  }

  Widget _buildBody({
    required String username,
    required String displayName,
    required String bio,
    required String avatarUrl,
    required bool isAuthor,
    required bool isLoading,
    required int bookingCount,
    required int shopingCount,
    required AppLocalizations loc,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tabs = buildProfileTabs(
      widget.currentUserId,
      isAuthor,
      false,
      loc: loc,
    );

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverToBoxAdapter(
              child: SafeArea(
                child: Column(
                  children: [
                    // Header row with username and menu
                    Row(
                      mainAxisAlignment:
                          isAuthor
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.spaceBetween,
                      children: [
                        if (!isAuthor)
                          AppIconButton(
                            icon:
                                Platform.isIOS
                                    ? Icons.arrow_back_ios
                                    : Icons.arrow_back,
                            onPressed: () => Navigator.pop(context),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            AppIconButton(
                              icon: Icons.expand_more,
                              onPressed: () {},
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '@$username',
                              style: textTheme.bodyLarge?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 15),
                            if (isAuthor)
                              AppIconButton(
                                icon: Icons.notifications_active_outlined,
                                onPressed:
                                    () => context.showLoadingSnackbar(
                                      loc.profileScreenLoadingNotifications,
                                    ),
                              ),
                            if (isAuthor)
                              AppIconButton(
                                icon: Icons.menu,
                                onPressed:
                                    () => context.push(
                                      '/settings',
                                      extra: widget.currentUserId,
                                    ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    ProfileHeader(
                      mode: ProfileHeaderMode.detailed,
                      displayName: displayName,
                      userId: widget.profileUserId,
                      bio: bio,
                      isCurrentUser: isAuthor,
                      avatarUrl: avatarUrl,
                      bookingCount: bookingCount,
                      isLoading: isLoading,
                      shopingCount: shopingCount,
                      onMessagePressed:
                          widget.currentUserId.isEmpty
                              ? () {
                                context.showErrorSnackbar(
                                  loc.profileScreenSignInToChatMessage,
                                );
                              }
                              : isAuthor
                              ? null // Can't message yourself
                              : () => _startPrivateChat(),

                      onEditPressed:
                          isAuthor
                              ? () => context.push(
                                '/editScreen',
                                extra: widget.currentUserId,
                              )
                              : null,
                      onFollowPressed:
                          !isAuthor
                              ? () {
                                context.showLoadingSnackbar(
                                  loc.profileScreenFollowFeatureComingSoon,
                                );
                              }
                              : null,
                      showStats: true,
                      showActions: true,
                    ),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: TabBarDelegate(
                tabs: tabs,
                tabController: _tabController,
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children:
              tabs
                  .map((tab) => tab.content ?? const SizedBox.shrink())
                  .toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final loc = AppLocalizations.of(context)!;
    final isAuthor = widget.profileUserId == widget.currentUserId;

    // ✅ Direct data from search result (no need to fetch again)

    // ✅ IMPORTANT FIX: Use different providers for author vs other users
    AsyncValue<Profile?> profileAsync;

    if (isAuthor) {
      // For own profile - use currentUserProfileProvider (auto-refreshes after edit)
      profileAsync = ref.watch(currentUserProfileProvider);
    } else {
      // For other users - fetch directly
      profileAsync = ref.watch(profileProvider(userId: widget.profileUserId));
    }

    // Loading state
    if (profileAsync.isLoading) {
      return _buildLoadingShimmer(true);
    }

    // Error or missing state
    if (profileAsync.hasError || profileAsync.value == null) {
      return Scaffold(
        body: ErrorStateWidget(
          showDetails: true,
          onPrimaryAction: () {
            if (isAuthor) {
              ref.invalidate(currentUserProfileProvider);
            } else {
              ref.invalidate(profileProvider(userId: widget.profileUserId));
            }
          },
          subtitle: loc.profileScreenErrorLoadingProfileBody,
          errorDetails: profileAsync.error?.toString(),
          type: ErrorStateType.networkError,
        ),
      );
    }

    final profile = profileAsync.value!;
    final username = profile.username ?? 'anonymous';
    final displayName = profile.displayName ?? username;
    final bio =
        profile.bio ??
        (isAuthor
            ? loc.profileScreenEnterBioPlaceholder
            : loc.profileScreenNoBioYet);
    final avatarUrl = profile.avatarUrl;

    return _buildBody(
      username: username,
      displayName: displayName,
      bio: bio,
      avatarUrl: avatarUrl ?? '',
      isAuthor: isAuthor,
      bookingCount: 3452,
      shopingCount: 24325,
      isLoading: false,
      loc: loc,
    );
  }
}
