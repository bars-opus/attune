import 'dart:async';

import 'package:attune/app/theme/chat_color_scheme.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/make_room.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/chat/presentation/widgets/chat_date_chip.dart';
import 'package:attune/core/ui/motion/settle_in.dart';
import 'package:attune/core/ui/motion/shimmer.dart';
import 'package:attune/core/ui/presence/breathing_dots.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/state/typing_controller.dart';
import 'package:attune/features/chat/presentation/widgets/attune_chat_wallpaper.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:attune/features/chat/presentation/widgets/chat_media_group.dart';
import 'package:attune/features/conflict_translator/data/models/translator_request.dart';
import 'package:attune/features/conflict_translator/presentation/providers/translator_providers.dart'
    as translator_providers;
import 'package:attune/features/conflict_translator/presentation/screens/translator_sheet.dart';
import 'package:attune/features/games/presentation/widgets/chat_games_sheet.dart';
import 'package:attune/features/settings/data/chat_feel_preference.dart';
import 'package:attune/features/settings/data/sound_preference.dart';
import 'package:attune/core/services/media/image_picker_service.dart';
import 'package:attune/core/services/media/voice_recorder_service.dart';
import 'package:attune/core/ui/motion/glow_pulse.dart';
import 'package:attune/core/widgets/profile_avatar.dart';
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:video_compress/video_compress.dart';
import 'package:attune/features/chat/presentation/providers/partner_presence_provider.dart';
import 'package:attune/features/location/presentation/widgets/share_place_sheet.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversation,
    this.initialJumpToMessageId,
  });

  final Conversation conversation;

  /// Set when arriving from a screen that points at one specific message
  /// (e.g. Starred messages) — scrolled to and flashed once the message
  /// list has loaded, paging further back via loadMoreMessages if the
  /// message isn't in the initially-loaded page. Null means no jump, the
  /// normal "open at the latest message" behavior.
  final String? initialJumpToMessageId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _composerFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePickerService();
  final DateTime _messageListCutoff = DateTime.now();
  // Once-per-message animation ledger: ListView.builder recycles item State
  // when a bubble scrolls out of cacheExtent, so a time-based `isNew` alone
  // would replay SettleIn/Shimmer every time a new message scrolls back into
  // view. IDs recorded here animate exactly once per screen lifetime.
  final Set<String> _animatedMessageIds = <String>{};
  bool _headerExpanded = false;
  bool _headerOverlayMounted = false;
  Timer? _headerOverlayRemovalTimer;
  bool _isForeground = true;

  /// Reply target set by swiping a message — mirrors
  /// DebateRoomScreen._replyToPostId/_replyToQuotedText exactly. Null means
  /// no reply is pending; the quoted-preview strip above the composer only
  /// renders when this is non-null.
  String? _replyToMessageId;
  String? _replyToQuotedText;

  /// Maps every loaded message id to its currently rendered row. Media-group
  /// members may share the representative row's key. Used by _jumpToMessage
  /// to scroll a currently-built message into view.
  final Map<String, GlobalKey> _messageKeys = {};

  /// The message currently flashed as a jump target, and a timer to clear
  /// the flash — mirrors DebateRoomScreen._highlightedPostId/_highlightTimer.
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  /// True once the initial jump (widget.initialJumpToMessageId) has been
  /// attempted, so it fires exactly once per screen lifetime rather than
  /// re-triggering on every rebuild while state.messages is still loading.
  bool _didAttemptInitialJump = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onDraftChanged);
    _composerFocusNode.addListener(_onComposerFocusChanged);
    Future.microtask(_restoreDraft);
    // Mark the view active once the first frame has rendered so read receipts
    // are only sent when the conversation is visible, foregrounded, and the
    // message list has drawn (Spec 6.4).
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncViewActive());
  }

  @override
  void deactivate() {
    // The controller outlives this screen by controllerKeepAlive (5
    // minutes), and _isViewActive was never cleared when the screen went
    // away -- so it stayed TRUE for a chat nobody was looking at. Every
    // realtime event in that window then ran markAsReadDebounced(),
    // marking messages read that the user never saw: the unread badge
    // cleared itself on the conversation list, and the sender's receipt
    // jumped past delivered straight to read.
    //
    // deactivate() rather than dispose(): ref is still usable here, and
    // this fires on both a pop and a push of another route over this one.
    ref
        .read(chatControllerProvider(widget.conversation).notifier)
        .setViewActive(false);
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onDraftChanged);
    _composerFocusNode.removeListener(_onComposerFocusChanged);
    _controller.dispose();
    _composerFocusNode.dispose();
    _scrollController.dispose();
    _highlightTimer?.cancel();
    _headerOverlayRemovalTimer?.cancel();
    super.dispose();
  }

  void _onComposerFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    _syncViewActive();
  }

  /// Reports current view visibility to the controller. The conversation is
  /// "active" for read purposes only while this route is the top of the
  /// navigator (ModalRoute.isCurrent) and the app is foregrounded.
  void _syncViewActive() {
    if (!mounted) return;
    final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    ref
        .read(chatControllerProvider(widget.conversation).notifier)
        .setViewActive(_isForeground && isCurrentRoute);
  }

  void _onDraftChanged() {
    unawaited(_persistDraft());
    ref
        .read(
          typingControllerProvider(widget.conversation.relationshipId).notifier,
        )
        .onComposingChanged(_controller.text.trim().isNotEmpty);
  }

  Future<void> _restoreDraft() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final draft = await ref
        .read(chatCacheServiceProvider)
        .readDraft(user.id, widget.conversation.relationshipId);
    if (!mounted || draft.isEmpty) return;
    _controller.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
  }

  Future<void> _persistDraft() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    await ref
        .read(chatCacheServiceProvider)
        .writeDraft(
          user.id,
          widget.conversation.relationshipId,
          _controller.text,
        );
  }

  Future<void> _clearDraft() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    await ref
        .read(chatCacheServiceProvider)
        .clearDraft(user.id, widget.conversation.relationshipId);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ref.read(hapticsProvider).light(); // instant tactile confirm (Spec §3.1)
    if (ref.read(messageSoundsEnabledProvider)) {
      ref.read(soundServiceProvider).play(ChatSound.send);
    }
    ref
        .read(
          typingControllerProvider(widget.conversation.relationshipId).notifier,
        )
        .onSent();
    await _sendDraftText(text);
  }

  void _setReplyTarget(String messageId, String contentPreview) {
    setState(() {
      _replyToMessageId = messageId;
      _replyToQuotedText =
          contentPreview.length > 60
              ? '${contentPreview.substring(0, 60)}...'
              : contentPreview;
    });
    _composerFocusNode.requestFocus();
  }

  void _clearReplyTarget() {
    setState(() {
      _replyToMessageId = null;
      _replyToQuotedText = null;
    });
  }

  /// Scrolls to and flashes [messageId] if it's currently built (mounted
  /// GlobalKey). Returns whether it found something to scroll to — the
  /// caller falls back to an index-based estimate when this returns false.
  /// Mirrors DebateRoomScreen._tryEnsureVisible exactly.
  bool _tryEnsureMessageVisible(String messageId) {
    final targetContext = _messageKeys[messageId]?.currentContext;
    if (targetContext == null) return false;

    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.5,
    );

    _highlightTimer?.cancel();
    setState(() => _highlightedMessageId = messageId);
    _highlightTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _highlightedMessageId = null);
    });
    return true;
  }

  /// Jump to a reply's parent message — mirrors
  /// DebateRoomScreen._jumpToPost exactly, adapted for this screen's
  /// reversed ListView.builder (state.messages is already newest-first,
  /// matching the reversed list's visual top-to-bottom order, so the same
  /// index × averageExtent estimate applies with no sign flip needed).
  Future<void> _jumpToMessage(
    String messageId,
    List<Message> currentMessages,
  ) async {
    if (_tryEnsureMessageVisible(messageId)) return;

    final index = currentMessages.indexWhere((m) => m.id == messageId);
    if (index == -1 || !_scrollController.hasClients) return;

    final position = _scrollController.position;
    final averageExtent =
        position.viewportDimension /
        (_messageKeys.isEmpty ? 8 : _messageKeys.length);
    final estimatedOffset = index * averageExtent;

    await _scrollController.animateTo(
      estimatedOffset.clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    _tryEnsureMessageVisible(messageId);
  }

  /// Like _jumpToMessage, but for a target that may be further back than
  /// the initially-loaded page — used for widget.initialJumpToMessageId
  /// (e.g. arriving from Starred messages), where the target could be
  /// arbitrarily old. Pages backward via loadMoreMessages until the
  /// message is found or the conversation is exhausted (state.hasMore ==
  /// false), then delegates to the normal same-page jump. A capped
  /// iteration count guards against loadMoreMessages returning pages that
  /// never actually reduce hasMore to false (defensive; getMessages'
  /// contract already sets hasMore false on receiving a partial page).
  Future<void> _jumpToMessageAcrossPages(String messageId) async {
    final notifier = ref.read(
      chatControllerProvider(widget.conversation).notifier,
    );

    for (var attempt = 0; attempt < 50; attempt++) {
      final state = ref.read(chatControllerProvider(widget.conversation));
      if (state.messages.any((m) => m.id == messageId)) break;
      if (!state.hasMore || state.isLoadingMore) {
        if (!state.hasMore) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        continue;
      }
      await notifier.loadMoreMessages();
      if (!mounted) return;
    }

    if (!mounted) return;
    final currentMessages =
        ref.read(chatControllerProvider(widget.conversation)).messages;
    await _jumpToMessage(messageId, currentMessages);
  }

  Future<void> _sendDraftText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    await ref
        .read(chatControllerProvider(widget.conversation).notifier)
        .sendMessage(
          text,
          replyToMessageId: _replyToMessageId,
          quotedText: _replyToQuotedText,
        );
    _controller.clear();
    await _clearDraft();
    _clearReplyTarget();
    _scrollToLatest();
  }

  Future<void> _attachImage() async {
    final picked = await _imagePicker.pickImage(
      fromCamera: false,
      crop: true,
      lockAspectRatio: false,
    );
    if (picked == null || !mounted) return;

    // Full-screen preview + caption, shown unconditionally after every
    // pick/crop — matches WhatsApp/iMessage's pick-then-caption flow. Null
    // means the user backed out (closed the screen) rather than sending.
    final caption = await context.pushNamed<String>(
      'imageCaption',
      extra: picked.path,
    );
    if (caption == null || !mounted) return;

    await _clearDraft();
    // sendImageMessage has no replyToMessageId/quotedText params (image
    // replies are out of scope), so any pending reply target would silently
    // survive this send and get attached to the NEXT text message instead —
    // clear it here so the "Replying to..." strip never outlives the reply
    // it was showing.
    _clearReplyTarget();
    // sendImageMessage takes the RAW picked path and shows the optimistic
    // bubble before running ChatImagePreparer's compression itself (see its
    // own doc comment) — compression is real, non-instant work, and used to
    // run here, before the bubble ever appeared, which is what made sending
    // an image feel like nothing happened for a moment after tapping send.
    await ref
        .read(chatControllerProvider(widget.conversation).notifier)
        .sendImageMessage(localPath: picked.path, caption: caption);
    _scrollToLatest();
  }

  Future<void> _attachVideo() async {
    final picked = await _imagePicker.pickVideo(fromCamera: false);
    if (picked == null || !mounted) return;

    MediaInfo? sourceInfo;
    try {
      sourceInfo = await VideoCompress.getMediaInfo(picked.path);
    } catch (_) {
      sourceInfo = null;
    }
    if (!mounted) return;
    final sourceDurationMs = sourceInfo?.duration?.round();
    if (sourceDurationMs == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That video could not be read. Try a different one.'),
        ),
      );
      return;
    }

    final window = await context.pushNamed<({Duration start, Duration end})>(
      'videoTrim',
      extra: VideoTrimRouteArgs(
        sourcePath: picked.path,
        sourceDuration: Duration(milliseconds: sourceDurationMs),
      ),
    );
    if (window == null || !mounted) return; // user backed out

    _controller.clear();
    await _clearDraft();
    // Mirrors _attachImage's identical reasoning: sendVideoMessageFromTrim
    // has no replyToMessageId/quotedText params (video replies are equally
    // out of scope per the design spec), so clear any pending reply target
    // here.
    _clearReplyTarget();
    // sendVideoMessageFromTrim takes the RAW trimmed selection and shows
    // the optimistic (isPreparing: true) bubble before running
    // ChatVideoPreparer's compression itself — no more blocking
    // VideoPrepareProgressDialog in between; the bubble appears instantly
    // and the compression progress renders inline on it instead, matching
    // _attachImage's identical "show first, prepare in the background"
    // ordering above. Rejection (too large/long/etc.) is handled inside
    // sendVideoMessageFromTrim itself (surfaces via state.error), same as
    // sendImageMessage/_attachImage's existing convention.
    await ref
        .read(chatControllerProvider(widget.conversation).notifier)
        .sendVideoMessageFromTrim(
          localPath: picked.path,
          trimStart: window.start,
          trimEnd: window.end,
        );
    _scrollToLatest();
  }

  Future<void> _attachEphemeralCamera() async {
    // The streak camera, not the ephemeral one: it is the same
    // press-and-hold gesture plus segmentation, a progress ring and a
    // review step. EphemeralCameraScreen stays registered for now rather
    // than being deleted mid-testing.
    await context.pushNamed('streakCamera', extra: widget.conversation);
  }

  // Placeholder — file attach is not built yet. Wired now so the composer's
  // '+' sheet has somewhere to go; swap this for the real flow when it ships.
  void _attachFile() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('File sharing is coming soon.')),
    );
  }

  void _openGames() {
    FocusScope.of(context).unfocus();
    _closeHeaderExpanded();
    unawaited(
      BottomSheetUtils.showDocumentationBottomSheet<void>(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.neutral,

        maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        padding: Spacing.md,
        widget: ChatGamesSheet(
          onSelect: (destination) {
            Navigator.of(context).pop();
            unawaited(_openGameRoute(destination));
          },
        ),
      ),
    );
  }

  void _toggleHeaderExpanded() {
    FocusScope.of(context).unfocus();
    if (_headerExpanded) {
      _closeHeaderExpanded();
      return;
    }
    _headerOverlayRemovalTimer?.cancel();
    setState(() {
      _headerExpanded = true;
      _headerOverlayMounted = true;
    });
  }

  void _closeHeaderExpanded() {
    if (!_headerExpanded && !_headerOverlayMounted) return;
    _headerOverlayRemovalTimer?.cancel();
    setState(() => _headerExpanded = false);
    _headerOverlayRemovalTimer = Timer(const Duration(milliseconds: 260), () {
      if (!mounted || _headerExpanded) return;
      setState(() => _headerOverlayMounted = false);
    });
  }

  /// Opens the sheet for sharing where you are.
  ///
  /// A deliberate act, always: the app has no way to reveal a location on
  /// someone's behalf, so this is the only path by which a precise place
  /// ever reaches the chat.
  Future<void> _sharePlace() async {
    final shared = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (_) => SharePlaceSheet(
            relationshipId: widget.conversation.relationshipId,
          ),
    );

    if (shared == null || !mounted) return;

    final notifier = ref.read(
      chatControllerProvider(widget.conversation).notifier,
    );

    // A photo goes through the ordinary image pipeline, which strips EXIF
    // (chat spec 8.1). That matters more here than anywhere else: a photo
    // taken at the place would otherwise carry its exact coordinates past
    // every coarsening decision this feature makes.
    if (shared is String && shared.isNotEmpty) {
      await notifier.sendImageMessage(localPath: shared);
    }

    // The place message arrives through the normal realtime path; this
    // pulls it in immediately for the sender rather than waiting.
    unawaited(notifier.loadMessages(silent: true));
  }

  Future<void> _openGameRoute(ChatGameDestination destination) async {
    await openGameRoute(
      context,
      destination,
      relationshipId: widget.conversation.relationshipId,
    );
  }

  Future<void> _onVoiceMessageRecorded(VoiceRecording recording) async {
    await ref
        .read(chatControllerProvider(widget.conversation).notifier)
        .sendVoiceMessage(
          localPath: recording.localPath,
          durationMs: recording.durationMs,
          waveform: recording.waveform,
        );
    _scrollToLatest();
  }

  Future<void> _openTranslator() async {
    final message = _controller.text.trim();
    if (message.isEmpty) return;

    final translatorContext = await _getTranslatorContext();
    final notifier = ref.read(
      translator_providers.translatorNotifierProvider.notifier,
    );
    await notifier.translate(
      message: message,
      relationshipId: widget.conversation.relationshipId,
      context: translatorContext,
    );

    if (!mounted) return;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (sheetContext) => TranslatorSheet(
            originalMessage: message,
            onSendOriginal: () {
              Navigator.pop(sheetContext, true);
              _sendDraftText(message);
            },
            onSendRewrite: (rewrite) {
              Navigator.pop(sheetContext, true);
              _sendDraftText(rewrite);
            },
            onEditRewrite: (rewrite) {
              _controller.value = TextEditingValue(
                text: rewrite,
                selection: TextSelection.collapsed(offset: rewrite.length),
              );
              unawaited(_persistDraft());
              Navigator.pop(sheetContext, true);
            },
          ),
    );

    if (result == null && mounted) {
      final state = ref.read(translator_providers.translatorNotifierProvider);
      if (state.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Translator unavailable right now. Your draft is still here.',
            ),
          ),
        );
      }
    }

    ref.read(translator_providers.translatorNotifierProvider.notifier).reset();
  }

  Future<TranslatorContext?> _getTranslatorContext() async {
    final supabase = ref.read(supabaseClientProvider);
    final userId = ref.read(currentUserProvider)?.id;
    if (userId == null) return null;

    try {
      final profile =
          await supabase
              .from('psych_profiles')
              .select('attachment_style, communication_style, conflict_style')
              .eq('user_id', userId)
              .maybeSingle();

      if (profile == null) return null;

      final communicationStyle =
          profile['communication_style'] as Map<String, dynamic>?;
      final attachmentStyle =
          profile['attachment_style'] as Map<String, dynamic>?;
      final conflictStyle = profile['conflict_style'] as Map<String, dynamic>?;

      const conflictKeys = [
        'collaborating',
        'competing',
        'avoiding',
        'accommodating',
        'compromising',
      ];

      final conflictTendencies =
          conflictStyle == null
              ? null
              : <String, int>{
                for (final key in conflictKeys)
                  if (conflictStyle[key] is num)
                    key: (conflictStyle[key] as num).round(),
              };

      return TranslatorContext(
        attachmentStyle: attachmentStyle?['type'] as String?,
        communicationStyle:
            communicationStyle?['primary'] as String? ??
            communicationStyle?['type'] as String?,
        conflictTendencies:
            conflictTendencies?.length == conflictKeys.length
                ? conflictTendencies
                : null,
      );
    } catch (_) {
      return null;
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openPulse() async {
    _syncViewActive();
    await context.pushNamed('pulse');
    _syncViewActive();
  }

  Future<void> _openInsights() async {
    _syncViewActive();
    await context.pushNamed(
      'chatInsights',
      extra: (
        relationshipId: widget.conversation.relationshipId,
        partnerName: widget.conversation.partnerName,
      ),
    );
    _syncViewActive();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider(widget.conversation));
    final notifier = ref.read(
      chatControllerProvider(widget.conversation).notifier,
    );
    final conversation = state.conversation;
    final imageSharingEnabled = ref.watch(chatImageSharingEnabledProvider);
    final videoSharingEnabled = ref.watch(chatVideoSharingEnabledProvider);
    // create_chat_media_upload_intent (see the 20260815130000 migration)
    // requires BOTH chat_video_sharing AND chat_image_sharing to be enabled
    // for a video upload intent to succeed — every video send also uploads
    // its thumbnail through the image intent path. Gating on
    // videoSharingEnabled alone would let a user pick/trim/transcode a clip
    // only to have the send fail after the expensive part is done. Inlined
    // here (rather than a separate derived provider) since it's a single
    // call site and the migration comment is the source of truth to keep in
    // sync with.
    final videoAttachEnabled =
        videoSharingEnabled.valueOrNull == true &&
        imageSharingEnabled.valueOrNull == true;
    final ephemeralVideoEnabled = ref.watch(chatEphemeralVideoEnabledProvider);
    // Same reasoning as videoAttachEnabled above: create_chat_media_upload_intent
    // cannot distinguish an ephemeral video intent from a gallery one (both
    // request media_type = 'video'), so chat_ephemeral_video must be layered
    // ON TOP of the existing chat_video_sharing AND chat_image_sharing gate,
    // not checked independently — see the 20260816130000 migration's header
    // comment, which is the source of truth to keep in sync with.
    final captureVideoEnabled =
        ephemeralVideoEnabled.valueOrNull == true && videoAttachEnabled;
    final voiceMessagesEnabled = ref.watch(chatVoiceMessagesEnabledProvider);
    final translatorEnabled = ref.watch(chatTranslatorEntryEnabledProvider);
    final headerDrawerEnabled = ref.watch(
      chatExpandedHeaderDrawerEnabledProvider,
    );
    final isOnline = ref.watch(chatConnectivityProvider).valueOrNull ?? true;
    final headerSnapshot = ref.watch(
      chatHeaderSnapshotProvider(conversation.relationshipId),
    );

    final initialJumpId = widget.initialJumpToMessageId;
    if (initialJumpId != null &&
        !_didAttemptInitialJump &&
        !state.isLoading &&
        state.messages.isNotEmpty) {
      _didAttemptInitialJump = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_jumpToMessageAcrossPages(initialJumpId)),
      );
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Theme.of(context).colorScheme.neutral,
            appBar: AppBar(
              toolbarHeight: 72,
              backgroundColor: Theme.of(context).colorScheme.neutral,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: false,
              titleSpacing: 0,
              title: InkWell(
                onTap: () => unawaited(_openPulse()),
                child: _ConversationHeaderCard(
                  conversation: conversation,
                  isExpanded: _headerExpanded,
                  expandedEnabled: headerDrawerEnabled.valueOrNull == true,
                  onToggleExpanded: _toggleHeaderExpanded,
                  isOnline: isOnline,
                  lastSyncedAt: state.lastSyncedAt,
                ),
              ),

              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(0.5),
                child: AppDivider(),
              ),
            ),
            body: Stack(
              children: [
                const Positioned.fill(
                  child: AttuneChatWallpaper(child: SizedBox.expand()),
                ),
                // Message list fills the whole body; the composer floats on top
                // (see the Positioned block below) rather than being stacked in
                // flow beneath it, so bubbles keep scrolling visibly behind the
                // composer instead of stopping short above it — matches
                // DebateRoomScreen's floating composer treatment.
                Column(
                  children: [
                    if (state.pinnedMessages.isNotEmpty)
                      _PinnedMessagesBanner(
                        pinnedMessages: state.pinnedMessages,
                        onTap:
                            (message) => unawaited(
                              _jumpToMessage(message.id, state.messages),
                            ),
                      ),
                    _ConversationStateBanner(
                      conversation: conversation,
                      state: state,
                      isOnline: isOnline,
                      errorMessage: state.error,
                      onRetry: () => notifier.loadMessages(),
                    ),
                    Expanded(
                      child: _MessageList(
                        conversation: widget.conversation,
                        state: state,
                        scrollController: _scrollController,
                        firstBuildCutoff: _messageListCutoff,
                        animatedMessageIds: _animatedMessageIds,
                        messageKeys: _messageKeys,
                        highlightedMessageId: _highlightedMessageId,
                        composerFocused: _composerFocusNode.hasFocus,
                        onReply: _setReplyTarget,
                        onJumpToParent: _jumpToMessage,
                      ),
                    ),
                    // No trailing gap: it exposed a band of the scaffold's
                    // own background (colorScheme.neutral) below the
                    // wallpaper. The composer is Positioned over this
                    // column and carries its own SafeArea, so nothing here
                    // needs to reserve room for it, and the list already
                    // pads its bottom by 96 to clear it.
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Consumer(
                          builder: (context, ref, _) {
                            final typing =
                                ref
                                    .watch(
                                      typingControllerProvider(
                                        conversation.relationshipId,
                                      ),
                                    )
                                    .partnerTyping;
                            return AnimatedSize(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment.bottomLeft,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder:
                                    (child, animation) => FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: const Offset(0, 0.18),
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    ),
                                child:
                                    typing
                                        ? const Padding(
                                          key: ValueKey('typing_indicator'),
                                          padding: EdgeInsets.fromLTRB(
                                            16,
                                            4,
                                            16,
                                            6,
                                          ),
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: _TypingIndicatorBubble(),
                                          ),
                                        )
                                        : const SizedBox.shrink(
                                          key: ValueKey(
                                            'typing_indicator_hidden',
                                          ),
                                        ),
                              ),
                            );
                          },
                        ),
                        if (conversation.canSend && _replyToMessageId != null)
                          AnimatedScaleFade(
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeOutBack,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                              child: CardInkWell(
                                padding: const EdgeInsets.only(left: 12),
                                margin: EdgeInsets.zero,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: RichText(
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text: 'Replying to',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall?.copyWith(
                                                  color:
                                                      Theme.of(
                                                        context,
                                                      ).colorScheme.primary,
                                                ),
                                              ),
                                              TextSpan(
                                                text:
                                                    '\n${_replyToQuotedText ?? ''}',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurface
                                                      .withValues(alpha: 0.8),
                                                ),
                                              ),
                                            ],
                                          ),
                                          textAlign: TextAlign.start,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 16),
                                        onPressed: _clearReplyTarget,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (conversation.canSend)
                          ChatTextField(
                            controller: _controller,
                            onSend: () {
                              unawaited(_send());
                            },
                            focusNode: _composerFocusNode,
                            onAttachImage:
                                imageSharingEnabled.valueOrNull == true
                                    ? () {
                                      unawaited(_attachImage());
                                    }
                                    : null,
                            onAttachVideo:
                                videoAttachEnabled
                                    ? () {
                                      unawaited(_attachVideo());
                                    }
                                    : null,
                            onCaptureVideo:
                                captureVideoEnabled
                                    ? () {
                                      unawaited(_attachEphemeralCamera());
                                    }
                                    : null,
                            onOpenTranslator:
                                translatorEnabled.valueOrNull == true
                                    ? () {
                                      unawaited(_openTranslator());
                                    }
                                    : null,
                            onAttachFile: _attachFile,
                            onSharePlace: _sharePlace,
                            onOpenGames: _openGames,
                            showAttachImage:
                                imageSharingEnabled.valueOrNull == true,
                            showAttachVideo: videoAttachEnabled,
                            showCaptureVideo: captureVideoEnabled,
                            showGames: true,
                            showTranslator:
                                translatorEnabled.valueOrNull == true,
                            showVoiceMessage:
                                voiceMessagesEnabled.valueOrNull == true,
                            onVoiceMessageRecorded:
                                voiceMessagesEnabled.valueOrNull == true
                                    ? (recording) {
                                      unawaited(
                                        _onVoiceMessageRecorded(recording),
                                      );
                                    }
                                    : null,
                            enabled: !state.isSending,
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: Text(
                              conversation.readOnlyReason ??
                                  'This conversation is read-only.',
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (headerDrawerEnabled.valueOrNull == true && _headerOverlayMounted)
            Positioned.fill(
              child: _ConversationHeaderOverlay(
                snapshot: headerSnapshot,
                closing: !_headerExpanded,
                onDismiss: _closeHeaderExpanded,
                onOpenPulse: () {
                  _closeHeaderExpanded();
                  unawaited(_openPulse());
                },
                onOpenInsights: () {
                  _closeHeaderExpanded();
                  unawaited(_openInsights());
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ConversationStateBanner extends StatelessWidget {
  const _ConversationStateBanner({
    required this.conversation,
    required this.state,
    required this.isOnline,
    this.errorMessage,
    this.onRetry,
  });

  final Conversation conversation;
  final ChatState state;
  final bool isOnline;
  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final queuedCount =
        state.messages
            .where((message) => message.isMine && message.isQueued)
            .length;

    _ConversationBannerData? data;

    if (errorMessage != null) {
      data = _ConversationBannerData(
        title: 'Could not sync',
        body: errorMessage!,
        icon: Icons.wifi_tethering_error_rounded,
        accent: colorScheme.error,
        surface: colorScheme.errorContainer.withValues(alpha: 0.72),
        foreground: colorScheme.onErrorContainer,
        actionLabel: 'Retry',
        onAction: onRetry,
      );
    } else if (conversation.isArchived) {
      data = _ConversationBannerData(
        title: 'Conversation archived',
        body: conversation.readOnlyReason ?? 'This chat is read-only.',
        icon: Icons.archive_outlined,
        accent: colorScheme.error,
        surface: colorScheme.errorContainer.withValues(alpha: 0.72),
        foreground: colorScheme.onErrorContainer,
      );
    } else if (!isOnline) {
      data = _ConversationBannerData(
        title: 'Offline',
        body:
            queuedCount > 0
                ? '$queuedCount message${queuedCount == 1 ? '' : 's'} queued. They will send when you reconnect.'
                : 'Messages will queue locally until you reconnect.',
        icon: Icons.cloud_off_outlined,
        accent: colorScheme.onSurfaceVariant,
        surface: colorScheme.surfaceContainerHighest.withValues(alpha: 0.86),
        foreground: colorScheme.onSurface,
      );
    } else if (!conversation.canSend && conversation.readOnlyReason != null) {
      data = _ConversationBannerData(
        title: 'Read-only',
        body: conversation.readOnlyReason!,
        icon: Icons.lock_outline,
        accent: colorScheme.onSurfaceVariant,
        surface: colorScheme.surfaceContainerHighest.withValues(alpha: 0.86),
        foreground: colorScheme.onSurface,
      );
    }

    final child =
        data == null
            ? const SizedBox.shrink(key: ValueKey('conversation_banner_empty'))
            : _ConversationAlertCard(
              key: ValueKey('conversation_banner_${data.title}_${data.body}'),
              data: data,
            );

    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder:
            (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.18),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
            ),
        child: child,
      ),
    );
  }
}

class _ConversationBannerData {
  const _ConversationBannerData({
    required this.title,
    required this.body,
    required this.icon,
    required this.accent,
    required this.surface,
    required this.foreground,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final IconData icon;
  final Color accent;
  final Color surface;
  final Color foreground;
  final String? actionLabel;
  final VoidCallback? onAction;
}

class _ConversationAlertCard extends StatelessWidget {
  const _ConversationAlertCard({super.key, required this.data});

  final _ConversationBannerData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // ignore: deprecated_member_use
    final controlSurface = colorScheme.background.withValues(alpha: 0.92);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        decoration: BoxDecoration(
          color: colorScheme.neutral,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(26),
          ),
          boxShadow: const [
            BoxShadow(
              offset: Offset(0, 8),
              blurRadius: 24,
              spreadRadius: -11,
              color: Color(0x40000000),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: data.surface,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: data.accent.withValues(alpha: 0.18)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: controlSurface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: data.accent.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Icon(data.icon, size: 18, color: data.accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        data.title,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: data.foreground,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        data.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: data.foreground.withValues(alpha: 0.72),
                          height: 1.18,
                        ),
                      ),
                    ],
                  ),
                ),
                if (data.actionLabel != null && data.onAction != null) ...[
                  const SizedBox(width: 8),
                  Material(
                    color: controlSurface,
                    borderRadius: BorderRadius.circular(
                      BorderRadiusTokens.full,
                    ),
                    child: InkWell(
                      onTap: data.onAction,
                      borderRadius: BorderRadius.circular(
                        BorderRadiusTokens.full,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        child: Text(
                          data.actionLabel!,
                          style: Theme.of(
                            context,
                          ).textTheme.labelMedium?.copyWith(
                            color: data.accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationHeaderCard extends ConsumerWidget {
  const _ConversationHeaderCard({
    required this.conversation,
    required this.isExpanded,
    required this.expandedEnabled,
    required this.onToggleExpanded,
    required this.isOnline,
    required this.lastSyncedAt,
  });

  final Conversation conversation;
  final bool isExpanded;
  final bool expandedEnabled;
  final VoidCallback onToggleExpanded;
  final bool isOnline;
  final DateTime? lastSyncedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Absent rather than wrong while loading: an unknown presence must not
    // render as "Active", which is the failure the old indicator had.
    final partnerActive =
        ref
            .watch(partnerActiveInChatProvider(conversation.relationshipId))
            .valueOrNull ??
        false;

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final subtitle =
        !isOnline
            ? 'Offline'
            : lastSyncedAt == null
            ? 'Syncing'
            : 'Synced ${_relativeSyncLabel(lastSyncedAt!)}';

    return Hero(
      tag: conversation.name,
      child: Row(
        children: [
          // Breathes a few times when the partner is here, then settles
          // to a static glow — a moment, not a session-long loop.
          GlowPulse(
            // Follows the partner, not the viewer's connectivity, so the
            // avatar stops glowing permanently for everyone.
            active: partnerActive,
            child: ProfileAvatar(
              avatarUrl: conversation.avatarUrl ?? '',
              currentUserId: '',
              size: 40.h,
              enableHero: false,
            ),
          ),
          Gap(Spacing.sm.w),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: conversation.name,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),

                  // "Online" here used to be driven by isOnline -- the
                  // VIEWER's own connectivity -- so it read Online
                  // whenever you had a connection, whatever your partner
                  // was doing. It was decoration, not data.
                  //
                  // Now it reports whether the partner is in THIS
                  // conversation. Deliberately not a general online
                  // status: in a couples app that answers "they are on
                  // their phone and not replying to me", which starts
                  // arguments the app should not help start. Scoped here
                  // it says something kinder and true -- they are with
                  // you now -- and it is the only thing chat_presence
                  // actually measures.
                  partnerActive
                      ? TextSpan(
                        text: '\nActive in this chat',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                        ),
                      )
                      : TextSpan(
                        text: "\n$subtitle",
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                ],
              ),
            ),
          ),
          if (expandedEnabled)
            AppIconButton(
              icon:
                  isExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
              onPressed: onToggleExpanded,
              tooltip: isExpanded ? 'Hide chat details' : 'Show chat details',
            ),

          AppIconButton(
            icon: Icons.more_vert,
            onPressed: onToggleExpanded,
            tooltip: isExpanded ? 'Hide chat details' : 'Show chat details',
          ),
        ],
      ),
    );
  }
}

class _ConversationHeaderExpandedSection extends StatelessWidget {
  const _ConversationHeaderExpandedSection({
    required this.snapshot,
    required this.onOpenPulse,
    required this.onOpenInsights,
  });

  final AsyncValue<ChatHeaderSnapshot> snapshot;
  final VoidCallback onOpenPulse;
  final VoidCallback onOpenInsights;

  @override
  Widget build(BuildContext context) {
    final pulse = snapshot.valueOrNull?.pulse;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _PulseBadge(pulse: pulse),
          ),
          const SizedBox(height: 12),
          snapshot.when(
            data:
                (value) => _HeaderDrawerContent(
                  snapshot: value,
                  onOpenPulse: onOpenPulse,
                  onOpenInsights: onOpenInsights,
                ),
            loading:
                () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
            error:
                (_, __) => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Extra relationship context is unavailable right now.',
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _ConversationHeaderOverlay extends StatelessWidget {
  const _ConversationHeaderOverlay({
    required this.snapshot,
    required this.closing,
    required this.onDismiss,
    required this.onOpenPulse,
    required this.onOpenInsights,
  });

  final AsyncValue<ChatHeaderSnapshot> snapshot;
  final bool closing;
  final VoidCallback onDismiss;
  final VoidCallback onOpenPulse;
  final VoidCallback onOpenInsights;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: onDismiss,
        behavior: HitTestBehavior.opaque,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: closing ? 0 : 1),
          duration:
              reduceMotionOf(context)
                  ? Duration.zero
                  : closing
                  ? const Duration(milliseconds: 260)
                  : const Duration(milliseconds: 460),
          curve: Curves.linear,
          builder: (context, value, child) {
            final backdropProgress = Curves.easeOutCubic.transform(value);
            final motionProgress = Curves.easeOutBack.transform(value);

            return Container(
              color: Colors.black.withValues(alpha: 0.82 * backdropProgress),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Opacity(
                      opacity: backdropProgress.clamp(0.0, 1.0).toDouble(),
                      child: Transform.scale(
                        alignment: Alignment.topCenter,
                        scale: 0.78 + (0.22 * motionProgress),
                        child: Transform.translate(
                          offset: Offset(
                            28 * (1 - motionProgress),
                            -20 * (1 - motionProgress),
                          ),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
          child: GestureDetector(
            onTap: () {},
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 640.w),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(24.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.24),
                      blurRadius: 28,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Chat details',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: onDismiss,
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Close chat details',
                          ),
                        ],
                      ),
                      _ConversationHeaderExpandedSection(
                        snapshot: snapshot,
                        onOpenPulse: onOpenPulse,
                        onOpenInsights: onOpenInsights,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulseBadge extends StatelessWidget {
  const _PulseBadge({required this.pulse});

  final PulseSummary? pulse;

  @override
  Widget build(BuildContext context) {
    final label = pulse == null ? 'No pulse yet' : 'Pulse ${pulse!.score}';
    final delta = pulse?.delta;
    final deltaLabel =
        delta == null
            ? null
            : delta == 0
            ? 'No change'
            : delta > 0
            ? '+$delta'
            : '$delta';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (deltaLabel != null)
            Text(deltaLabel, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _HeaderDrawerContent extends StatelessWidget {
  const _HeaderDrawerContent({
    required this.snapshot,
    required this.onOpenPulse,
    required this.onOpenInsights,
  });

  final ChatHeaderSnapshot snapshot;
  final VoidCallback onOpenPulse;
  final VoidCallback onOpenInsights;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _DrawerCard(
                title: 'Latest insight',
                body:
                    snapshot.latestUnreadInsight?.body ??
                    'No unread private insight is ready right now.',
                icon: Icons.lightbulb_outline,
                actionLabel: 'Open insights',
                onAction: onOpenInsights,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DrawerCard(
                title: 'Next reminder',
                body:
                    snapshot.nextReminder == null
                        ? 'No upcoming relationship reminder is scheduled.'
                        : '${_reminderLabel(snapshot.nextReminder!)} ${_formatReminderTime(snapshot.nextReminder!.scheduledFor)}',
                icon: Icons.schedule_outlined,
                actionLabel: 'Open Pulse',
                onAction: onOpenPulse,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _reminderLabel(ChatReminderSummary reminder) {
    switch (reminder.type) {
      case 'checkin_reminder':
        return 'Check-in reminder';
      default:
        return 'Reminder';
    }
  }

  static String _formatReminderTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return 'on ${_monthNames[value.month - 1]} ${value.day} at $hour:$minute $suffix';
  }
}

class _DrawerCard extends StatelessWidget {
  const _DrawerCard({
    required this.title,
    required this.body,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String body;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(height: 10),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _MessageList extends ConsumerStatefulWidget {
  const _MessageList({
    required this.conversation,
    required this.state,
    required this.scrollController,
    required this.firstBuildCutoff,
    required this.animatedMessageIds,
    required this.messageKeys,
    required this.highlightedMessageId,
    required this.composerFocused,
    required this.onReply,
    required this.onJumpToParent,
  });

  /// The screen's own widget.conversation — NOT state.conversation.
  /// chatControllerProvider is a .family<..., Conversation> keyed by
  /// object identity (Conversation has no == override), and
  /// state.conversation gets replaced with a freshly-fetched instance by
  /// _refreshConversation() almost immediately after the screen opens. Any
  /// lookup keyed on state.conversation after that point resolves to a
  /// second, orphaned controller instance that nothing else watches —
  /// every message action (star/unstar/pin/unpin/edit/delete) silently
  /// wrote to that orphan instead of the one actually being watched and
  /// rendered, until an app restart re-fetched from the DB. Always key
  /// chatControllerProvider off this field, never off state.conversation.
  final Conversation conversation;
  final ChatState state;
  final ScrollController scrollController;
  final DateTime firstBuildCutoff;

  /// Owned by the screen State (survives list-item recycling); see its
  /// declaration for why a time-based cutoff alone is not enough.
  final Set<String> animatedMessageIds;

  /// Owned by the screen State — see `_ChatScreenState._messageKeys` for why
  /// keys are registered fresh on every build rather than only-if-absent.
  final Map<String, GlobalKey> messageKeys;

  /// The message currently flashed as a jump target, or null.
  final String? highlightedMessageId;

  /// True while the chat composer owns focus. The Scaffold body can see a
  /// zero keyboard inset after resize, so focus is the reliable signal for
  /// tightening the list's bottom reserve above the floating composer.
  final bool composerFocused;

  /// Sets the screen's reply target to (messageId, contentPreview).
  final void Function(String messageId, String contentPreview) onReply;

  /// Jumps to and highlights a reply's parent message, given the current
  /// message list for the index-based fallback estimate.
  final Future<void> Function(String messageId, List<Message> currentMessages)
  onJumpToParent;

  @override
  ConsumerState<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends ConsumerState<_MessageList>
    with SingleTickerProviderStateMixin {
  static const _timestampReturnDuration = Duration(milliseconds: 220);
  static const _messageListBottomReserve = 120.0;
  static const _messageListKeyboardBottomReserve = 64.0;

  final ValueNotifier<double> _timestampRevealOffset = ValueNotifier(0);
  final Map<String, GlobalKey> _rowKeys = {};
  late final AnimationController _timestampReturnController;
  Animation<double>? _timestampReturnAnimation;

  /// The day currently at the top of the viewport, shown in the pinned
  /// chip. Null before the first scroll, when the inline separators are
  /// enough on their own.
  String? _pinnedDateLabel;

  /// The pinned chip floats OVER the messages, so it shows while the list
  /// is moving and fades out once it settles — leaving it up permanently
  /// would cover a bubble the reader is trying to reach.
  bool _pinnedDateVisible = false;

  /// Time-based rather than driven by a scroll-end notification: a fling
  /// that settles on its own does not reliably deliver one, and the chip
  /// would stay up forever.
  Timer? _pinnedDateTimer;

  static const _pinnedDateLinger = Duration(milliseconds: 900);

  /// Records the topmost visible day and keeps the chip up while the list
  /// is moving.
  void _updatePinnedDate(String? label) {
    _pinnedDateTimer?.cancel();
    _pinnedDateTimer = Timer(_pinnedDateLinger, () {
      if (!mounted) return;
      setState(() => _pinnedDateVisible = false);
    });

    if (_pinnedDateLabel == label && _pinnedDateVisible) return;
    setState(() {
      _pinnedDateLabel = label;
      _pinnedDateVisible = true;
    });
  }

  @override
  void initState() {
    super.initState();
    _timestampReturnController = AnimationController(
      vsync: this,
      duration: _timestampReturnDuration,
    );
  }

  @override
  void dispose() {
    _timestampReturnAnimation?.removeListener(_onTimestampReturnTick);
    _timestampReturnController.dispose();
    _timestampRevealOffset.dispose();
    // A Timer outliving this State fires setState on an unmounted widget.
    _pinnedDateTimer?.cancel();
    super.dispose();
  }

  /// The day of the topmost message currently on screen.
  ///
  /// Walks the built rows and takes the first whose painted box crosses
  /// the top of the viewport. Only built rows are considered, which is
  /// exactly right: an unbuilt row is off-screen by definition.
  String? _topmostVisibleDateLabel(List<Message> messages) {
    var best = double.infinity;
    DateTime? topDate;

    for (final message in messages) {
      final key = _rowKeys[message.id];
      final context = key?.currentContext;
      if (context == null) continue;

      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;

      final top = box.localToGlobal(Offset.zero).dy;
      // The topmost row still visible: smallest top that has not scrolled
      // entirely past the viewport's upper edge.
      final bottom = top + box.size.height;
      if (bottom <= 0) continue;
      if (top < best) {
        best = top;
        topDate = message.createdAt;
      }
    }

    return topDate == null ? null : chatDateLabel(topDate);
  }

  void _setTimestampRevealOffset(double offset) {
    if (offset <= 0) {
      _closeTimestampReveal();
      return;
    }
    _timestampReturnController.stop();
    if (_timestampRevealOffset.value == offset) return;
    _timestampRevealOffset.value = offset;
  }

  void _closeTimestampReveal() {
    if (_timestampRevealOffset.value == 0) return;
    _timestampReturnAnimation?.removeListener(_onTimestampReturnTick);
    _timestampReturnAnimation = Tween<double>(
      begin: _timestampRevealOffset.value,
      end: 0,
    ).animate(
      CurvedAnimation(
        parent: _timestampReturnController,
        curve: Curves.easeOutCubic,
      ),
    )..addListener(_onTimestampReturnTick);
    _timestampReturnController.forward(from: 0);
  }

  void _onTimestampReturnTick() {
    if (!mounted) return;
    final value = _timestampReturnAnimation!.value;
    _timestampRevealOffset.value = value.abs() < 0.1 ? 0 : value;
  }

  @override
  Widget build(BuildContext context) {
    final conversation = widget.conversation;
    final state = widget.state;
    final scrollController = widget.scrollController;
    final firstBuildCutoff = widget.firstBuildCutoff;
    final animatedMessageIds = widget.animatedMessageIds;
    final messageKeys = widget.messageKeys;
    final highlightedMessageId = widget.highlightedMessageId;
    final composerFocused = widget.composerFocused;
    final onReply = widget.onReply;
    final onJumpToParent = widget.onJumpToParent;

    // Chat feel preference (Spec §1.1 tone floor, §3.7): expressive turns the
    // shimmer sweep and reconnect cascade up slightly; calm (default) keeps
    // both a whisper-subtle. Content-blind — only the enum is read here.
    final expressive =
        ref.watch(chatExpressivenessProvider) == ChatExpressiveness.expressive;

    if (state.isLoading && state.messages.isEmpty) {
      // Keep the wallpaper visible while the first page (and any cached video
      // posters) is restored. The real empty-conversation prompt is rendered
      // below only after loading completes, so it cannot flash during startup.
      return const SizedBox.expand(
        key: ValueKey('chat_initial_loading_wallpaper'),
      );
    }

    if (state.conversation.isArchived) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            state.conversation.readOnlyReason ??
                'This conversation is no longer available.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (state.messages.isEmpty) {
      return const Center(
        child: Text(
          'No messages yet. Start the conversation when you are ready.',
        ),
      );
    }

    // Prune keys for messages no longer in state.messages (scrolled-out
    // history that got dropped, or a pagination/reload replacing the list)
    // — without this, messageKeys only ever grows across the screen's
    // lifetime, leaking GlobalKeys and corrupting the jump-fallback's
    // "messages currently on screen" estimate in _jumpToMessage, which
    // divides the viewport by messageKeys.length.
    final currentIds = state.messages.map((m) => m.id).toSet();
    messageKeys.removeWhere((id, _) => !currentIds.contains(id));
    _rowKeys.removeWhere((id, _) => !currentIds.contains(id));
    final mediaRuns = ChatMediaRunLayout.fromMessages(state.messages);
    final pinnedLabel = _pinnedDateLabel;
    final keyboardIsOpen =
        composerFocused || MediaQuery.of(context).viewInsets.bottom > 0;

    return Stack(
      children: [
        Listener(
          onPointerUp: (_) => _closeTimestampReveal(),
          onPointerCancel: (_) => _closeTimestampReveal(),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.pixels >=
                  notification.metrics.maxScrollExtent - 200) {
                ref
                    .read(chatControllerProvider(conversation).notifier)
                    .loadMoreMessages();
              }
              if (notification.metrics.pixels <= 120) {
                ref
                    .read(chatControllerProvider(conversation).notifier)
                    .markAsReadDebounced();
              }
              // Measured from the row keys rather than an index estimate: rows
              // vary in height (a one-line text against a media group), so a
              // pixels/rowHeight guess names the wrong day on exactly the
              // conversations where the chip matters most.
              if (notification is ScrollUpdateNotification) {
                _updatePinnedDate(_topmostVisibleDateLabel(state.messages));
              }
              return false;
            },
            child: Scrollbar(
              controller: scrollController,
              child: ListView.builder(
                controller: scrollController,
                reverse: true,
                // Reserves room so the newest message doesn't sit behind the
                // floating composer, now Positioned on top of this list rather than
                // stacked in flow beneath it. Generous estimate covering the tallest
                // composer state (multi-line text growing the field to maxLines:5)
                // plus safe-area/keyboard-adjacent breathing room.
                // No horizontal inset on the LIST: the date separator's
                // rule has to reach both screen edges, and a list-level
                // padding clips it however wide the row asks to be. The
                // 8px moves onto the message rows themselves, which are
                // the only children that wanted it.
                // The unfocused reserve includes the floating composer and
                // the home-indicator SafeArea. When the keyboard is open,
                // that SafeArea collapses, so a tighter reserve keeps the
                // newest bubble/footer close to the focused composer.
                padding: EdgeInsets.fromLTRB(
                  0,
                  10,
                  0,
                  keyboardIsOpen
                      ? _messageListKeyboardBottomReserve
                      : _messageListBottomReserve,
                ),
                itemCount:
                    state.messages.length + (state.isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == state.messages.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (mediaRuns.hiddenIndices.contains(index)) {
                    return const SizedBox.shrink();
                  }

                  final message = state.messages[index];
                  final mediaGroup = mediaRuns.runs[index] ?? const <Message>[];
                  // Keep the rendered row stable while timestamp drag updates
                  // rebuild the visible list. Replacing this key on every pointer
                  // delta disposes the active GestureDetector mid-gesture, making
                  // the reveal stop after its first movement.
                  final messageKey = _rowKeys.putIfAbsent(
                    message.id,
                    GlobalKey.new,
                  );
                  messageKeys[message.id] = messageKey;
                  for (final groupedMessage in mediaGroup) {
                    messageKeys[groupedMessage.id] = messageKey;
                  }
                  // A bubble is "first of its day" if its local date differs from the
                  // next-older message's local date (list is newest-first). Only
                  // genuinely-new first-of-day messages shimmer — cached history on
                  // open does not, since `isNew` reuses the same play-once cutoff as
                  // SettleIn below. Content-blind: only dates are compared.
                  final older =
                      index + 1 < state.messages.length
                          ? state.messages[index + 1]
                          : null;
                  bool sameLocalDay(DateTime a, DateTime b) =>
                      a.year == b.year && a.month == b.month && a.day == b.day;
                  final isFirstOfDay =
                      older == null ||
                      !sameLocalDay(message.createdAt, older.createdAt);
                  // Consecutive messages from the same sender sit close together
                  // (grouped); the normal, larger gap only appears right before the
                  // sender switches — i.e. above the first bubble of a new run,
                  // exactly like WhatsApp/iMessage grouping. A day boundary always
                  // forces the larger gap too (the date separator needs the
                  // breathing room regardless of who sent either message).
                  final isGrouped =
                      older != null &&
                      older.isMine == message.isMine &&
                      !isFirstOfDay;
                  final newer = index > 0 ? state.messages[index - 1] : null;
                  final isLastOfDay =
                      newer == null ||
                      !sameLocalDay(message.createdAt, newer.createdAt);
                  final isGroupedWithPrevious =
                      newer != null &&
                      newer.isMine == message.isMine &&
                      !isLastOfDay;
                  final isNew = message.createdAt.isAfter(firstBuildCutoff);
                  // Play-once ledger: animate only the first time this message is ever
                  // built on this screen. Without it, list recycling replays entry
                  // animations whenever a new message scrolls back into view.
                  final shouldAnimate =
                      isNew &&
                      !animatedMessageIds.contains(message.clientMessageId);
                  if (shouldAnimate) {
                    animatedMessageIds.add(message.clientMessageId);
                  }

                  // A reply's parent is only known to be deleted/mine if it is
                  // actually in the currently-loaded window; an unloaded parent
                  // stays deleted=false, isMine=null (MessageBubble documents both
                  // assumptions — null means "don't know," not "not mine").
                  var parentDeleted = false;
                  bool? parentIsMine;
                  if (message.replyToMessageId != null) {
                    for (final candidate in state.messages) {
                      if (candidate.id == message.replyToMessageId) {
                        parentDeleted = candidate.isDeleted;
                        parentIsMine = candidate.isMine;
                        break;
                      }
                    }
                  }

                  Widget bubble = ValueListenableBuilder<double>(
                    valueListenable: _timestampRevealOffset,
                    builder:
                        (context, timestampRevealOffset, _) => MessageBubble(
                          message: message,
                          mediaGroup: mediaGroup,
                          conversation: conversation,
                          showStatus: index == 0 && message.isMine,
                          showLatestTimestamp: index == 0,
                          showTimestamp: true,
                          timestampRevealOffset: timestampRevealOffset,
                          onTimestampRevealChanged: _setTimestampRevealOffset,
                          parentIsMine: parentIsMine,
                          isGrouped: isGrouped,
                          isGroupedWithPrevious: isGroupedWithPrevious,
                          onImageTap: (tapped) async {
                            // state.messages is newest-first (ListView's reverse: true);
                            // ImageViewerScreen wants chronological (oldest-to-newest)
                            // order to swipe forward through a photo history the same
                            // direction a user reads the conversation, so reverse the
                            // filtered subset here.
                            final images =
                                state.messages
                                    .where((m) => m.hasImage)
                                    .toList()
                                    .reversed
                                    .toList();
                            final index = images.indexWhere(
                              (m) =>
                                  m.clientMessageId == tapped.clientMessageId,
                            );
                            if (index == -1) return;
                            // "Go to message" pops the viewer with that image's message
                            // id; jump to and flash it in THIS chat screen (already
                            // open — no need to push a second one).
                            final jumpToId = await context.pushNamed<String>(
                              'imageViewer',
                              extra: ImageViewerRouteArgs(
                                images: images,
                                initialIndex: index,
                              ),
                            );
                            if (jumpToId != null) {
                              await onJumpToParent(jumpToId, state.messages);
                            }
                          },
                          onVideoTap: (tapped) async {
                            // Mirrors onImageTap exactly. isViewOnce excluded — an
                            // ephemeral video has its own separate
                            // EphemeralVideoViewerScreen flow (tap-to-view-once,
                            // markVideoViewed, expiry) and must never appear in this
                            // regular, replayable video gallery.
                            final videos =
                                state.messages
                                    .where((m) => m.hasVideo && !m.isViewOnce)
                                    .toList()
                                    .reversed
                                    .toList();
                            final index = videos.indexWhere(
                              (m) =>
                                  m.clientMessageId == tapped.clientMessageId,
                            );
                            if (index == -1) return;
                            final jumpToId = await context.pushNamed<String>(
                              'videoViewer',
                              extra: VideoViewerRouteArgs(
                                videos: videos,
                                initialIndex: index,
                              ),
                            );
                            if (jumpToId != null) {
                              await onJumpToParent(jumpToId, state.messages);
                            }
                          },
                          // The viewer reports what the server left after
                          // spending a view; applying it is what stops a
                          // streak reopening past its budget.
                          onGameTap: (gameType) {
                            // Reuses the sheet's type -> destination map,
                            // so a card and the picker open a game exactly
                            // the same way. Unknown types (a game added
                            // server-side before the app knows it) do
                            // nothing rather than routing nowhere.
                            final destination = chatGameDestinationForType(
                              gameType,
                            );
                            if (destination == null) return;
                            unawaited(
                              openGameRoute(
                                context,
                                destination,
                                relationshipId:
                                    widget.conversation.relationshipId,
                              ),
                            );
                          },
                          onStreakViewSpent: (messageId, viewsRemaining) {
                            ref
                                .read(
                                  chatControllerProvider(conversation).notifier,
                                )
                                .applyStreakViewSpent(
                                  messageId,
                                  viewsRemaining,
                                );
                          },
                          onRetry:
                              message.isFailed
                                  ? () => ref
                                      .read(
                                        chatControllerProvider(
                                          conversation,
                                        ).notifier,
                                      )
                                      .retryMessage(message)
                                  : null,
                          onRemove:
                              message.isFailed
                                  ? () => ref
                                      .read(
                                        chatControllerProvider(
                                          conversation,
                                        ).notifier,
                                      )
                                      .removeFailedMessage(message)
                                  : null,
                          onReply:
                              state.conversation.canSend &&
                                      !message.id.startsWith('_local_')
                                  ? () => onReply(message.id, message.content)
                                  : null,
                          onJumpToParent:
                              message.replyToMessageId == null
                                  ? null
                                  : () => onJumpToParent(
                                    message.replyToMessageId!,
                                    state.messages,
                                  ),
                          isHighlighted: highlightedMessageId == message.id,
                          // Actions are only offered on server-backed messages in an
                          // active, sendable conversation: a local optimistic row has no
                          // server id to delete/edit/star/pin, and a read-only
                          // conversation (e.g. an ended relationship viewed via Previous
                          // Relationships) must not offer mutating actions the RPCs will
                          // now correctly reject server-side — this client gate is a
                          // UX correction, not the security boundary (the RPCs are
                          // authoritative; see fix round 1's migration change).
                          currentUserId:
                              state.conversation.canSend &&
                                      !message.id.startsWith('_local_')
                                  ? ref.read(currentUserProvider)?.id
                                  : null,
                          isStarred: state.starredMessageIds.contains(
                            message.id,
                          ),
                          isPinned: state.pinnedMessages.any(
                            (p) => p.id == message.id,
                          ),
                          parentDeleted: parentDeleted,
                          onCopy: () {
                            Clipboard.setData(
                              ClipboardData(text: message.content),
                            );
                            context.showSuccessSnackbar('Copied to clipboard');
                          },
                          // Star/unstar/unpin are all fire-and-forget from the menu, but
                          // each awaits a network call that can throw — swallowing the
                          // failure silently would leave an unhandled async error, so each
                          // reports it the same way onPin does.
                          onStar: () async {
                            try {
                              await ref
                                  .read(
                                    chatControllerProvider(
                                      conversation,
                                    ).notifier,
                                  )
                                  .starMessage(message.id);
                            } catch (e, st) {
                              debugPrint('starMessage failed: $e\n$st');
                              if (context.mounted) {
                                context.showErrorSnackbar(
                                  "Couldn't star — try again.",
                                );
                              }
                            }
                          },
                          onUnstar: () async {
                            try {
                              await ref
                                  .read(
                                    chatControllerProvider(
                                      conversation,
                                    ).notifier,
                                  )
                                  .unstarMessage(message.id);
                            } catch (e, st) {
                              debugPrint('unstarMessage failed: $e\n$st');
                              if (context.mounted) {
                                context.showErrorSnackbar(
                                  "Couldn't unstar — try again.",
                                );
                              }
                            }
                          },
                          onPin: () async {
                            try {
                              await ref
                                  .read(
                                    chatControllerProvider(
                                      conversation,
                                    ).notifier,
                                  )
                                  .pinMessage(message);
                            } catch (e, st) {
                              debugPrint('pinMessage failed: $e\n$st');
                              if (context.mounted) {
                                context.showErrorSnackbar(
                                  "Couldn't pin — you may already have 3 pinned messages.",
                                );
                              }
                            }
                          },
                          onUnpin: () async {
                            try {
                              await ref
                                  .read(
                                    chatControllerProvider(
                                      conversation,
                                    ).notifier,
                                  )
                                  .unpinMessage(message);
                            } catch (e, st) {
                              debugPrint('unpinMessage failed: $e\n$st');
                              if (context.mounted) {
                                context.showErrorSnackbar(
                                  "Couldn't unpin — try again.",
                                );
                              }
                            }
                          },
                          onReact: (emoji) async {
                            try {
                              await ref
                                  .read(
                                    chatControllerProvider(
                                      conversation,
                                    ).notifier,
                                  )
                                  .reactToMessage(message, emoji);
                            } catch (e, st) {
                              debugPrint('reactToMessage failed: $e\n$st');
                              if (context.mounted) {
                                context.showErrorSnackbar(
                                  "Couldn't react — try again.",
                                );
                              }
                            }
                          },
                          onRemoveReaction: () async {
                            try {
                              await ref
                                  .read(
                                    chatControllerProvider(
                                      conversation,
                                    ).notifier,
                                  )
                                  .removeReactionFrom(message);
                            } catch (e, st) {
                              debugPrint('removeReactionFrom failed: $e\n$st');
                              if (context.mounted) {
                                context.showErrorSnackbar(
                                  "Couldn't remove reaction — try again.",
                                );
                              }
                            }
                          },
                          onEdit:
                              () => _showEditDialog(
                                context,
                                ref,
                                conversation,
                                message,
                              ),
                          onDelete:
                              () => _confirmAndDelete(
                                context,
                                ref,
                                conversation,
                                message,
                              ),
                          onShowEditHistory:
                              (target) =>
                                  _showEditHistorySheet(context, ref, target),
                        ),
                  );
                  if (isFirstOfDay && shouldAnimate) {
                    bubble = Shimmer(
                      period:
                          expressive
                              ? kShimmerSweepExpressive
                              : kShimmerSweepCalm,
                      child: bubble,
                    );
                  }

                  // A batch of messages arriving together (e.g. after a reconnect via
                  // _catchUpFromCursor) should cascade in rather than pop
                  // simultaneously: offset each new bubble's settle duration by its
                  // position within the newest-first list. The index is clamped so a
                  // large batch never produces an absurdly long settle. Cached
                  // history (`isNew == false`) always uses the base duration.
                  final stepMs =
                      expressive
                          ? kCascadeStepExpressiveMs
                          : kCascadeStepCalmMs;
                  final staggeredDuration =
                      shouldAnimate
                          ? kSettleDuration +
                              Duration(milliseconds: stepMs * index.clamp(0, 6))
                          : kSettleDuration;

                  final row = KeyedSubtree(
                    key: messageKey,
                    child: Padding(
                      // This list is reverse: true with state.messages newest-first,
                      // so `older` (index+1) renders physically ABOVE this message
                      // on screen — a top-padding here is exactly the gap between
                      // this bubble and its older neighbor above it. Same-sender
                      // messages keep only a hairline gap so their squared inner
                      // corners still read as one connected stack; a sender switch
                      // or day boundary restores the normal breathing room.
                      padding: EdgeInsets.only(
                        top: isGrouped ? 3 : 12,
                        // Inherited from the list, which no longer applies it
                        // so the date rule can span the full width.
                        left: 8,
                        right: 8,
                      ),
                      // Opens the row's own vertical space as it arrives, so
                      // the messages above are physically displaced by exactly
                      // this bubble's height instead of jumping to their new
                      // positions a frame before it fades in. Outside SettleIn
                      // so the slot grows while the bubble settles into it.
                      child: MakeRoom(
                        animate: shouldAnimate,
                        child: SettleIn(
                          key: ValueKey(message.clientMessageId),
                          // Only animate a message the first time it is built after
                          // arriving live (cached history never replays on open, and
                          // recycled items never replay on scroll-back — Spec §2
                          // play-once).
                          animate: shouldAnimate,
                          duration: staggeredDuration,
                          beginOffset:
                              message.isMine
                                  ? const Offset(0, 0.12)
                                  : const Offset(0, 0.10),
                          child: bubble,
                        ),
                      ),
                    ),
                  );

                  if (!isFirstOfDay) return row;

                  // The separator comes FIRST, so it renders above the
                  // message whose day it names.
                  //
                  // reverse: true flips the LIST's scroll axis; it does not
                  // reverse the children of an individual item. Placing the
                  // separator after the row put it BELOW the message, so
                  // the first message of a new day sat above its own
                  // "Today" divider and read as part of yesterday. The
                  // day's second message looked right, because it is not
                  // first-of-day and draws no separator at all — which is
                  // what made this look like a send-path bug rather than a
                  // layout one.
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        // 32 above, 20 below, which lands SYMMETRIC on
                        // screen: the row beneath contributes its own 12px
                        // top padding, so an even 20/20 here measures
                        // 20 above and 32 below and leans the separator
                        // toward the older day. A day boundary should also
                        // read as a bigger break than a sender change,
                        // which already gets 12.
                        padding: const EdgeInsets.only(top: 32, bottom: 20),
                        child: ChatDateSeparator(
                          label: chatDateLabel(message.createdAt),
                        ),
                      ),
                      row,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        // Floats over the list, so it must never take a pointer: a tap
        // meant for the bubble underneath has to reach it.
        if (pinnedLabel != null)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: ChatDateChip(
                  label: pinnedLabel,
                  opacity: _pinnedDateVisible ? 1 : 0,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Confirms then soft-deletes [message]. Deletion is irreversible for both
/// members, so it always goes through an explicit confirm step.
Future<void> _confirmAndDelete(
  BuildContext context,
  WidgetRef ref,
  Conversation conversation,
  Message message,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: const Text('Delete message?'),
          content: const Text('This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                'Delete',
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.error,
                ),
              ),
            ),
          ],
        ),
  );
  if (confirmed != true) return;

  try {
    await ref
        .read(chatControllerProvider(conversation).notifier)
        .deleteMessage(message);
  } catch (e, st) {
    debugPrint('deleteMessage failed: $e\n$st');
    if (context.mounted) {
      context.showErrorSnackbar("Couldn't delete — try again.");
    }
  }
}

/// Edits [message] in place. The server enforces the sender-only, 5-minute
/// edit window; a rejection surfaces as a generic retry snackbar rather than
/// leaking the reason.
Future<void> _showEditDialog(
  BuildContext context,
  WidgetRef ref,
  Conversation conversation,
  Message message,
) async {
  final controller = TextEditingController(text: message.content);
  final newContent = await showDialog<String>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: const Text('Edit message'),
          content: TextField(
            controller: controller,
            maxLines: null,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed:
                  () => Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
  );
  // showDialog's future completes the moment pop() is called, but the route's
  // dismiss transition keeps rebuilding the TextField for a few more frames —
  // disposing here synchronously would throw "used after being disposed".
  // Hand the dispose to the next frame, once the route is gone.
  WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());

  if (newContent == null ||
      newContent.isEmpty ||
      newContent == message.content) {
    return;
  }

  try {
    await ref
        .read(chatControllerProvider(conversation).notifier)
        .editMessage(message, newContent);
  } catch (e, st) {
    debugPrint('editMessage failed: $e\n$st');
    if (context.mounted) {
      context.showErrorSnackbar("Couldn't save edit — try again.");
    }
  }
}

/// Prior versions of [message], oldest first, with the current content last.
/// Opened by tapping the bubble's "edited" label.
Future<void> _showEditHistorySheet(
  BuildContext context,
  WidgetRef ref,
  Message message,
) async {
  final repository = ref.read(chatRepositoryProvider);
  final future = repository.getMessageEditHistory(message.id);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: FutureBuilder<List<MessageEditHistoryEntry>>(
          future: future,
          builder: (builderContext, snapshot) {
            if (snapshot.hasError) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text("Couldn't load edit history right now."),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final entries = snapshot.data!;
            return ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Edit history',
                    style: Theme.of(builderContext).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                ...entries.map(
                  (entry) => ListTile(
                    title: Text(entry.previousContent),
                    subtitle: Text(
                      DateFormat.yMMMd(
                        Localizations.localeOf(builderContext).toString(),
                      ).add_jm().format(entry.editedAt),
                    ),
                  ),
                ),
                ListTile(
                  title: Text(message.content),
                  subtitle: const Text('Current'),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}

/// Horizontal strip of the relationship's pinned messages (max 3, enforced
/// server-side). Tapping one reuses the existing reply-jump mechanism to
/// scroll to and flash it in the list.
class _PinnedMessagesBanner extends StatelessWidget {
  const _PinnedMessagesBanner({
    required this.pinnedMessages,
    required this.onTap,
  });

  final List<Message> pinnedMessages;
  final void Function(Message) onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
          ),
        ),
        child: SizedBox(
          height: 40.h,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: pinnedMessages.length,
            itemBuilder: (context, index) {
              final message = pinnedMessages[index];
              final isLast = index == pinnedMessages.length - 1;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => onTap(message),
                    splashColor: colorScheme.primary.withValues(alpha: 0.12),
                    highlightColor: colorScheme.primary.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.sm),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.push_pin,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Text(
                              message.isDeleted
                                  ? 'This message was deleted'
                                  : message.content,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!isLast)
                    Container(
                      width: 1,
                      height: 24,
                      color: colorScheme.outlineVariant,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TypingIndicatorBubble extends StatelessWidget {
  const _TypingIndicatorBubble();

  @override
  Widget build(BuildContext context) {
    final chatColors = Theme.of(context).chatColors;
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: chatColors.receiverBubble,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            offset: Offset(0, 1),
            blurRadius: 1,
            spreadRadius: -1,
            color: Color(0x0F000000),
          ),
          BoxShadow(
            offset: Offset(0, 1),
            blurRadius: 2,
            color: Color(0x0A000000),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        child: BreathingDots(
          size: 7,
          color: colorScheme.primary.withValues(alpha: 0.82),
        ),
      ),
    );
  }
}

String _relativeSyncLabel(DateTime value) {
  final delta = DateTime.now().difference(value);
  if (delta.inSeconds < 10) return 'just now';
  if (delta.inMinutes < 1) return '${delta.inSeconds}s ago';
  if (delta.inHours < 1) return '${delta.inMinutes}m ago';
  return '${delta.inHours}h ago';
}

const _monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Opens a game, from either the picker sheet or a chat game card.
///
/// Top-level rather than a method: the sheet is opened from the chat
/// screen's state and the cards are built inside the message list's, and
/// both must route identically -- a card and the picker landing in
/// different places for the same game would be the worst kind of bug here.
Future<void> openGameRoute(
  BuildContext context,
  ChatGameDestination destination, {
  required String relationshipId,
}) async {
  switch (destination) {
    case ChatGameDestination.neverHaveIEver:
      // Coming soon in the catalogue, so the row does not fire this.
      // Kept exhaustive rather than defaulted: adding a game to the
      // enum should break this switch, not silently route nowhere.
      break;
    case ChatGameDestination.thirtySixQuestions:
      // Its own entry screen, which resumes an in-progress journey or
      // starts one. Previously the games hub, the only game not routed
      // to itself.
      await context.pushNamed('thirtySixQuestions');
    case ChatGameDestination.mirror:
      await context.pushNamed('mirrorGame');
    case ChatGameDestination.slidingScale:
      await context.pushNamed('slidingScaleGame');
    case ChatGameDestination.scenario:
      await context.pushNamed('scenarioGame');
    case ChatGameDestination.loveMap:
      await context.pushNamed('loveMap');
    case ChatGameDestination.thisOrThat:
      await context.pushNamed('thisOrThatGamesHub');
    case ChatGameDestination.truthOrDare:
      await context.pushNamed('truthOrDareGame');
    case ChatGameDestination.paintBall:
      await context.pushNamed(
        'paintBallLobby',
        pathParameters: {'relationshipId': relationshipId},
      );
  }
}
