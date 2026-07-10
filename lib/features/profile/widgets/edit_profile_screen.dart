// lib/features/settings/screens/settings_screen.dart

import 'package:attune/core/providers/profile_providers/profile_edit_provider.dart';
import 'package:attune/core/providers/profile_providers/profile_provider.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/text_field_loading_indicator.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/profile/models/profile_role.dart';
import 'package:attune/features/profile/widgets/editable_profile_avatar.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  final String currentUserId;

  const EditProfileScreen({super.key, required this.currentUserId});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _userNameController;
  late final TextEditingController _bioController;
  late String _originalName;
  late String _originalUsername;
  late String _originalBio;
  late String _originalAvatarUrl;

  // Role selection state
  AccountType? _selectedRole;
  bool _isSavingRole = false;
  List<UserRole> _currentRoles = [];

  // Available roles for selection
  final List<AccountType> _availableRoles = [
    AccountType.client,
    AccountType.shop,
    AccountType.worker,
  ];

  @override
  void initState() {
    super.initState();
    final profile = ref.read(currentUserProfileProvider).valueOrNull;
    _originalName = profile?.displayName ?? '';
    _originalUsername = profile?.username ?? '';
    _originalBio = profile?.bio ?? '';
    _originalAvatarUrl = profile?.avatarUrl ?? '';

    // Initialize controllers with current profile values
    _nameController = TextEditingController(text: profile?.displayName ?? '');
    _userNameController = TextEditingController(text: profile?.username ?? '');
    _bioController = TextEditingController(text: profile?.bio ?? '');

    // Add listeners
    _nameController.addListener(_onNameChanged);
    _userNameController.addListener(_onUsernameChanged);
    _bioController.addListener(_onBioChanged);

    // Load current roles
    _loadCurrentRoles();
  }

  Future<void> _loadCurrentRoles() async {
    final repo = ref.read(profileRepositoryProvider);
    final roles = await repo.fetchActiveUserRoles(widget.currentUserId);
    if (mounted) {
      setState(() {
        _currentRoles = roles;
        // Set selected role to first active role
        if (roles.isNotEmpty) {
          _selectedRole = roles.first.role;
        }
      });
    }
  }

  void _onNameChanged() {
    final value = _nameController.text.trim();
    if (value != _originalName) {
      ref
          .read(profileEditProvider(widget.currentUserId).notifier)
          .setDisplayName(value);
    }
  }

  void _onUsernameChanged() {
    final value = _userNameController.text.trim();
    if (value != _originalUsername) {
      ref
          .read(profileEditProvider(widget.currentUserId).notifier)
          .setUsername(value);
    }
  }

  void _onBioChanged() {
    final value = _bioController.text.trim();
    if (value != _originalBio) {
      ref
          .read(profileEditProvider(widget.currentUserId).notifier)
          .setBio(value);
    }
  }

  Future<void> _updateRole(AccountType role) async {
    if (_selectedRole == role) return;

    setState(() {
      _isSavingRole = true;
    });

    try {
      final repo = ref.read(profileRepositoryProvider);

      // If user already has a primary role, remove it (or keep multiple)
      // For now, we'll replace the primary role
      if (_currentRoles.isNotEmpty) {
        await repo.removeRole(widget.currentUserId, _currentRoles.first.role);
      }

      // Add new role
      await repo.addRole(widget.currentUserId, role);

      // Update local state
      setState(() {
        _selectedRole = role;
        _currentRoles = [
          UserRole(
            id: '',
            userId: widget.currentUserId,
            role: role,
            isActive: true,
            metadata: {},
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ];
      });

      // Refresh role providers so HomeScreen re-evaluates tabs immediately.
      ref.invalidate(currentUserProfileProvider);
      ref.invalidate(currentUserPrimaryRoleProvider);

      if (mounted) {
        context.showSuccessSnackbar(
          'Account type updated to ${role.displayName}',
        );
      }
    } catch (e) {
      if (mounted) {
        print(e.toString());
        context.showErrorSnackbar('Error updating role: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingRole = false;
        });
      }
    }
  }

  Widget _buildRoleSelector(AppLocalizations loc) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.editProfileScreenAccountTypeLabel,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
        Gap(Spacing.md),
        Text(
          loc.editProfileScreenAccountTypeSubtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        Gap(Spacing.sm),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children:
              _availableRoles.map((role) {
                final isSelected = _selectedRole == role;
                final isDisabled = _isSavingRole;

                return AppFilterChip(
                  label: role.displayName,
                  selected: isSelected,
                  onSelected:
                      isDisabled
                          ? (bool) {}
                          : (selected) {
                            if (selected) {
                              _updateRole(role);
                            }
                          },
                  selectedColor: colorScheme.primary,
                  backgroundColor: colorScheme.background,
                  labelColor:
                      isSelected
                          ? Colors.white
                          : colorScheme.onSurface.withOpacity(0.6),
                  borderWidth: 0.3,
                  avatarIcon: role.icon,
                );
              }).toList(),
        ),
        if (_isSavingRole)
          Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: Row(
              children: [
                const CircularLoadingIndicator(),
                Gap(Spacing.md.w),
                Text(
                  loc.editProfileScreenUpdatingAccountType,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _userNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;

    // Get current user
    final currentUser = ref.watch(currentUserProvider);
    final userId = currentUser?.id;

    // Handle not logged in state
    if (userId == null) {
      return Scaffold(body: Center(child: Text(loc.editProfileScreenPleaseLogIn)));
    }

    // Watch profile and edit state
    final profileAsync = ref.watch(currentUserProfileProvider);
    final editState = ref.watch(profileEditProvider(userId));

    // Handle error state
    if (profileAsync.hasError) {
      return Scaffold(
        body: Center(
          child: ErrorStateWidget(
            subtitle: 'Error loading profile: ${profileAsync.error}',
            onPrimaryAction: () => ref.refresh(currentUserProfileProvider),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.neutral,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: true,
        title: Text(
          loc.editProfileScreenTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
      ),
      body: Form(
        child: ListView(
          padding: EdgeInsets.all(Spacing.lg),
          children: [
            EditableProfileAvatar(
              currentUserId: widget.currentUserId,
              currentAvatarUrl: _originalAvatarUrl,
              size: 100.h,
              onErrorDismiss: () {},
            ),
            Gap(Spacing.md),
            CardInkWell(
              margin: EdgeInsets.only(bottom: 10.h),
              child: Column(
                children: [
                  // Name field
                  AppTextFormField(
                    controller: _nameController,
                    isSmall: true,
                    label: loc.editProfileScreenNameLabel,
                    hintText: loc.editProfileScreenNameHint,
                    prefixIcon: Icons.person_outline,
                    maxLines: 1,
                    keyboardType: TextInputType.name,
                    textInputAction: TextInputAction.next,
                    errorText: editState.displayNameError,
                    suffixIcon:
                        editState.isSavingDisplayName
                            ? const TextFieldLoadingIndicator()
                            : null,
                  ),
                  // Username field
                  AppTextFormField(
                    controller: _userNameController,
                    isSmall: true,
                    label: loc.editProfileScreenUsernameLabel,
                    hintText: loc.editProfileScreenUsernameHint,
                    prefixIcon: Icons.alternate_email,
                    maxLines: 1,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    errorText: editState.usernameError,
                    suffixIcon:
                        editState.isSavingUsername
                            ? const TextFieldLoadingIndicator()
                            : null,
                  ),
                  // Bio field
                  AppTextFormField(
                    controller: _bioController,
                    isSmall: true,
                    label: loc.editProfileScreenBioLabel,
                    hintText: loc.editProfileScreenBioHint,
                    prefixIcon: Icons.info_outline,
                    maxLines: 3,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.done,
                    errorText: editState.bioError,
                    suffixIcon:
                        editState.isSavingBio
                            ? const TextFieldLoadingIndicator()
                            : null,
                  ),
                  // ✅ Role Selection Section (Added here)
                  Gap(Spacing.lg),

                  _buildRoleSelector(loc),
                  Gap(Spacing.md),
                ],
              ),
            ),
            Gap(Spacing.sm),
            CardInkWell(
              margin: EdgeInsets.only(bottom: 10.h),
              onTap: () {},
              child: Column(
                children: [
                  InfoRowWidget(
                    subtitle: loc.editProfileScreenEditShopSubtitle,
                    title: loc.editProfileScreenEditShopTitle,
                    icon: Icons.storefront_rounded,
                    avatarRadius: 25.h,
                    onTap: () => context.push('/myShopsScreen'),
                    showAvatar: false,
                    showTrailingArrow: true,
                    showDivider: false,
                  ),
                ],
              ),
            ),

            CardInkWell(
              margin: EdgeInsets.only(bottom: 10.h),
              onTap: () {},
              child: Column(
                children: [
                  InfoRowWidget(
                    subtitle: loc.editProfileScreenEditShopSubtitle,
                    title: loc.editProfileScreenEditWorkProfileTitle,
                    icon: Icons.person,
                    avatarRadius: 25.h,
                    onTap:
                        () => {
                         
                        },
                    showAvatar: false,
                    showTrailingArrow: true,
                    showDivider: false,
                  ),
                ],
              ),
            ),
            Gap(Spacing.xl),
          ],
        ),
      ),
    );
  }
}
