// lib/features/chat/presentation/screens/chat_settings_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/services/media/image_picker_service.dart';
import 'package:attune/core/widgets/profile_avatar.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/services/chat_image_preparer.dart';
import 'package:attune/features/chat/domain/services/relationship_chat_name_validator.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lets either partner set/edit a name and photo for their relationship's
/// chat — e.g. "Perla" + "Javics" -> "Japerl34". See
/// docs/superpowers/specs/2026-08-11-couple-chat-identity-design.md.
///
/// Reached by tapping the conversation name/avatar in ChatScreen's AppBar.
/// Not gated to "the person who set it" — either partner may edit at any
/// time the relationship is active, per the spec's explicit "no per-partner
/// override" decision.
class ChatSettingsScreen extends ConsumerStatefulWidget {
  const ChatSettingsScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  ConsumerState<ChatSettingsScreen> createState() =>
      _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends ConsumerState<ChatSettingsScreen> {
  final _imagePicker = ImagePickerService();
  late final TextEditingController _nameController;

  bool _isSavingName = false;
  bool _isUploadingPhoto = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.conversation.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final validation = validateRelationshipChatName(_nameController.text);
    if (!validation.isValid) {
      setState(() => _errorMessage = validation.errorMessage);
      return;
    }

    setState(() {
      _isSavingName = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(chatRepositoryProvider);
      await repository.setRelationshipChatName(
        relationshipId: widget.conversation.relationshipId,
        chatName: validation.trimmedName!,
      );
      if (!mounted) return;
      ref.read(conversationsRefreshProvider.notifier).state++;
      context.showSuccessSnackbar('Chat name updated.');
    } catch (_) {
      if (!mounted) return;
      // Checklist 5.5: generic, no internal error text surfaced.
      setState(
        () => _errorMessage = "Couldn't update the name — try again.",
      );
    } finally {
      if (mounted) setState(() => _isSavingName = false);
    }
  }

  Future<void> _changePhoto() async {
    final picked = await _imagePicker.pickImage(
      fromCamera: false,
      crop: true,
      lockAspectRatio: true,
    );
    if (picked == null || !mounted) return;

    final PreparedChatImage prepared;
    try {
      prepared = await const ChatImagePreparer().prepare(picked.path);
    } on ChatImageRejected catch (_) {
      if (!mounted) return;
      setState(
        () =>
            _errorMessage =
                "That photo couldn't be used — try a different one.",
      );
      return;
    }
    if (!mounted) return;

    setState(() {
      _isUploadingPhoto = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(chatRepositoryProvider);
      final intent = await repository.createRelationshipAvatarUploadIntent(
        relationshipId: widget.conversation.relationshipId,
        mimeType: prepared.mimeType,
      );
      await repository.uploadRelationshipAvatarImage(
        intent: intent,
        localPath: prepared.file.path,
        mimeType: prepared.mimeType,
      );
      await repository.applyRelationshipAvatar(
        relationshipId: widget.conversation.relationshipId,
        intentId: intent.intentId,
      );
      if (!mounted) return;
      ref.read(conversationsRefreshProvider.notifier).state++;
      context.showSuccessSnackbar('Chat photo updated.');
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _errorMessage = "Couldn't update the photo — try again.",
      );
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isBusy = _isSavingName || _isUploadingPhoto;

    return Scaffold(
      appBar: AppBar(title: const Text('Chat settings')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(Spacing.lg.h),
          children: [
            Center(
              child: GestureDetector(
                onTap: isBusy ? null : _changePhoto,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ProfileAvatar(
                      avatarUrl: widget.conversation.avatarUrl ?? '',
                      size: 112.h,
                      currentUserId: widget.conversation.relationshipId,
                      // No navigation transition animates this avatar in from
                      // elsewhere, and reusing conversation.relationshipId as
                      // a Hero tag risks colliding with a real per-user
                      // ProfileAvatar Hero elsewhere in the tree.
                      enableHero: false,
                    ),
                    if (_isUploadingPhoto) const CircularLoadingIndicator(),
                  ],
                ),
              ),
            ),
            Gap(Spacing.sm.h),
            Center(
              child: TextButton(
                onPressed: isBusy ? null : _changePhoto,
                child: const Text('Change photo'),
              ),
            ),
            Gap(Spacing.xl.h),
            AppTextFormField(
              controller: _nameController,
              label: 'Chat name',
              hintText: 'e.g. Japerl34',
              enabled: !isBusy,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _saveName(),
            ),
            Gap(Spacing.sm.h),
            Text(
              'Visible to both of you. Either partner can change this at any time.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (_errorMessage != null) ...[
              Gap(Spacing.smMd.h),
              Text(
                _errorMessage!,
                style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
              ),
            ],
            Gap(Spacing.lg.h),
            AppButton(
              label: 'Save',
              isLoading: _isSavingName,
              onPressed: isBusy ? null : _saveName,
            ),
          ],
        ),
      ),
    );
  }
}
