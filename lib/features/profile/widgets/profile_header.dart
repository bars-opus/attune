
import 'package:attune/core/widgets/profile_avatar.dart';
import 'package:attune/features/auth/utility/auth_exports.dart';

/// Profile header display modes
enum ProfileHeaderMode {
  compact, // For lists, cards (small)
  detailed, // For profile pages (medium)
  expanded, // For hero sections (large)
}

class ProfileHeader extends ConsumerWidget {
  final ProfileHeaderMode mode;
  final String displayName;
  final String? username;
  final String? bio;
  final String? avatarUrl;
  // final String? coverImageUrl;
  final int? bookingCount;
  final int? shopingCount;
  final VoidCallback? onEditPressed;
  final VoidCallback? onFollowPressed;
  final VoidCallback? onMessagePressed;
  final VoidCallback? onProfileNavigatePressed;

  final bool isFollowing;
  final bool isCurrentUser;
  final bool showStats;
  final bool showActions;
  final String userId;
  final Color? textColor;
  final Color? bioTextColor;

  final bool enableHero;
  final bool enableOnProfileNavigatePressed;

  final bool isLoading;

  const ProfileHeader({
    super.key,
    required this.mode,
    required this.displayName,
    required this.userId,
    this.username,
    this.bio,
    this.avatarUrl,
    // this.coverImageUrl,
    this.bookingCount,
    this.shopingCount,
    this.onEditPressed,
    this.onFollowPressed,
    this.onMessagePressed,
    this.onProfileNavigatePressed,
    this.isFollowing = false,
    this.isCurrentUser = false,
    this.showStats = true,
    this.showActions = true,
    this.textColor,
    this.enableHero = true,
    this.isLoading = false,
    this.bioTextColor,
    this.enableOnProfileNavigatePressed = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final user = ref.watch(currentUserProvider);
    final loc = AppLocalizations.of(context)!;

    switch (mode) {
      case ProfileHeaderMode.compact:
        return enableOnProfileNavigatePressed
            ? GestureDetector(
              onTap:
                  onProfileNavigatePressed ??
                  () => context.push(
                    '/profileScreen',
                    extra: {
                      'profileUserId': userId,
                      'currentUserId': user == null ? '' : user.id,
                    },
                  ),

              child: _buildCompactHeader(
                context,
                colorScheme,
                textTheme,
                user == null ? '' : user.id,
              ),
            )
            : _buildCompactHeader(
              context,
              colorScheme,
              textTheme,
              user == null ? '' : user.id,
            );
      case ProfileHeaderMode.detailed:
        return _buildDetailedHeader(context, colorScheme, textTheme, loc);
      case ProfileHeaderMode.expanded:
        return _buildExpandedHeader(context, colorScheme, textTheme, loc);
    }
  }

  Widget _buildCompactHeader(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
    String currentUserId,
  ) {
    return Container(
      color: Colors.transparent,
      child: Row(
        children: [
          ProfileAvatar(
            avatarUrl: avatarUrl ?? '',
            currentUserId: userId,
            size: 40.r,
            enableHero: enableHero,
          ),
          Gap(Spacing.md.w),

          // Name & username
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: textColor ?? colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (username != null) ...[
                  // Gap(Spacing.xs.h),
                  Text(
                    username!,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                // Bio
                if (bio != null && bio!.isNotEmpty) ...[
                  Text(
                    bio ?? '',
                    style: textTheme.bodySmall?.copyWith(
                      color: bioTextColor ?? textColor ?? colorScheme.onSurface,
                      height: 1.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Follow button (if not current user)
          // if (showActions && !isCurrentUser && onFollowPressed != null)
          //   _buildFollowButton(context, colorScheme, compact: true),
        ],
      ),
    );
  }

  Widget _buildDetailedHeader(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
    AppLocalizations loc,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cover image (optional)

        // Content padding
        Padding(
          padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar and actions row
              Row(
                children: [
                  // Avatar
                  isLoading
                      ? CircularLoadingIndicator(size: 80.r)
                      : ProfileAvatar(
                        avatarUrl: avatarUrl ?? '',
                        currentUserId: userId,
                        size: 80.r,
                      ),
                  Gap(10.w),
                  // Stats
                  if (showStats &&
                      (bookingCount != null || shopingCount != null)) ...[
                    // Gap(Spacing.lg.h),
                    _buildStatsRow(context, colorScheme, textTheme, loc),
                  ],
                ],
              ),

              Gap(Spacing.md.h),
              Text(
                displayName,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),

              // Bio
              if (bio != null && bio!.isNotEmpty) ...[
                GestureDetector(
                  onTap: () {
                    BottomSheetUtils.showDocumentationBottomSheet(
                      context: context,
                      widget: ReadAll(body: bio ?? ''),
                    );
                  },
                  child: Text(
                    bio ?? '',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                      height: 1.5,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],

              if (showActions) Gap(Spacing.lg.h),
              if (showActions) _buildActionButtons(context, colorScheme, loc),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedHeader(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
    AppLocalizations loc,
  ) {
    return Padding(
      padding: EdgeInsets.all(Spacing.md.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar
          ProfileAvatar(
            avatarUrl: avatarUrl ?? '',
            currentUserId: userId,
            size: 100.r,
          ),

          Gap(Spacing.md.h),

          // Name
          Text(
            displayName,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          Gap(Spacing.md.h),
          // Stats
          if (showStats && (bookingCount != null || shopingCount != null)) ...[
            _buildStatsRow(context, colorScheme, textTheme, loc, expanded: true),
          ],

          // Bio
          if (bio != null && bio!.isNotEmpty) ...[
            Gap(Spacing.md.h),
            Text(
              bio!,
              style: textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurface,
                height: 1.6,
              ),
              textAlign: TextAlign.start,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // Actions
          if (showActions) ...[
            Gap(Spacing.lg.h),
            _buildActionButtons(context, colorScheme, loc, expanded: true),
          ],
        ],
      ),
    );
  }

  // Widget _buildAvatar(
  //   BuildContext context,
  //   ColorScheme colorScheme, {
  //   required double size,
  // }) {
  //   return Container(
  //     width: size,
  //     height: size,
  //     decoration: BoxDecoration(
  //       shape: BoxShape.circle,
  //       border: Border.all(color: colorScheme.surface, width: 3.w),
  //       boxShadow: [
  //         BoxShadow(
  //           color: Colors.black.withOpacity(0.1),
  //           blurRadius: 8.r,
  //           offset: Offset(0, 2.h),
  //         ),
  //       ],
  //     ),
  //     child: ClipOval(
  //       child:
  //           avatarUrl != null
  //               ? Image.network(
  //                 avatarUrl!,
  //                 fit: BoxFit.cover,
  //                 errorBuilder:
  //                     (context, error, stackTrace) =>
  //                         _buildAvatarPlaceholder(colorScheme, size),
  //               )
  //               : _buildAvatarPlaceholder(colorScheme, size),
  //     ),
  //   );
  // }

  Widget _buildStatsRow(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
    AppLocalizations loc, {
    bool expanded = false,
  }) {
    return Row(
      mainAxisAlignment:
          expanded ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        if (bookingCount != null) ...[
          _buildStatItem(
            context,
            value: bookingCount!,
            label: loc.profileHeaderBookingsStatLabel,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
          Gap(expanded ? Spacing.xl.w : Spacing.lg.w),
        ],
        if (shopingCount != null)
          _buildStatItem(
            context,
            value: shopingCount!,
            label: loc.profileHeaderOrdersStatLabel,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
      ],
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required int value,
    required String label,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    return Column(
      children: [
        Text(
          _formatNumber(value),
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        Gap(Spacing.xs.h),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    ColorScheme colorScheme,
    AppLocalizations loc, {
    bool expanded = false,
  }) {
    if (isCurrentUser) {
      return _buildEditButton(context, colorScheme, loc, expanded: expanded);
    }
    return _buildMessageButton(loc);

    // Row(
    //   mainAxisAlignment:
    //       expanded ? MainAxisAlignment.center : MainAxisAlignment.start,
    //   children: [
    //     if (onFollowPressed != null)
    //       _buildFollowButton(context, colorScheme, expanded: expanded),

    //     if (onMessagePressed != null) ...[
    //       Gap(Spacing.md.w),
    //       _buildMessageButton(context, colorScheme, expanded: expanded),
    //     ],
    //   ],
    // );
  }

  Widget _buildEditButton(
    BuildContext context,
    ColorScheme colorScheme,
    AppLocalizations loc, {
    bool expanded = false,
  }) {
    return AppButton(
      height: 35.h,
      label: loc.profileHeaderEditProfileButton,
      onPressed: onEditPressed,
      padding: Spacing.horizontalMd,
      variant: ButtonVariant.outline,
      size: ButtonSize.small,
      width: double.infinity,
      elevation: 0,
    );

    //  Row(
    //   children: [
    //     // Cancel button
    // AppButton(
    //   height: 35.h,
    //   label: "Edit profile",
    //   onPressed: onEditPressed,
    //   padding: Spacing.horizontalMd,
    //   variant: ButtonVariant.outline,
    //   size: ButtonSize.small,
    //   width: double.infinity,
    //   elevation: 0,
    // ),

    //     if (!isAuthor) Gap(5.w),

    //     // Confirm button
    //   ],
    // );
  }

  // Widget _buildFollowButton(
  //   BuildContext context,
  //   ColorScheme colorScheme, {
  //   bool compact = false,
  //   bool expanded = false,
  // }) {
  //   return ElevatedButton(
  //     onPressed: onFollowPressed,
  //     style: ElevatedButton.styleFrom(
  //       foregroundColor:
  //           isFollowing ? colorScheme.onSurfaceVariant : colorScheme.onPrimary,
  //       backgroundColor:
  //           isFollowing ? colorScheme.surfaceVariant : colorScheme.primary,
  //       side: isFollowing ? BorderSide(color: colorScheme.outline) : null,
  //       padding: EdgeInsets.symmetric(
  //         horizontal:
  //             compact ? Spacing.md.w : (expanded ? Spacing.xl.w : Spacing.lg.w),
  //         vertical: compact ? Spacing.xs.h : Spacing.md.h,
  //       ),
  //       shape: RoundedRectangleBorder(
  //         borderRadius: BorderRadius.circular(20.r),
  //       ),
  //     ),
  //     child: Text(
  //       isFollowing ? 'Following' : 'Follow',
  //       style: TextStyle(
  //         fontWeight: FontWeight.w600,
  //         fontSize: compact ? 12.sp : null,
  //       ),
  //     ),
  //   );
  // }

  Widget _buildMessageButton(AppLocalizations loc) {
    return AppButton(
      elevation: 0,
      label: loc.profileHeaderMessageButton,
      customColor: isLoading ? Colors.grey.withValues(alpha: .4) : null,
      onPressed: onMessagePressed,
      size: ButtonSize.small,
      width: double.infinity,
      padding: Spacing.horizontalMd,

      height: 35.h,
    );

    //  OutlinedButton(
    //   onPressed: onMessagePressed,
    //   style: OutlinedButton.styleFrom(
    //     foregroundColor: colorScheme.onSurface,
    //     side: BorderSide(color: colorScheme.outline),
    //     padding: EdgeInsets.symmetric(
    //       horizontal: expanded ? Spacing.xl.w : Spacing.lg.w,
    //       vertical: Spacing.md.h,
    //     ),
    //     shape: RoundedRectangleBorder(
    //       borderRadius: BorderRadius.circular(20.r),
    //     ),
    //   ),
    //   child: Text('Message'),
    // );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    }
    if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }
}
