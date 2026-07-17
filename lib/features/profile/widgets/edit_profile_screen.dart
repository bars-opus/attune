// lib/features/settings/screens/settings_screen.dart

import 'package:attune/core/providers/profile_providers/profile_edit_provider.dart';
import 'package:attune/core/providers/profile_providers/profile_provider.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/text_field_loading_indicator.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
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
