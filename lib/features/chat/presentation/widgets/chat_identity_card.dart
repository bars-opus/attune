// lib/features/chat/presentation/widgets/chat_identity_card.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/services/media/image_picker_service.dart';
import 'package:attune/core/widgets/profile_avatar.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/services/chat_image_preparer.dart';
import 'package:attune/features/chat/domain/services/relationship_chat_name_validator.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/resolved_media_url.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrintStack;
import 'package:attune/features/pulse/data/models/pulse_score.dart';
import 'package:attune/features/pulse/providers/pulse_providers.dart'
    show currentPulseScoreProvider;
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    show bothPartnersSharedProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';

/// Couple's identity card for the top of PulseTab — avatar, editable chat
/// name, a strip of the 4 most recently shared photos, and a small
/// "Relationship Center" panel.
///
/// Restructured to a creator-profile-style layout (avatar/name row, photo
/// grid, stat tiles, task rows) per a supplied reference screenshot. Real
/// data: [ProfileAvatar], the name field, and the 4-photo strip (each tile
/// is this relationship's own most-recently-shared chat image, tapping any
/// tile or "See all" opens the existing chatMedia gallery). Everything below
/// — the 3 stat tiles and the 2 task rows — is placeholder content with no
/// backing feature yet, built from existing widgets/tokens (CardInkWell,
/// InfoRowWidget, Spacing, colorScheme) rather than new one-off styling, so
/// swapping in real data later is a data change, not a redesign.
///
/// ChatSettingsScreen still renders this same widget, so the standalone
/// `chatSettings` route (currently unreached — nothing pushes it directly,
/// PulseTab embeds ChatSettingsScreen inline) keeps identical behavior.
///
/// Self-contained ConsumerStatefulWidget: owns its own name/photo state so
/// it can be dropped into a CustomScrollView sliver without a parent
/// Scaffold or State object to host it.
class ChatIdentityCard extends ConsumerStatefulWidget {
  const ChatIdentityCard({super.key, required this.conversation});

  final Conversation conversation;

  @override
  ConsumerState<ChatIdentityCard> createState() => _ChatIdentityCardState();
}

class _ChatIdentityCardState extends ConsumerState<ChatIdentityCard> {
  /// Newest-first, UNCAPPED — the strip below only ever shows the first 4,
  /// but the full count is what decides whether "See all" appears, and the
  /// full list is what the viewer needs so swiping from tile 4 still moves
  /// through every shared image, not just the 4 visible on the card.
  ///
  /// Fetched once per mount rather than kept live — same one-shot pattern
  /// ChatMediaScreen's own grid tabs use, since this card has no
  /// ChatController subscription of its own.
  late final Future<List<Message>> _recentImagesFuture = ref
      .read(chatRepositoryProvider)
      .getMediaMessages(widget.conversation.relationshipId, mediaType: 'image');

  void _openMediaGallery() {
    context.pushNamed('chatMedia', extra: widget.conversation);
  }

  /// Opens the full-screen image viewer for one tile in the strip.
  ///
  /// [images] is the same newest-first list the strip renders from;
  /// ImageViewerRouteArgs (mirroring ChatMediaScreen's own tile tap) wants
  /// chronological order so swiping moves forward the same direction as
  /// every other viewer entry point, hence the reverse — and [tappedIndex]
  /// (an index into the newest-first strip) has to be re-derived against
  /// that reversed list rather than reused as-is.
  Future<void> _openImageViewer(List<Message> images, int tappedIndex) async {
    final chronological = images.reversed.toList();
    final initialIndex = chronological.length - 1 - tappedIndex;
    final jumpToId = await context.pushNamed<String>(
      'imageViewer',
      extra: ImageViewerRouteArgs(
        images: chronological,
        initialIndex: initialIndex,
      ),
    );
    if (jumpToId != null && mounted) {
      context.pushNamed(
        'chatScreen',
        queryParameters: {'jumpTo': jumpToId},
        extra: widget.conversation,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoRowWidget(
            title: widget.conversation.name,
            subTitleFontSize: 12.h,
            textMainAxisAlignment: MainAxisAlignment.center,
            subtitle: '"Choose a couple tag like Japerl34" or "TeamNogre".',
            // InfoRowWidget's constructor asserts icon != null || imageUrl
            // != null — a bare null (no avatar set yet, the common state
            // for a brand-new couple) would fail it, even though the
            // ProfileAvatar it builds internally already treats an empty
            // string as "show the placeholder" just fine.
            imageUrl: widget.conversation.avatarUrl ?? '',
            avatarRadius: 50.h,
            showDivider: false,
            padAvatarTop: true,
            trailing: Icon(
              Icons.edit,
              size: IconSizes.md.h,
              color: colorScheme.primary,
            ),
            showTrailingArrow: false,
            onTap:
                () => ChatIdentityEditSheet.show(context, widget.conversation),
          ),
          Gap(Spacing.xl.h),
          FutureBuilder<List<Message>>(
            future: _recentImagesFuture,
            builder: (context, snapshot) {
              final images = snapshot.data ?? const <Message>[];
              // Nothing shared yet — skip the whole Media section (header
              // included), matching _RecentPhotosRow's own empty-state
              // behavior below.
              if (snapshot.connectionState == ConnectionState.done &&
                  images.isEmpty) {
                return const SizedBox.shrink();
              }

              final visible = images.take(4).toList();
              // "See all" only earns its place once the strip is actually
              // truncating something — 4 or fewer images already show
              // everything, so a "See all" there would open a gallery with
              // nothing more to reveal.
              final hasMore = images.length > 4;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Media',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (hasMore)
                        GestureDetector(
                          onTap: _openMediaGallery,
                          child: Row(
                            children: [
                              Text(
                                'See all',
                                style: textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.primary,
                                ),
                              ),
                              Gap(Spacing.md.w),
                              Icon(
                                Icons.chevron_right,
                                size: IconSizes.md.h,
                                color: colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  Gap(Spacing.sm.h),
                  _RecentPhotosRow(
                    images: visible,
                    onTapImage: (index) => _openImageViewer(images, index),
                  ),
                ],
              );
            },
          ),
          Gap(Spacing.xl.h),
          Text(
            'Relationship Center',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          Gap(Spacing.sm.h),
          const _RelationshipCenterPanel(),
        ],
      ),
    );
  }
}

/// The avatar/name editor, shown as the app's shared bottom sheet
/// (BottomSheetUtils.showDocumentationBottomSheet — same sheet chrome used
/// throughout the app, e.g. FamilyMemberEditSheet, rather than a one-off
/// showModalBottomSheet here) via [show]. Centered column layout (avatar
/// above the name field) replacing the row this used to be inline on the
/// card.
///
/// Owns its own name/photo state — extracted out of ChatIdentityCard so the
/// card itself only needs to know how to launch this, not how to edit
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
class ChatIdentityEditSheet extends ConsumerStatefulWidget {
  const ChatIdentityEditSheet({super.key, required this.conversation});

  final Conversation conversation;

  /// Presents this form in the app's shared bottom sheet.
  static Future<void> show(BuildContext context, Conversation conversation) {
    final colorScheme = Theme.of(context).colorScheme;
    return BottomSheetUtils.showDocumentationBottomSheet<void>(
      context: context,
      backgroundColor: colorScheme.neutral,
      widget: ChatIdentityEditSheet(conversation: conversation),
    );
  }

  @override
  ConsumerState<ChatIdentityEditSheet> createState() =>
      _ChatIdentityEditSheetState();
}

class _ChatIdentityEditSheetState extends ConsumerState<ChatIdentityEditSheet> {
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
          // Text(
          //   'Edit chat identity',
          //   style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          // ),
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

/// The recently-shared-photos strip — up to 4 of this relationship's most
/// recent chat images, newest first, rendered as ONE continuous flush
/// filmstrip rather than separate spaced cards: tiles butt up against each
/// other with no gap, and only the strip's own outer edges are rounded —
/// the first tile rounds its left corners, the last rounds its right
/// corners, and any tile in between (3+ images) is square on every side. A
/// single image rounds on all four corners, since it IS both the first and
/// last tile.
///
/// Tapping a tile opens the full-screen image viewer for THAT image via
/// [onTapImage] (its index within [images]) — never the media gallery
/// screen. "See all" (rendered by the caller, not here) is the only way to
/// reach the gallery; a tile's job is to show that one photo.
class _RecentPhotosRow extends StatelessWidget {
  const _RecentPhotosRow({required this.images, required this.onTapImage});

  final List<Message> images;
  final ValueChanged<int> onTapImage;

  static const double _cornerRadius = 12;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();

    return Row(
      children: List.generate(images.length, (index) {
        return Expanded(
          child: GestureDetector(
            onTap: () => onTapImage(index),
            child: _PhotoTile(
              message: images[index],
              borderRadius: _borderRadiusFor(
                index: index,
                count: images.length,
              ),
            ),
          ),
        );
      }),
    );
  }

  BorderRadius _borderRadiusFor({required int index, required int count}) {
    final isFirst = index == 0;
    final isLast = index == count - 1;
    return BorderRadius.only(
      topLeft: isFirst ? const Radius.circular(_cornerRadius) : Radius.zero,
      bottomLeft: isFirst ? const Radius.circular(_cornerRadius) : Radius.zero,
      topRight: isLast ? const Radius.circular(_cornerRadius) : Radius.zero,
      bottomRight: isLast ? const Radius.circular(_cornerRadius) : Radius.zero,
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.message, required this.borderRadius});

  final Message message;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final placeholder = Container(color: colorScheme.surfaceContainerHighest);

    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: borderRadius,
        // Same tag ImageViewerScreen's _ZoomableImage Hero-wraps its full
        // image with, so tapping a tile flies the cropped square thumbnail
        // into the full (BoxFit.contain) image instead of cutting to it —
        // matches the chat bubble's own thumbnail -> viewer transition.
        child: Hero(
          tag: message.clientMessageId,
          child: ResolvedMediaUrl(
            signedMediaUrl: message.signedMediaUrl,
            mediaKey: message.mediaKey,
            loading: placeholder,
            error: placeholder,
            builder:
                (context, url) => CachedNetworkImage(
                  imageUrl: url,
                  cacheKey: message.mediaKey,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => placeholder,
                  errorWidget: (context, url, error) => placeholder,
                ),
          ),
        ),
      ),
    );
  }
}

/// "Relationship Center" panel — the couple's Pulse at a glance, plus the
/// two actions that most directly improve it.
///
/// ## What is deliberately NOT here
///
/// The three stat tiles were originally dummy ("7d streak", "Response
/// rate", "Shared goals"). Two of those three can never ship:
///
/// - **Streaks are a permanent product ban.** PULSE.md §6 states verbatim:
///   "Do not implement streak tracking for check-ins. Do not show 'X week
///   streak' anywhere... This is a permanent constraint from
///   ATTUNE_SOUL.md." A missed week must carry no visible penalty.
/// - **Response rate is chat-derived, per-partner attribution.** The
///   chat→Pulse integration spec's Privacy section forbids surfacing
///   chat-derived signal on any client surface, and permanent constraint
///   #2 forbids per-partner behavioural attribution entirely ("Jordan
///   tends to withdraw" must never exist). A response-rate number is
///   exactly that, just numeric.
///
/// So the tiles show Pulse itself instead: the score, its week-over-week
/// movement, and how much data it is standing on. All three are already
/// computed by `compute-pulse`, are relationship-level (never
/// per-partner), and are explicitly designed to be seen by both partners.
///
/// Pulse and Timeline each have their own tab immediately below this card,
/// so this panel deliberately does not duplicate their content — it
/// summarises Pulse in one line and points at the two things that feed it.
class _RelationshipCenterPanel extends ConsumerWidget {
  const _RelationshipCenterPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final pulseAsync = ref.watch(currentPulseScoreProvider);
    final bothSharedQuizAsync = ref.watch(bothPartnersSharedProvider);

    return CardInkWell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Gap(Spacing.md.h),
          _PulseStatRow(pulseAsync: pulseAsync),
          Gap(Spacing.xl.h),
          InfoRowWidget(
            title: 'Weekly check-in',
            subtitle: 'Five quick questions. Takes about 60 seconds.',
            icon: Icons.checklist_rtl_outlined,
            iconColor: colorScheme.info,
            circularRadius: 10,
            backgroundColor: colorScheme.info.withValues(alpha: .2),
            showAvatar: true,
            showTrailingArrow: true,
            showDivider: true,
            onTap: () => context.pushNamed('weeklyCheckin'),
          ),
          // Attachment quiz — the one other real, already-built input to
          // Pulse (PULSE.md §5: both partners completing it adds +20 to
          // Alignment, one partner only adds +5). bothPartnersSharedProvider
          // is mutual by construction (it checks BOTH directions of
          // quiz_shares), so this states a shared fact about the couple
          // rather than reporting on either partner individually.
          bothSharedQuizAsync.when(
            loading: () => _quizRow(context, colorScheme, bothShared: null),
            error: (_, _) => _quizRow(context, colorScheme, bothShared: null),
            data:
                (bothShared) =>
                    _quizRow(context, colorScheme, bothShared: bothShared),
          ),
          InfoRowWidget(
            title: 'Relationship tips',
            subtitle: 'Ideas curated for you two',
            icon: Icons.lightbulb_outline,
            iconColor: colorScheme.warning,
            circularRadius: 10,
            backgroundColor: colorScheme.warning.withValues(alpha: .2),
            showAvatar: true,
            showTrailingArrow: true,
            showDivider: false,
            // Intentionally non-tappable: no backing feature exists yet.
            // Kept as a deliberate placeholder for a spec'd-and-built
            // follow-up rather than wired to a dead route.
          ),
          Gap(Spacing.md.h),
        ],
      ),
    );
  }

  /// The attachment-quiz row. [bothShared] null means "still resolving or
  /// unavailable" — the row still renders with its real title/icon (same
  /// convention ChatSettingsStaticRows uses for a not-yet-loaded
  /// conversation) rather than flashing a spinner into the list.
  Widget _quizRow(
    BuildContext context,
    ColorScheme colorScheme, {
    required bool? bothShared,
  }) {
    return InfoRowWidget(
      title: 'Attachment styles',
      subtitle: switch (bothShared) {
        true => 'You have both shared your results',
        false => 'Take it together to strengthen your Pulse',
        null => 'See how your styles fit together',
      },
      icon: Icons.favorite_outline,
      iconColor: colorScheme.primary,
      circularRadius: 10,
      backgroundColor: colorScheme.primary.withValues(alpha: .2),
      showAvatar: true,
      showTrailingArrow: true,
      showDivider: true,
      onTap: () => context.pushNamed('quizEntry'),
    );
  }
}

/// The three Pulse stat tiles. Renders real values once
/// [currentPulseScoreProvider] resolves; an em-dash placeholder before
/// then, and for a couple with no Pulse score computed yet (a brand-new
/// relationship, which is a normal state rather than an error).
class _PulseStatRow extends StatelessWidget {
  const _PulseStatRow({required this.pulseAsync});

  final AsyncValue<PulseScore?> pulseAsync;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pulse = pulseAsync.valueOrNull;

    final overallDelta = pulse?.getDeltaForDimension('overall');

    Widget divider() => Container(
      width: .3,
      height: 50.h,
      color: colorScheme.onSurface.withValues(alpha: .5),
    );

    return Row(
      children: [
        Expanded(
          child: _StatTile(
            value: pulse == null ? '—' : '${pulse.overallScore}',
            label: 'Pulse',
          ),
        ),
        divider(),
        Expanded(
          child: _StatTile(
            // No previous week to compare against yet is a real, common
            // state (first computed score) — distinct from "no movement",
            // so it shows the placeholder rather than a misleading "0".
            value: overallDelta == null ? '—' : _signed(overallDelta),
            label: 'This week',
            valueColor: switch (overallDelta) {
              null => null,
              > 0 => colorScheme.success,
              < 0 => colorScheme.error,
              _ => null,
            },
          ),
        ),
        divider(),
        Expanded(
          child: _StatTile(
            value: pulse == null ? '—' : _confidenceLabel(pulse.dataConfidence),
            label: 'Confidence',
          ),
        ),
      ],
    );
  }

  static String _signed(int delta) => delta > 0 ? '+$delta' : '$delta';

  /// PULSE.md §7's four levels, title-cased for a compact tile. 'none' is
  /// rendered as "Early" rather than "None" — the spec's own copy for that
  /// state is encouraging ("Not enough data yet — keep using Attune"), and
  /// a bare "None" reads as a failure the couple caused.
  static String _confidenceLabel(String confidence) => switch (confidence) {
    'high' => 'High',
    'medium' => 'Medium',
    'low' => 'Low',
    _ => 'Early',
  };
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label, this.valueColor});

  final String value;
  final String label;

  /// Tints the value only — used by the week-over-week delta tile to show
  /// direction. Null keeps the default text colour, which is what every
  /// non-directional tile wants.
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      // Centered rather than left-aligned: each tile sits in an Expanded
      // slot with a divider at the boundary between slots, so a
      // left-aligned tile's text hugs one side and the divider ends up
      // nowhere near the visual midpoint between two stats. Centering the
      // text is what makes the divider actually read as splitting the two
      // neighboring stats down the middle.
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
