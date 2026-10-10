// lib/features/pulse/presentation/screens/pulse_identity_row.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/services/media/image_picker_service.dart';
import 'package:attune/core/widgets/profile_avatar.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/services/chat_image_preparer.dart';
import 'package:attune/features/chat/domain/services/relationship_chat_name_validator.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrintStack;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';

/// The couple's identity row — avatar, editable chat name — shown at the
/// top of the Settings tab (`_ChatSettingsRowsTab` in pulse_tab.dart).
///
/// Extracted out of the old ChatIdentityCard, which also carried a
/// 4-photo "recently shared" strip and the "Relationship Center" panel.
/// That card was deleted: the photo strip was removed entirely ("Media,
/// docs and links" in ChatSettingsStaticRows already covers shared
/// photos), and the Relationship Center panel moved into PulseScreen.
/// This widget is just the identity row and its tap-to-edit sheet.
///
/// Self-contained ConsumerStatefulWidget: owns nothing but the tap
/// target, so it can be dropped anywhere without a parent Scaffold or
/// State object to host it.
class PulseIdentityRow extends ConsumerWidget {
  const PulseIdentityRow({super.key, required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InfoRowWidget(
      title: conversation.name,
      subTitleFontSize: 12.h,
      textMainAxisAlignment: MainAxisAlignment.center,
      subtitle: '"Choose a couple tag like Japerl34" or "TeamNogre".',
      // InfoRowWidget's constructor asserts icon != null || imageUrl !=
      // null — a bare null (no avatar set yet, the common state for a
      // brand-new couple) would fail it, even though the ProfileAvatar
      // it builds internally already treats an empty string as "show the
      // placeholder" just fine.
      imageUrl: conversation.avatarUrl ?? '',
      avatarRadius: 50.h,
      showDivider: false,
      padAvatarTop: true,
      trailing: AppIconButton(icon: Icons.edit, size: IconSizes.md.h),
      showTrailingArrow: false,
      onTap: () => PulseIdentityEditSheet.show(context, conversation),
    );
  }
}

/// The avatar/name editor, shown as the app's shared bottom sheet
/// (BottomSheetUtils.showDocumentationBottomSheet — same sheet chrome used
/// throughout the app, e.g. FamilyMemberEditSheet, rather than a one-off
/// showModalBottomSheet here) via [show]. Centered column layout (avatar
/// above the name field).
///
/// Owns its own name/photo state — extracted out of PulseIdentityRow so
/// the row itself only needs to know how to launch this, not how to edit
/// anything. Saving/uploading bumps conversationsRefreshProvider, which is
/// what makes the row behind the sheet show the new name/photo once the
/// sheet closes.
///
/// ## Everything autosaves — there is no Save button
///
/// - **Photo**: writes as soon as one is picked and cropped (this was
///   always true; the old Save button only ever gated the name).
/// - **Name**: committed by AppTextFormField's own debouncer ~500ms after
///   typing stops, and again on focus loss so tapping away commits
///   immediately. A save still in its debounce window when the sheet is
///   dismissed is flushed from `dispose` — AppTextFormField cancels rather
///   than flushes its debouncer there, so without that the last edit would
///   be silently dropped.
///
/// Redundant writes are skipped (`_lastSavedName`) and overlapping ones
/// coalesced (`_pendingName`) rather than fired concurrently, since two
/// in-flight writes have no guaranteed completion order — the older value
/// could otherwise land last and win.
class PulseIdentityEditSheet extends ConsumerStatefulWidget {
  const PulseIdentityEditSheet({super.key, required this.conversation});

  final Conversation conversation;

  /// Presents this form in the app's shared bottom sheet.
  static Future<void> show(BuildContext context, Conversation conversation) {
    final colorScheme = Theme.of(context).colorScheme;
    return BottomSheetUtils.showDocumentationBottomSheet<void>(
      context: context,
      backgroundColor: colorScheme.neutral,
      widget: PulseIdentityEditSheet(conversation: conversation),
    );
  }

  @override
  ConsumerState<PulseIdentityEditSheet> createState() =>
      _PulseIdentityEditSheetState();
}

class _PulseIdentityEditSheetState
    extends ConsumerState<PulseIdentityEditSheet> {
  final _imagePicker = ImagePickerService();
  late final TextEditingController _nameController;

  bool _isSavingName = false;
  bool _isUploadingPhoto = false;
  bool _nameJustSaved = false;
  String? _errorMessage;

  /// Local path of a photo uploaded during THIS sheet session, shown in
  /// place of widget.conversation.avatarUrl (a snapshot taken when the
  /// sheet opened, which never refreshes while it stays open).
  String? _localAvatarPath;

  /// The last value successfully written (or the value the sheet opened
  /// with). Guards against redundant writes: the debounce also fires on
  /// focus loss, so closing the sheet without editing anything would
  /// otherwise re-save the identical name.
  late String _lastSavedName;

  /// A save queued because one was already in flight. The debounce can
  /// out-pace the network on a slow connection; rather than fire
  /// overlapping writes (whose completion order isn't guaranteed, so the
  /// older value could land last), the newest pending value is parked here
  /// and run once the current write finishes.
  String? _pendingName;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.conversation.name);
    _lastSavedName = widget.conversation.name.trim();
  }

  @override
  void dispose() {
    // No dispose-time flush needed: dismissing the sheet unfocuses the
    // field first, and AppTextFormField flushes any pending debounce on
    // focus loss (_onFocusChange), so an edit typed right before closing
    // is already committed by the time this runs. Verified by test —
    // "an edit still inside the debounce window when the sheet is
    // dismissed is still saved". (An earlier dispose-time flush here was
    // both redundant and broken: Riverpod invalidates `ref` before
    // dispose, so reading a provider there throws.)
    _nameController.dispose();
    super.dispose();
  }

  /// Debounced autosave, wired to AppTextFormField's own debouncer (500ms
  /// by default) — there is no Save button. Also fires on focus loss, so
  /// tapping away commits immediately rather than waiting out the timer.
  Future<void> _autoSaveName(String raw) async {
    final validation = validateRelationshipChatName(raw);
    if (!validation.isValid) {
      // Invalid mid-edit (cleared the field to retype, or overran 30
      // chars) is a normal state, not a failure — show the rule, write
      // nothing, and leave the last saved name intact in the database.
      if (mounted) {
        setState(() {
          _errorMessage = validation.errorMessage;
          _nameJustSaved = false;
        });
      }
      return;
    }

    final trimmed = validation.trimmedName!;
    // Nothing actually changed (reopened the sheet, tapped away, retyped
    // the same thing) — skip the round trip entirely.
    if (trimmed == _lastSavedName) {
      if (mounted && _errorMessage != null) {
        setState(() => _errorMessage = null);
      }
      return;
    }

    // Coalesce rather than overlap: park the newest value and let the
    // in-flight save pick it up when it lands.
    if (_isSavingName) {
      _pendingName = trimmed;
      return;
    }

    setState(() {
      _isSavingName = true;
      _errorMessage = null;
      _nameJustSaved = false;
    });

    try {
      final repository = ref.read(chatRepositoryProvider);
      await repository.setRelationshipChatName(
        relationshipId: widget.conversation.relationshipId,
        chatName: trimmed,
      );
      _lastSavedName = trimmed;
      if (!mounted) return;
      ref.read(conversationsRefreshProvider.notifier).state++;
      setState(() => _nameJustSaved = true);
    } catch (_) {
      if (!mounted) return;
      // Checklist 5.5: generic, no internal error text surfaced.
      setState(() => _errorMessage = "Couldn't update the name — try again.");
    } finally {
      if (mounted) setState(() => _isSavingName = false);

      // Drain a value that arrived while this write was in flight.
      final queued = _pendingName;
      _pendingName = null;
      if (queued != null && queued != _lastSavedName && mounted) {
        await _autoSaveName(queued);
      }
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
    } on ChatImageRejected catch (error) {
      // The rejection CODE is the whole diagnostic value here (too large,
      // bad MIME, decode failure) — ChatLog.e would shape it to a length
      // and tell us nothing.
      ChatLog.diagnostic('relationship avatar rejected at prepare', error);
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

    // Which of the three sequential calls failed is most of the
    // diagnostic value — "photo upload failed" alone can't distinguish an
    // RPC/feature-flag rejection (intent) from a storage RLS or MIME
    // rejection (upload) from a server-side size/ownership check (apply).
    var stage = 'create intent';
    try {
      final repository = ref.read(chatRepositoryProvider);
      final intent = await repository.createRelationshipAvatarUploadIntent(
        relationshipId: widget.conversation.relationshipId,
        mimeType: prepared.mimeType,
      );
      stage = 'upload object';
      await repository.uploadRelationshipAvatarImage(
        intent: intent,
        localPath: prepared.file.path,
        mimeType: prepared.mimeType,
      );
      stage = 'apply avatar';
      await repository.applyRelationshipAvatar(
        relationshipId: widget.conversation.relationshipId,
        intentId: intent.intentId,
      );
      if (!mounted) return;
      // Show the local copy right away. conversationsRefreshProvider below
      // updates every OTHER consumer, but this sheet holds a Conversation
      // captured at open time that never changes — so without this the
      // avatar here stayed stale until the sheet was reopened.
      setState(() => _localAvatarPath = prepared.file.path);
      ref.read(conversationsRefreshProvider.notifier).state++;
      context.showSuccessSnackbar('Chat photo updated.');
    } catch (error, stackTrace) {
      // diagnostic, not ChatLog.e: this is an infrastructure rejection
      // (RLS policy, storage MIME allowlist, RPC feature gate) whose
      // REASON is the entire diagnostic value. ChatLog.e shapes it to a
      // length, which is what left this failure invisible in the console.
      ChatLog.diagnostic(
        'relationship avatar failed at $stage '
        '(mime=${prepared.mimeType}, bytes=${prepared.byteSize})',
        error,
      );
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _errorMessage = "Couldn't update the photo — try again.");
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Only the photo's OWN upload blocks picking another photo — a name
    // autosave in flight is unrelated and must not lock the avatar (or,
    // below, the text field) while it lands.
    final isUploading = _isUploadingPhoto;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        children: [
          BottomSheetHeader(title: 'Edit chat identity'),
          Gap(Spacing.lg.h),
          GestureDetector(
            onTap: isUploading ? null : _changePhoto,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ProfileAvatar(
                  // Prefer the just-picked local file over the stored
                  // remote URL. widget.conversation is a snapshot captured
                  // when the sheet opened and never updates, so without
                  // this the avatar here stayed stale until the sheet was
                  // closed and reopened. ProfileAvatar renders a non-http
                  // path via Image.file, so the local copy shows the new
                  // photo the instant the upload lands — no waiting on a
                  // refetch and a freshly signed URL.
                  avatarUrl:
                      _localAvatarPath ?? widget.conversation.avatarUrl ?? '',
                  size: 88.h,
                  currentUserId: widget.conversation.relationshipId,
                  // No navigation transition animates this avatar in from
                  // elsewhere, and reusing conversation.relationshipId as a
                  // Hero tag risks colliding with a real per-user
                  // ProfileAvatar Hero elsewhere in the tree.
                  enableHero: false,
                ),
                if (_isUploadingPhoto) const CircularLoadingIndicator(),
              ],
            ),
          ),
          Gap(Spacing.sm.h),
          AppTextButton(
            fontSize: 12.h,
            onPressed: isUploading ? null : _changePhoto,
            text: 'Change photo',
          ),
          Gap(Spacing.md.h),
          AppTextFormField(
            fillColor: colorScheme.neutral,
            controller: _nameController,
            label: 'Coupples name',
            hintText: 'e.g. Japerl34',
            // Deliberately NOT disabled while a save is in flight —
            // autosave fires constantly as the user types, and disabling
            // the field would steal focus and interrupt them mid-word on a
            // slow connection. Overlapping writes are handled by
            // _autoSaveName's own coalescing instead.
            // Typing is the obvious next action the moment this sheet
            // opens — skips the extra tap into the field every edit
            // otherwise needed.
            autofocus: true,
            textInputAction: TextInputAction.done,
            // There is no Save button: the field's own debouncer commits
            // ~500ms after typing stops, and AppTextFormField also flushes
            // on focus loss so tapping away saves immediately.
            onDebouncedChanged: _autoSaveName,
            onFieldSubmitted: _autoSaveName,
          ),
          Gap(Spacing.smMd.h),
          _SaveStatusLine(
            isSaving: _isSavingName,
            justSaved: _nameJustSaved,
            errorMessage: _errorMessage,
          ),
          Gap(Spacing.lg.h),
        ],
      ),
    );
  }
}

/// The single line under the name field that replaces the old Save button:
/// saving / saved / error / the standing "visible to both of you" note.
///
/// One line that swaps content, rather than a snackbar per save — the
/// debounce can commit several times during one editing session, and a
/// stack of "Chat name updated." toasts for what the user experiences as a
/// single edit reads as noise.
class _SaveStatusLine extends StatelessWidget {
  const _SaveStatusLine({
    required this.isSaving,
    required this.justSaved,
    required this.errorMessage,
  });

  final bool isSaving;
  final bool justSaved;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final (String text, Color color, IconData? icon) = switch ((
      errorMessage,
      isSaving,
      justSaved,
    )) {
      (final String message, _, _) => (
        message,
        colorScheme.error,
        Icons.error_outline,
      ),
      (_, true, _) => ('Saving…', colorScheme.onSurfaceVariant, null),
      (_, _, true) => ('Saved', colorScheme.success, Icons.check_rounded),
      _ => (
        'Visible to both of you. Either partner can change this at any time.',
        colorScheme.onSurfaceVariant,
        null,
      ),
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14.h, color: color),
          Gap(Spacing.xs.w),
        ],
        Flexible(
          child: Text(
            text,
            style: textTheme.bodySmall?.copyWith(color: color),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
