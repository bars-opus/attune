import 'dart:async';
import 'dart:math' as math;

import 'package:attune/app/routing/app_route_observer.dart';
import 'package:attune/app/theme/chat_color_scheme.dart';
import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/ui/layout/measure_size.dart';
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/make_room.dart';
import 'package:attune/core/ui/motion/payload_flight.dart';
import 'package:attune/core/ui/motion/reaction_landing_effect.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/conflict_translator/presentation/providers/translator_register_preference.dart';
import 'package:attune/features/wins/presentation/share_win_sheet.dart';
import 'package:attune/features/wins/presentation/support_chips_sheet.dart';
import 'package:attune/features/wins/presentation/win_providers.dart';
import 'package:attune/features/appreciation/data/thankful_phrasing_preference.dart';
import 'package:attune/features/appreciation/presentation/appreciation_sheet.dart';
import 'package:attune/features/appreciation/data/appreciation_service.dart';
import 'package:attune/features/quiet_states/presentation/quiet_state_providers.dart';
import 'package:attune/features/conflict_toolkit/data/pause_service.dart';
import 'package:attune/features/conflict_toolkit/data/pause_timer_store.dart';
import 'package:attune/features/conflict_toolkit/data/toolkit_texts.dart';
import 'package:attune/features/conflict_toolkit/presentation/apology_sheet.dart';
import 'package:attune/features/conflict_toolkit/presentation/hard_moment_sheet.dart';
import 'package:attune/features/conflict_toolkit/presentation/pause_reply_chip.dart';
import 'package:attune/features/conflict_toolkit/presentation/pause_sheet.dart';
import 'package:attune/features/conflict_toolkit/presentation/pause_timer_card.dart';
import 'package:attune/features/conflict_toolkit/presentation/repair_tray.dart';
import 'package:attune/features/conflict_toolkit/presentation/start_conversation_sheet.dart';
import 'package:attune/features/chat/presentation/widgets/chat_date_chip.dart';
import 'package:attune/features/chat/presentation/widgets/chat_empty_state.dart';
import 'package:attune/app/documentations/user_manual/data/documentation_flags.dart';
import 'package:attune/core/ui/motion/settle_in.dart';
import 'package:attune/core/ui/motion/shimmer.dart';
import 'package:attune/core/ui/presence/breathing_dots.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/ai_assistant/data/models/ai_session_model.dart'
    show AiSessionKind;
import 'package:attune/features/ai_assistant/presentation/providers/ai_assistant_providers.dart'
    show aiSessionCapabilitiesProvider;
import 'package:attune/features/ai_assistant/presentation/screens/ai_session_entry.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/services/chat_image_picker.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/state/typing_controller.dart';
import 'package:attune/features/chat/presentation/state/voice_playback_controller.dart';
import 'package:attune/core/widgets/app_content_width.dart';
import 'package:attune/features/chat/presentation/widgets/attune_chat_wallpaper.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:attune/features/chat/presentation/widgets/rune_length_limiting_formatter.dart';
import 'package:attune/features/chat/presentation/widgets/emoji_message_content.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:attune/features/chat/presentation/widgets/message_status_rule.dart';
import 'package:attune/features/chat/presentation/widgets/chat_media_group.dart';
import 'package:attune/features/chat/presentation/widgets/message_arrival_tracker.dart';
import 'package:attune/features/chat/presentation/widgets/game_move_ledger.dart';
import 'package:attune/features/chat/presentation/widgets/pending_arrivals.dart';
import 'package:attune/features/chat/presentation/widgets/reply_composer_preview.dart';
import 'package:attune/features/conflict_translator/presentation/providers/translator_providers.dart'
    as translator_providers;
import 'package:attune/features/conflict_translator/presentation/screens/translator_sheet.dart';
import 'package:attune/features/games/paint_ball/models/paint_ball_models.dart';
import 'package:attune/features/games/invites/presentation/game_composer_bar.dart';
import 'package:attune/features/games/invites/state/game_invite_provider.dart';
import 'package:attune/features/games/presentation/providers/game_card_provider.dart';
import 'package:attune/features/games/presentation/providers/game_partner_name_provider.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart'
    show gameTypeDisplayName;
import 'package:attune/features/games/presentation/widgets/chat_games_sheet.dart';
import 'package:attune/features/games/presentation/widgets/game_icon.dart';
import 'package:attune/features/games/presentation/widgets/game_palette.dart';
import 'package:attune/features/settings/data/chat_feel_preference.dart';
import 'package:attune/features/settings/data/sound_preference.dart';
import 'package:attune/core/services/media/image_picker_service.dart';
import 'package:attune/core/services/media/voice_recorder_service.dart';
import 'package:attune/core/ui/motion/glow_pulse.dart';
import 'package:attune/core/widgets/profile_avatar.dart';
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:clock/clock.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/scheduler.dart' show SchedulerPhase;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:video_compress/video_compress.dart';
import 'package:attune/features/chat/presentation/providers/partner_presence_provider.dart';
import 'package:attune/features/location/presentation/widgets/share_place_sheet.dart';
import 'package:attune/features/chat/presentation/widgets/linkified_message_text.dart';
import 'package:attune/features/chat/presentation/widgets/chat_list_scroll_controller.dart';
import 'package:attune/features/chat/presentation/widgets/scroll_to_latest_pill.dart';
import 'package:attune/features/chat/presentation/widgets/unread_divider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversation,
    this.initialJumpToMessageId,
    this.initialDraft,
  });

  final Conversation conversation;

  /// Set when arriving from a screen that points at one specific message
  /// (e.g. Starred messages) — scrolled to and flashed once the message
  /// list has loaded, paging further back (ChatController
  /// .ensureMessageLoaded) if the message isn't in the initially-loaded
  /// page. Null means no jump, the
  /// normal "open at the latest message" behavior.
  final String? initialJumpToMessageId;

  /// Text to start the composer with (e.g. Together's "How did it go?"),
  /// used instead of a saved draft. Null or empty: the saved draft as usual.
  final String? initialDraft;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver, RouteAware {
  final _controller = TextEditingController();
  final _composerFocusNode = FocusNode();
  final _composerTextKey = GlobalKey();
  final _replyPreviewSurfaceKey = GlobalKey();
  final _gameComposerPayloadKey = GlobalKey();
  final _scrollController = ChatListScrollController();
  final _imagePicker = ImagePickerService();
  // Once-per-message animation ledger: ListView.builder recycles item State
  // when a bubble scrolls out of cacheExtent. IDs recorded here animate
  // exactly once per screen lifetime.
  final Set<String> _animatedMessageIds = <String>{};
  bool _headerExpanded = false;
  bool _headerOverlayMounted = false;
  Timer? _headerOverlayRemovalTimer;
  bool _isForeground = true;

  /// True while another route (a game, a viewer, a sheet) sits on top of this
  /// one. Set by RouteAware; State.deactivate does not fire for a push.
  bool _coveredByRoute = false;
  ModalRoute<Object?>? _observedRoute;

  /// App-scoped (one voice engine app-wide), so this screen says when it is
  /// left; captured in initState because ref is unusable in dispose.
  late final VoicePlaybackController _voicePlayback;

  /// Reply target set by swiping a message — mirrors
  /// DebateRoomScreen._replyToPostId/_replyToQuotedText exactly. Null means
  /// no reply is pending; the quoted-preview strip above the composer only
  /// renders when this is non-null.
  String? _replyToMessageId;
  String? _replyToQuotedText;
  String? _replyMessageClientId;
  bool _replyMessageIsMine = true;
  String _replyingToLabel = 'you';
  ReplyPreviewKind _replyPreviewKind = ReplyPreviewKind.text;
  String? _replyPreviewGameType;
  Rect? _replyOriginRect;
  bool _replyPreviewHidden = false;
  bool _replyFlightInProgress = false;
  int _replyFlightEpoch = 0;

  /// Measured height of the bottom overlay (typing indicator, reply strip,
  /// staged game, pause card, composer and the home-indicator inset). The
  /// message list pads itself by this much so the newest bubble is never
  /// covered (#33). Null until the first frame has measured it.
  double? _bottomOverlayHeight;

  /// Maps every loaded message id to its currently rendered row. Media-group
  /// members may share the representative row's key. Used by _jumpToMessage
  /// to scroll a currently-built message into view.
  final Map<String, GlobalKey> _messageKeys = {};

  /// Exact painted bubble surfaces, keyed by stable client id. These are
  /// animation targets; _messageKeys above intentionally remain row keys for
  /// scroll-to-message behavior.
  final Map<String, GlobalKey> _bubbleFillKeys = {};
  final Map<String, int> _reactionImpactTokens = {};
  final Set<String> _flyingMessageIds = <String>{};
  final Set<String> _flyingGameSessionIds = <String>{};

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
    _voicePlayback = ref.read(voicePlaybackControllerProvider.notifier);
    // This chat taking the screen stops a note from ANOTHER conversation
    // (chat B pushed over A by a notification): one conversation audible at
    // a time, as in WhatsApp — the person has left A's conversation even
    // though its route survives underneath. Deferred: initState runs inside
    // a build, where changing a provider throws.
    final ownerId = widget.conversation.relationshipId;
    final playback = _voicePlayback;
    scheduleMicrotask(
      () => unawaited(playback.stopIfOwnedByAnother(ownerId)),
    );
    // Stories Wave 3: the shell keeps this screen mounted behind the privacy
    // cover and the Safety lock check, so presence and read receipts also
    // wait for the lock to open (a return that ends at the PIN screen must
    // not mark anything read).
    ref.listenManual<bool>(
      appContentVisibleProvider,
      (_, __) => _syncViewActive(),
    );
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onDraftChanged);
    Future.microtask(_restoreDraft);
    // Mark the view active once the first frame has rendered so read receipts
    // are only sent when the conversation is visible, foregrounded, and the
    // message list has drawn (Spec 6.4).
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncViewActive());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && !identical(route, _observedRoute)) {
      if (_observedRoute != null) appRouteObserver.unsubscribe(this);
      _observedRoute = route;
      appRouteObserver.subscribe(this, route);
    }
    // RouteObserver reports pops but not removals: a page taken off the
    // stack without a pop (removeRoute, a declarative stack change) never
    // calls didPopNext. ModalRoute.of depends on isCurrent, so this runs
    // when the chat is back on top however the cover left.
    if (_coveredByRoute && route != null && route.isCurrent) {
      _coveredByRoute = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncViewActive());
    }
  }

  @override
  void didPushNext() {
    // A sheet, dialog or menu (PopupRoute) leaves the chat visible and the
    // person in it: presence and read receipts carry on. Anything else — a
    // game, a viewer, settings, a camera — covers it.
    if (appRouteObserver.lastPushedRoute is PopupRoute) return;
    _coveredByRoute = true;
    _syncViewActive();
  }

  /// This chat's own route was popped: leaving the chat stops voice playback.
  /// A sheet or a page pushed OVER the chat (viewer, game) does not — the
  /// chat is still there underneath (didPushNext leaves playback alone).
  @override
  void didPop() => _stopVoicePlayback();

  /// Spec: leaving the chat screen stops voice playback (no background
  /// playback). Deferred a microtask: a pop or dispose can land while the
  /// tree is building or locked, where changing a provider throws. stop()
  /// is idempotent, so the pop and the dispose that follows are both safe.
  /// Owner-scoped: chat A going away under chat B leaves B's note playing.
  void _stopVoicePlayback() {
    final playback = _voicePlayback;
    final ownerId = widget.conversation.relationshipId;
    scheduleMicrotask(() => unawaited(playback.stop(ifOwnedBy: ownerId)));
  }

  /// A note whose message went away (deleted, purged, hidden) has lost its
  /// bubble, the only control that could pause it: stop it. Only a note that
  /// WAS a live voice message in this list counts, so a note this list
  /// never held (an older one played from Media) is left alone.
  void _stopVoiceWhoseMessageWentAway(
    List<Message>? previous,
    List<Message> next,
  ) {
    final current = ref.read(voicePlaybackControllerProvider).messageId;
    if (current == null || previous == null) return;
    bool live(Message m) =>
        m.clientMessageId == current && m.hasAudio && !m.isDeleted;
    if (!previous.any(live) || next.any(live)) return;
    final playback = _voicePlayback;
    // Deferred like the other stops: the list can change mid-build.
    scheduleMicrotask(() => unawaited(playback.stopMessage(current)));
  }

  @override
  void didPopNext() {
    _coveredByRoute = false;
    _syncViewActive();
    // ModalRoute.isCurrent can lag the pop by a frame; settle once more.
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
    // deactivate() rather than dispose(): ref is still usable here. It
    // fires on a pop; a push over this route is handled by RouteAware
    // (didPushNext), which deactivate() does not see.
    ref
        .read(chatControllerProvider(widget.conversation).notifier)
        .setViewActive(false);
    super.deactivate();
  }

  @override
  void dispose() {
    // Also here, not only in didPop: a route removed without a pop (a
    // declarative stack change) never calls didPop.
    _stopVoicePlayback();
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onDraftChanged);
    _controller.dispose();
    _composerFocusNode.dispose();
    _scrollController.dispose();
    _highlightTimer?.cancel();
    _headerOverlayRemovalTimer?.cancel();
    // The controller outlives the screen (keep-alive): a jump still paging
    // must stop with it. cancelJump writes no state.
    _jumpPager?.cancelJump();
    // No streak row stays locked behind a viewer route that was lost.
    releaseStreakViewerGuards();
    super.dispose();
  }

  /// MeasureSize reports post-frame, so setState here never runs during
  /// layout. Whole logical pixels, rounded up, so an animating composer
  /// (AnimatedSize) only rebuilds the screen when the reserve really moves
  /// and the newest bubble is never short by a sub-pixel.
  void _onBottomOverlayMeasured(Size size) {
    if (!mounted) return;
    final height = size.height.ceilToDouble();
    if (height == _bottomOverlayHeight) return;
    setState(() => _bottomOverlayHeight = height);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _isForeground;
    _isForeground = state == AppLifecycleState.resumed;
    _syncViewActive();
    // Back in the foreground: resync and send what waited now, not when the
    // socket's heartbeat notices (W1a #1).
    if (_isForeground && !wasForeground) {
      ref
          .read(chatControllerProvider(widget.conversation).notifier)
          .onAppResumed();
    }
  }

  /// Reports current view visibility to the controller. The conversation is
  /// "active" for read purposes only while nothing but a popup (sheet,
  /// dialog, menu) sits over this route — a page pushed on top covers it —
  /// and the app is foregrounded (resumed — inactive/paused/hidden all count
  /// as away, which covers the lock screen).
  void _syncViewActive() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    final isCurrentRoute =
        !_coveredByRoute &&
        (route == null ||
            route.isCurrent ||
            // Not current only because a popup is open on top of it.
            appRouteObserver.lastPushedRoute is PopupRoute);
    ref
        .read(chatControllerProvider(widget.conversation).notifier)
        .setViewActive(
          _isForeground &&
              isCurrentRoute &&
              ref.read(appContentVisibleProvider),
        );
  }

  void _onDraftChanged() {
    unawaited(_persistDraft());
    ref
        .read(
          typingControllerProvider(widget.conversation.relationshipId).notifier,
        )
        .onComposingChanged(_controller.text.trim().isNotEmpty);
  }

  // Spec 7 (B9 (b)): the chosen support line goes into the composer to
  // edit or send; added below anything already written.
  Future<void> _askForSupport() async {
    final line = await showSupportChipsSheet(context);
    if (line == null || !mounted) return;
    final current = _controller.text.trimRight();
    final text = current.isEmpty ? line : '$current\n$line';
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  // Spec 8 (B3; plan review M8): a toolkit line goes into the composer to
  // edit or send, below anything already written; nothing sends by itself.
  void _appendToComposer(String? line) {
    if (line == null || !mounted) return;
    final current = _controller.text.trimRight();
    final text = current.isEmpty ? line : '$current\n$line';
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _openRepairTray() async =>
      _appendToComposer(await showRepairTray(context));

  Future<void> _openStartConversation() async =>
      _appendToComposer(await showStartConversationSheet(context));

  Future<void> _openHardMoment() async {
    final action = await showHardMomentSheet(context);
    if (action == null || !mounted) return;
    switch (action) {
      case HardMomentAction.pause:
        await _takeAPause();
      case HardMomentAction.repair:
        await _openRepairTray();
      case HardMomentAction.apology:
        _appendToComposer(await showApologySheet(context));
      case HardMomentAction.start:
        await _openStartConversation();
    }
  }

  // The fixed message goes as an ordinary message; the timer is this
  // device's alone.
  Future<void> _takeAPause() async {
    final relationshipId = widget.conversation.relationshipId;
    await showPauseSheet(
      context,
      onSend: (variant, clientMessageId) async {
        await ref
            .read(pauseServiceProvider)
            .send(
              relationshipId: relationshipId,
              clientMessageId: clientMessageId,
              variant: variant,
            );
        await ref
            .read(pauseTimerProvider(relationshipId).notifier)
            .start(kPauseMinutes[variant]!);
      },
    );
  }

  Future<void> _restoreDraft() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final draft = await ref
        .read(chatCacheServiceProvider)
        .readDraft(user.id, widget.conversation.relationshipId);
    if (!mounted) return;
    final given = widget.initialDraft;
    if (given != null && given.isNotEmpty) {
      // Keep whatever was already written and add the given text below it.
      // Set without the draft listener: nothing is saved (and no typing
      // indicator is sent) until the user actually edits.
      final text = draft.isEmpty ? given : '$draft\n$given';
      _controller.removeListener(_onDraftChanged);
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _controller.addListener(_onDraftChanged);
      return;
    }
    if (draft.isEmpty) return;
    // Restoring is not typing. Set the text without the draft listener,
    // exactly like the initialDraft branch above: no typing broadcast to the
    // partner, and the identical draft is not re-encrypted and re-written.
    _controller.removeListener(_onDraftChanged);
    _controller.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
    _controller.addListener(_onDraftChanged);
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

  /// RC-16: sendMessage silently drops an over-limit draft, and the
  /// composer used to be cleared first — so 10,001 characters vanished
  /// without a word. True when [text] was refused (and the person told).
  bool _refuseOverLimitDraft(String text) {
    if (Message.isValidContent(text)) return false;
    context.showErrorSnackbar(tooLongMessageNotice());
    return true;
  }

  Future<void> _send() async {
    final text = _controller.text.trim();

    // A staged game is the thing being sent; the text, if any, is a note
    // about it. Checked BEFORE the empty-text guard below, or a game with
    // no caption would return here and Send would do nothing.
    if (ref
        .read(gameComposerProvider(widget.conversation.relationshipId))
        .isStaged) {
      await _sendStagedGame(caption: text);
      return;
    }

    if (text.isEmpty) return;
    if (_refuseOverLimitDraft(text)) return;
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

  void _setReplyTarget(Message message) {
    if (_replyFlightInProgress) return;
    unawaited(_flyReplyToComposer(message));
  }

  void _clearReplyTarget() {
    _replyFlightEpoch++;
    setState(() {
      final clientId = _replyMessageClientId;
      if (clientId != null) _flyingMessageIds.remove(clientId);
      _replyToMessageId = null;
      _replyToQuotedText = null;
      _replyMessageClientId = null;
      _replyMessageIsMine = true;
      _replyingToLabel = 'you';
      _replyPreviewKind = ReplyPreviewKind.text;
      _replyPreviewGameType = null;
      _replyOriginRect = null;
      _replyPreviewHidden = false;
      _replyFlightInProgress = false;
    });
  }

  ReplyPreviewKind _replyKindFor(Message message) {
    if (message.isGame) return ReplyPreviewKind.game;
    if (message.isStreak) {
      return _replyStreakIsOpened(message)
          ? ReplyPreviewKind.streakOpened
          : ReplyPreviewKind.streak;
    }
    if (message.hasImage || message.mediaType == 'image') {
      return ReplyPreviewKind.image;
    }
    if (message.hasVideo || message.mediaType == 'video') {
      return ReplyPreviewKind.video;
    }
    if (message.hasAudio || message.mediaType == 'audio') {
      return ReplyPreviewKind.audio;
    }
    return ReplyPreviewKind.text;
  }

  bool _replyStreakIsOpened(Message message) {
    if (!message.isStreak) return false;
    if (message.isMine) return message.viewedAt != null;
    return (message.streakViewsRemaining ?? 0) <= 0;
  }

  String? _replyGameTypeFor(Message message) {
    final sessionId = message.gameSessionId;
    if (sessionId == null) return null;
    return ref.read(gameCardProvider(sessionId)).valueOrNull?.gameType;
  }

  String _replyingToLabelFor(Message message) {
    if (message.isMine) return 'you';

    final fetchedName = ref.read(gamePartnerNameProvider).valueOrNull;
    final resolvedName = _actualPartnerName(fetchedName);
    if (resolvedName != null) return resolvedName;

    return _actualPartnerName(widget.conversation.partnerName) ?? 'Partner';
  }

  String? _actualPartnerName(String? value) {
    final name = value?.trim();
    if (name == null || name.isEmpty) return null;
    final normalized = name.toLowerCase();
    if (normalized == 'your partner' || normalized == 'partner') return null;
    return name;
  }

  String _replyPreviewText(Message message) {
    final content = message.content.trim();
    final kind = _replyKindFor(message);
    final fallback = switch (kind) {
      ReplyPreviewKind.game => content.isEmpty ? 'Game' : content,
      ReplyPreviewKind.image => 'Photo',
      ReplyPreviewKind.video =>
        message.isViewOnce ? 'View-once video' : 'Video',
      ReplyPreviewKind.audio => 'Voice message',
      ReplyPreviewKind.streak => 'Streak',
      ReplyPreviewKind.streakOpened => 'Opened',
      ReplyPreviewKind.text => '',
    };
    final text = content.isEmpty ? fallback : content;
    return text.length > 60 ? '${text.substring(0, 60)}...' : text;
  }

  Rect? _bubbleRectForClientId(String? clientId) {
    return clientId == null ? null : _rectForKey(_bubbleFillKeys[clientId]);
  }

  Rect _fallbackReplyPreviewDestination(Rect sourceRect) {
    final composerRect = _rectForKey(_composerTextKey);
    final screenWidth = MediaQuery.sizeOf(context).width;
    return Rect.fromLTWH(
      16,
      (composerRect?.top ?? sourceRect.bottom) - 62,
      math.max(1, screenWidth - 32),
      58,
    );
  }

  Future<void> _flyReplyToComposer(Message message) async {
    final sourceRect = _bubbleRectForClientId(message.clientMessageId);
    final shouldAnimate = sourceRect != null && !reduceMotionOf(context);
    final epoch = ++_replyFlightEpoch;
    final quotedText = _replyPreviewText(message);
    final replyKind = _replyKindFor(message);
    final replyGameType = _replyGameTypeFor(message);
    final replyingToLabel = _replyingToLabelFor(message);

    setState(() {
      final previousClientId = _replyMessageClientId;
      if (previousClientId != null) {
        _flyingMessageIds.remove(previousClientId);
      }
      _replyToMessageId = message.id;
      _replyToQuotedText = quotedText;
      _replyMessageClientId = message.clientMessageId;
      _replyMessageIsMine = message.isMine;
      _replyingToLabel = replyingToLabel;
      _replyPreviewKind = replyKind;
      _replyPreviewGameType = replyGameType;
      _replyOriginRect = sourceRect;
      _replyPreviewHidden = shouldAnimate;
      _replyFlightInProgress = shouldAnimate;
      if (shouldAnimate) _flyingMessageIds.add(message.clientMessageId);
    });

    // If the keyboard is already showing, retaining focus is a no-op. If it
    // is closed, this starts its entrance while the tracked flight follows
    // the reply preview to its final position above the composer.
    if (!_composerFocusNode.hasFocus) _composerFocusNode.requestFocus();
    if (!shouldAnimate || !mounted) return;

    await showPayloadFlight(
      context: context,
      sourceRect: sourceRect,
      fallbackDestination: _fallbackReplyPreviewDestination(sourceRect),
      resolveDestination: () => _rectForKey(_replyPreviewSurfaceKey),
      trackDestination: true,
      builder:
          (context, progress) => _ReplyPayloadFlight(
            quotedText: quotedText,
            isMine: message.isMine,
            replyingToLabel: replyingToLabel,
            kind: replyKind,
            gameType: replyGameType,
            morphProgress: progress,
          ),
    );

    if (!mounted || epoch != _replyFlightEpoch) return;
    setState(() {
      _flyingMessageIds.remove(message.clientMessageId);
      _replyPreviewHidden = false;
      _replyFlightInProgress = false;
    });
  }

  Future<void> _cancelReplyTarget() async {
    if (_replyFlightInProgress || _replyToMessageId == null) return;

    final previewRect = _rectForKey(_replyPreviewSurfaceKey);
    final clientId = _replyMessageClientId;
    final destination = _bubbleRectForClientId(clientId) ?? _replyOriginRect;
    final quotedText = _replyToQuotedText ?? '';
    final isMine = _replyMessageIsMine;
    final replyingToLabel = _replyingToLabel;
    final replyKind = _replyPreviewKind;
    final replyGameType = _replyPreviewGameType;
    final shouldAnimate =
        previewRect != null && destination != null && !reduceMotionOf(context);
    if (!shouldAnimate) {
      _clearReplyTarget();
      return;
    }

    final epoch = ++_replyFlightEpoch;
    setState(() {
      _replyPreviewHidden = true;
      _replyFlightInProgress = true;
      if (clientId != null) _flyingMessageIds.add(clientId);
    });

    await showPayloadFlight(
      context: context,
      sourceRect: previewRect,
      fallbackDestination: destination,
      // The remembered origin is already a valid landing point. Do not park
      // the preview for ten frames if keyboard resizing recycled the bubble.
      destinationWaitFrames: 1,
      resolveDestination: () => _bubbleRectForClientId(clientId),
      builder:
          (context, progress) => _ReplyPayloadFlight(
            quotedText: quotedText,
            isMine: isMine,
            replyingToLabel: replyingToLabel,
            kind: replyKind,
            gameType: replyGameType,
            morphProgress: 1 - progress,
          ),
    );

    if (!mounted || epoch != _replyFlightEpoch) return;
    setState(() {
      if (clientId != null) _flyingMessageIds.remove(clientId);
      _replyToMessageId = null;
      _replyToQuotedText = null;
      _replyMessageClientId = null;
      _replyMessageIsMine = true;
      _replyingToLabel = 'you';
      _replyPreviewKind = ReplyPreviewKind.text;
      _replyPreviewGameType = null;
      _replyOriginRect = null;
      _replyPreviewHidden = false;
      _replyFlightInProgress = false;
    });
  }

  /// Scrolls to [messageId] if it's currently built (mounted GlobalKey),
  /// then re-checks where it landed, nudges it into view if a correction
  /// left it off, and flashes it. Returns whether it found something to
  /// scroll to — the caller pages/scrolls further when this returns false.
  /// Under reduce motion the scroll is a jump, not an animation.
  bool _tryEnsureMessageVisible(String messageId) {
    final targetContext = _messageKeys[messageId]?.currentContext;
    if (targetContext == null) return false;

    final epoch = _jumpEpoch;
    final reduceMotion = reduceMotionOf(context);
    final scrolled = Scrollable.ensureVisible(
      targetContext,
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.5,
    );
    unawaited(
      scrolled.then((_) async {
        if (!mounted || epoch != _jumpEpoch) return;
        await _settleOnTarget(messageId, epoch);
        if (!mounted || epoch != _jumpEpoch) return;
        _highlightTimer?.cancel();
        setState(() => _highlightedMessageId = messageId);
        _highlightTimer = Timer(const Duration(milliseconds: 1200), () {
          if (mounted) setState(() => _highlightedMessageId = null);
        });
      }),
    );
    return true;
  }

  /// After ensureVisible: the list's place hold (ChatListScrollController)
  /// can correct a row-targeted drive mid-flight and leave it a frame step
  /// off its row. Re-measure and jump the rest of the way (a few frames at
  /// most; the row's own layout settles as it is first painted).
  Future<void> _settleOnTarget(String messageId, int epoch) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      if (!mounted || epoch != _jumpEpoch) return;
      final box = _messageKeys[messageId]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      if (!_scrollController.hasClients) return;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) return;
      final position = _scrollController.position;
      final reveal = viewport.getOffsetToReveal(box, 0.5).offset;
      final target = reveal.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      // Within a pixel of centred (or as centred as the extent allows).
      if ((position.pixels - target).abs() <= 1) return;
      position.jumpTo(target);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// Bumped by every jump, so an older jump still converging (or its
  /// delayed flash) stands down when a newer one starts.
  int _jumpEpoch = 0;

  /// A touch, a scroll-wheel/trackpad scroll or a trackpad pan on the
  /// message list supersedes any jump in progress: paging toward the target
  /// (the controller stops between pages), the scroll that follows, the
  /// settle and its flash all stand down, so nothing moves the list under
  /// the person's hand. (A reply quote's own tap is a pointer down too, but
  /// its jump starts on the pointer UP, after this has run.)
  void _cancelJumpFromList() {
    final wasLoading = _jumpLoading;
    _jumpEpoch++;
    if (wasLoading) {
      _jumpPager?.cancelJump();
      setState(() {});
    }
  }

  /// The controller paging toward the current jump's target, held so
  /// dispose can stop it without reading a provider.
  ChatController? _jumpPager;

  /// The jump whose target is being paged in, if any. The "Finding that
  /// message…" chip shows only while that is still the current jump: a
  /// newer jump supersedes it, and a superseded load finishing never clears
  /// the newer one's chip.
  int? _jumpLoadingEpoch;
  bool get _jumpLoading =>
      _jumpLoadingEpoch != null && _jumpLoadingEpoch == _jumpEpoch;

  /// The one jump entry point: reply quotes, pinned banner, viewer "Go to
  /// message" and initialJumpToMessageId. Loads the target if needed
  /// (ChatController.ensureMessageLoaded, contiguous pages), then scrolls
  /// until its row is built, then ensureVisible + settle + flash (#30).
  Future<void> _jumpToMessage(
    String messageId,
    List<Message> currentMessages,
  ) async {
    final wasLoading = _jumpLoading;
    final epoch = ++_jumpEpoch;
    final pager = ref.read(
      chatControllerProvider(widget.conversation).notifier,
    );
    // A new jump supersedes the old one: its paging stops between pages
    // (even when this one needs none), and its chip goes now.
    pager.cancelJump();
    if (wasLoading) setState(() {});
    if (_tryEnsureMessageVisible(messageId)) return;

    var messages = currentMessages;
    if (!messages.any((m) => m.id == messageId)) {
      messages = ref.read(chatControllerProvider(widget.conversation)).messages;
    }
    if (!messages.any((m) => m.id == messageId)) {
      setState(() => _jumpLoadingEpoch = epoch);
      _jumpPager = pager;
      var result = JumpTargetResult.exhausted;
      try {
        result = await pager.ensureMessageLoaded(messageId);
      } catch (_) {
        result = JumpTargetResult.exhausted;
      } finally {
        if (mounted && _jumpLoadingEpoch == epoch) {
          setState(() => _jumpLoadingEpoch = null);
        }
      }
      if (!mounted || epoch != _jumpEpoch) return;
      switch (result) {
        case JumpTargetResult.loaded:
          break;
        case JumpTargetResult.cancelled:
          return;
        case JumpTargetResult.tooFarBack:
          context.showInfoSnackbar('That message is too far back to jump to.');
          return;
        case JumpTargetResult.notFound:
        case JumpTargetResult.exhausted:
          context.showInfoSnackbar("Couldn't find that message.");
          return;
      }
      messages = ref.read(chatControllerProvider(widget.conversation)).messages;
      // Let the list build the newly loaded rows before measuring.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || epoch != _jumpEpoch) return;
    }
    final reached = await _scrollUntilBuilt(messageId, messages, epoch);
    // The scroll gave up (the target left the list mid-jump, nothing was
    // built to measure from, or it never converged): say so rather than
    // leave the tap looking ignored.
    if (!reached && mounted && epoch == _jumpEpoch) {
      context.showInfoSnackbar("Couldn't find that message.");
    }
  }

  /// Anchored extrapolation: from the built row nearest the target, step
  /// by (index distance × mean built-row extent), jump, let a frame build,
  /// repeat. Each pass measures real rows, so the error shrinks until the
  /// target's GlobalKey is attached; the old single viewport/keys guess
  /// could never converge on varied row heights (#30).
  ///
  /// Returns whether the target's row was reached (an ensureVisible
  /// started); true too when the jump was superseded, which says nothing.
  Future<bool> _scrollUntilBuilt(
    String messageId,
    List<Message> messages,
    int epoch,
  ) async {
    if (!_scrollController.hasClients) return false;
    for (var attempt = 0; attempt < 24; attempt++) {
      if (!mounted || epoch != _jumpEpoch) return true;
      if (_tryEnsureMessageVisible(messageId)) return true;
      // Re-read each pass: an arrival at the newest end shifts indices.
      final current =
          ref.read(chatControllerProvider(widget.conversation)).messages;
      if (current.isNotEmpty) messages = current;
      final targetIndex = messages.indexWhere((m) => m.id == messageId);
      if (targetIndex == -1) return false;
      final indexById = <String, int>{
        for (var i = 0; i < messages.length; i++) messages[i].id: i,
      };
      final anchor = _nearestBuiltRow(targetIndex, indexById);
      if (anchor == null || !_scrollController.hasClients) break;
      final position = _scrollController.position;
      final estimate =
          anchor.scrollOffset +
          (targetIndex - anchor.index) * anchor.meanExtent;
      position.jumpTo(
        estimate.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted || epoch != _jumpEpoch) return true;
    return _tryEnsureMessageVisible(messageId);
  }

  /// The built row with the index closest to [targetIndex], its scroll
  /// offset (centred) and the mean extent of all built rows.
  ({int index, double scrollOffset, double meanExtent})? _nearestBuiltRow(
    int targetIndex,
    Map<String, int> indexById,
  ) {
    int? bestIndex;
    RenderBox? bestBox;
    var extentSum = 0.0;
    var extentCount = 0;
    final measured = <RenderBox>{};
    for (final entry in _messageKeys.entries) {
      final index = indexById[entry.key];
      final context = entry.value.currentContext;
      if (index == null || context == null) continue;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      // Media-run members share their representative's key: count the box
      // once in the mean.
      if (measured.add(box)) {
        extentSum += box.size.height;
        extentCount++;
      }
      if (bestIndex == null ||
          (index - targetIndex).abs() < (bestIndex - targetIndex).abs()) {
        bestIndex = index;
        bestBox = box;
      }
    }
    if (bestIndex == null || bestBox == null || extentCount == 0) return null;
    final viewport = RenderAbstractViewport.maybeOf(bestBox);
    if (viewport == null) return null;
    // Rows carry a small top padding inside their box and the date
    // separator sits inside some rows, so the mean is only an estimate —
    // the loop's next measurement corrects for it.
    return (
      index: bestIndex,
      scrollOffset: viewport.getOffsetToReveal(bestBox, 0.5).offset,
      meanExtent: extentSum / extentCount,
    );
  }

  Future<void> _sendDraftText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (_refuseOverLimitDraft(trimmed)) return;

    // Sending finishes this draft immediately from the composer's point of
    // view. Keeping it in the controller until the network request completed
    // forced the whole field to be disabled (and therefore unfocused), and it
    // also made any text typed for the next message vulnerable to the late
    // clear below. Snapshot reply metadata before clearing it for the next
    // message.
    final replyToMessageId = _replyToMessageId;
    final quotedText = _replyToQuotedText;
    final sourceRect = _composerPayloadRect(trimmed);
    String? optimisticClientId;
    var flightCompleted = false;
    final flight =
        sourceRect == null
            ? null
            : showPayloadFlight(
              context: context,
              sourceRect: sourceRect,
              fallbackDestination: _fallbackMessageDestination(sourceRect),
              resolveDestination: () {
                final clientId = optimisticClientId;
                return clientId == null
                    ? null
                    : _rectForKey(_bubbleFillKeys[clientId]);
              },
              builder:
                  (context, progress) =>
                      _OutgoingTextFlight(text: trimmed, progress: progress),
            );
    _controller.clear();
    _clearReplyTarget();

    final send = ref
        .read(chatControllerProvider(widget.conversation).notifier)
        .sendMessage(
          trimmed,
          replyToMessageId: replyToMessageId,
          quotedText: quotedText,
          onOptimisticMessage: (message) {
            optimisticClientId = message.clientMessageId;
            if (flight != null && !flightCompleted && mounted) {
              setState(() => _flyingMessageIds.add(message.clientMessageId));
            }
            _scrollToLatest();
          },
        );

    if (flight != null) {
      await flight;
      flightCompleted = true;
      final clientId = optimisticClientId;
      if (mounted && clientId != null) {
        setState(() => _flyingMessageIds.remove(clientId));
      }
    }
    await send;
  }

  Rect? _rectForKey(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Rect? _composerPayloadRect(String text) {
    final fieldRect = _rectForKey(_composerTextKey);
    if (fieldRect == null) return null;
    final style = Theme.of(
      context,
    ).textTheme.bodyLarge?.copyWith(fontSize: 18, height: 1.25);
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      maxLines: 5,
    )..layout(maxWidth: math.max(1, fieldRect.width - 24));
    final width = math.min(fieldRect.width, painter.width + 24);
    final height = math.min(fieldRect.height, painter.height + 18);
    return Rect.fromLTWH(
      fieldRect.left + 12,
      fieldRect.center.dy - height / 2,
      width,
      height,
    );
  }

  Rect _fallbackMessageDestination(Rect sourceRect) {
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(320.0, sourceRect.width);
    return Rect.fromLTWH(
      screen.width - width - 24,
      sourceRect.top - sourceRect.height - 12,
      width,
      sourceRect.height,
    );
  }

  void _startReactionFlight(Message message, String emoji, Rect sourceRect) {
    unawaited(_runReactionFlight(message, emoji, sourceRect));
  }

  Future<void> _runReactionFlight(
    Message message,
    String emoji,
    Rect sourceRect,
  ) async {
    Rect? destination() {
      final bubbleRect = _rectForKey(_bubbleFillKeys[message.clientMessageId]);
      if (bubbleRect == null) return null;
      final center = Offset(
        message.isMine ? bubbleRect.left : bubbleRect.right,
        bubbleRect.top + 18,
      );
      return Rect.fromCenter(center: center, width: 38, height: 38);
    }

    final target = destination();
    final fallback =
        target ??
        Rect.fromCenter(
          center: Offset(
            message.isMine ? sourceRect.left : sourceRect.right,
            sourceRect.bottom + 56,
          ),
          width: 38,
          height: 38,
        );
    await showPayloadFlight(
      context: context,
      sourceRect: sourceRect,
      fallbackDestination: fallback,
      resolveDestination: destination,
      builder:
          (context, progress) => Material(
            type: MaterialType.transparency,
            child: Center(
              child: Text(
                emoji,
                key: const ValueKey('reaction-flight-emoji'),
                style: TextStyle(
                  fontSize: 22 + (2 * math.sin(math.pi * progress)),
                  shadows: const [
                    Shadow(
                      color: Color(0x26000000),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );

    if (!mounted) return;
    final landingCenter = destination()?.center ?? fallback.center;
    setState(() {
      _reactionImpactTokens.update(
        message.clientMessageId,
        (revision) => revision + 1,
        ifAbsent: () => 1,
      );
    });
    await showReactionLandingEffect(
      context: context,
      center: landingCenter,
      emoji: emoji,
    );
  }

  Future<void> _attachImage() async {
    // Chat-only picker: original bytes, staged under <support>/chat_picks, no
    // crop/compress pass before ChatImagePreparer (chat review #20, #27).
    final String? pickedPath;
    try {
      pickedPath = await ref.read(chatImagePickerProvider).pickFromGallery();
    } on ChatImagePickException catch (error) {
      // The picker has already deleted anything it staged.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.failure == ChatImagePickFailure.accessDenied
                ? 'Attune needs access to your photos. You can allow it in Settings.'
                : 'That photo could not be opened. Try a different one.',
          ),
        ),
      );
      return;
    }
    if (pickedPath == null) return;
    if (!mounted) {
      // Picked after the chat closed: nothing will send it.
      unawaited(ChatImagePicker.discard(pickedPath));
      return;
    }

    // Full-screen preview + caption, shown unconditionally after every
    // pick — matches WhatsApp/iMessage's pick-then-caption flow. Null
    // means the user backed out (closed the screen) rather than sending.
    final caption = await context.pushNamed<String>(
      'imageCaption',
      extra: pickedPath,
    );
    if (caption == null || !mounted) {
      unawaited(ChatImagePicker.discard(pickedPath));
      return;
    }

    await _clearDraft();
    // sendImageMessage has no replyToMessageId/quotedText params (image
    // replies are out of scope), so any pending reply target would silently
    // survive this send and get attached to the NEXT text message instead —
    // clear it here so the "Replying to..." strip never outlives the reply
    // it was showing.
    _clearReplyTarget();
    // sendImageMessage takes the RAW picked path and shows the optimistic
    // bubble before running ChatImagePreparer's compression itself (see its
    // own doc comment).
    await ref
        .read(chatControllerProvider(widget.conversation).notifier)
        .sendImageMessage(
          localPath: pickedPath,
          caption: caption,
          onOptimisticMessage: (_) => _scrollToLatest(),
        );
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
          onOptimisticMessage: (_) => _scrollToLatest(),
        );
  }

  Future<void> _attachEphemeralCamera() async {
    // The streak camera, not the ephemeral one: it is the same
    // press-and-hold gesture plus segmentation, a progress ring and a
    // review step. EphemeralCameraScreen stays registered for now rather
    // than being deleted mid-testing.
    await context.pushNamed('streakCamera', extra: widget.conversation);
    if (mounted) _scrollToLatest();
  }

  // Placeholder — file attach is not built yet. Wired now so the composer's
  // '+' sheet has somewhere to go; swap this for the real flow when it ships.
  void _attachFile() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('File sharing is coming soon.')),
    );
  }

  /// Sends the game staged in the composer.
  ///
  /// Nothing happens here on failure beyond the message the composer
  /// shows: the game stays staged and the idempotency key is kept, so
  /// the retry is the same request rather than a second invitation.
  Future<void> _sendStagedGame({String caption = ''}) async {
    if (caption.isNotEmpty && _refuseOverLimitDraft(caption)) return;
    final gameType =
        ref
            .read(gameComposerProvider(widget.conversation.relationshipId))
            .gameType;
    if (gameType == null) return;

    // The caption goes FIRST, as an ordinary message.
    //
    // Two messages rather than one card carrying text: the card's
    // content field is the game's name, written by a database trigger
    // and used as the card's fallback label, so a caption stored there
    // would fight it. As its own message the caption is editable,
    // replyable and deletable like anything else the player typed.
    //
    // Sent before the invite so the conversation reads in the order it
    // was written: the note, then the game it is about.
    if (caption.isNotEmpty) {
      await _sendDraftText(caption);
      if (!mounted) return;
    }

    final sourceRect = _rectForKey(_gameComposerPayloadKey);

    final sessionId =
        await ref
            .read(
              gameComposerProvider(widget.conversation.relationshipId).notifier,
            )
            .send();
    if (sessionId == null || !mounted) return;

    // Stays in the chat. The card the trigger just posted is the
    // confirmation -- pushing into the game would take the player away
    // from the conversation they chose to send it in.
    ref.read(hapticsProvider).selection();
    if (ref.read(messageSoundsEnabledProvider)) {
      ref.read(soundServiceProvider).play(ChatSound.send);
    }
    _scrollToLatest();

    if (sourceRect == null) return;
    setState(() => _flyingGameSessionIds.add(sessionId));
    await showPayloadFlight(
      context: context,
      sourceRect: sourceRect,
      fallbackDestination: _fallbackMessageDestination(sourceRect),
      // The card is created by the invite RPC's database trigger and reaches
      // this list through realtime, not ChatController's local optimistic
      // insertion. Give that measured destination a little longer to arrive.
      destinationWaitFrames: 30,
      resolveDestination: () {
        final messages =
            ref.read(chatControllerProvider(widget.conversation)).messages;
        for (final message in messages) {
          if (message.gameSessionId == sessionId) {
            return _rectForKey(_bubbleFillKeys[message.clientMessageId]);
          }
        }
        return null;
      },
      builder:
          (context, progress) =>
              _OutgoingGameFlight(gameType: gameType, progress: progress),
    );
    if (mounted) {
      setState(() => _flyingGameSessionIds.remove(sessionId));
    }
  }

  void _openGames() {
    FocusScope.of(context).unfocus();
    _closeHeaderExpanded();
    unawaited(
      showChatGamesPicker(
        context,
        relationshipId: widget.conversation.relationshipId,
        onStageNewGame:
            (gameType) => ref
                .read(
                  gameComposerProvider(
                    widget.conversation.relationshipId,
                  ).notifier,
                )
                .stage(gameType),
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

  Future<void> _onVoiceMessageRecorded(VoiceRecording recording) async {
    await ref
        .read(chatControllerProvider(widget.conversation).notifier)
        .sendVoiceMessage(
          localPath: recording.localPath,
          durationMs: recording.durationMs,
          waveform: recording.waveform,
          onOptimisticMessage: (_) => _scrollToLatest(),
        );
  }

  /// The composer's AI entry point (spec §3.3, Plan D Task 9).
  ///
  /// Routes through `openAiSessionSheet` rather than pushing the sheet
  /// itself, which is RULING 24: the long-press "Get ideas" entry point
  /// lives in `ask_attune_mode_sheet.dart`, pushed from a
  /// `StatelessWidget` bubble with no access to this `State`, so a
  /// `bool` here could not see it and two sheets would share Task 7's
  /// single `aiSessionControllerProvider` instance. The invariant is
  /// enforced in the container both entry points share. See that
  /// function's header.
  ///
  /// The root navigator, matching `_buildAskAttuneOpener`'s own choice,
  /// so the session covers the chat rather than nesting inside a
  /// sub-navigator the composer might be in.
  void _openAiSession() {
    FocusScope.of(context).unfocus();
    _closeHeaderExpanded();
    openAiSessionSheet(
      container: ProviderScope.containerOf(context, listen: false),
      navigator: Navigator.of(context, rootNavigator: true),
      relationshipId: widget.conversation.relationshipId,
      // Ideas, because the composer button is the generic entry: it
      // names no place and no target message. Nearby is still
      // reachable from the sheet's own kind choice when
      // `sessionsNearby` allows it — `initialKind` is the kind the
      // entry point ASKED for, not a lock.
      initialKind: AiSessionKind.ideas,
      utcOffsetMinutes: displayedUtcOffsetMinutes(),
      onShared: (_) => _scrollToLatest(),
    );
  }

  Future<void> _openTranslator() async {
    final message = _controller.text.trim();
    if (message.isEmpty) return;

    // Spec 8 (plan review I9): only the message goes, in the chosen
    // register; no profile or tone summary.
    final notifier = ref.read(
      translator_providers.translatorNotifierProvider.notifier,
    );
    await notifier.translate(
      message: message,
      relationshipId: widget.conversation.relationshipId,
      register: ref.read(translatorRegisterProvider),
    );

    if (!mounted) return;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (sheetContext) => TranslatorSheet(
            originalMessage: message,
            onRegisterChanged:
                (register) => notifier.translate(
                  message: message,
                  relationshipId: widget.conversation.relationshipId,
                  register: register,
                ),
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

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (reduceMotionOf(context)) {
        _scrollController.jumpTo(0);
        return;
      }
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
    ref.listen<List<Message>>(
      chatControllerProvider(
        widget.conversation,
      ).select((chat) => chat.messages),
      _stopVoiceWhoseMessageWentAway,
    );
    // Archived (or no longer available, which the controller records as
    // archived): every note of this conversation stops — including one
    // played from Media for a message this list never loaded.
    ref.listen<ConversationAvailability>(
      chatControllerProvider(
        widget.conversation,
      ).select((chat) => chat.conversation.availability),
      (previous, next) {
        if (next != ConversationAvailability.archived || previous == next) {
          return;
        }
        final playback = _voicePlayback;
        final ownerId = widget.conversation.relationshipId;
        scheduleMicrotask(
          () => unawaited(playback.stop(ifOwnedBy: ownerId)),
        );
      },
    );
    ref.watch(gamePartnerNameProvider);
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
    // The game waiting to be sent, if any. Drives the composer swap
    // below: a staged game replaces the text field.
    final stagedGame =
        ref.watch(gameComposerProvider(conversation.relationshipId)).gameType;
    final voiceMessagesEnabled = ref.watch(chatVoiceMessagesEnabledProvider);
    final translatorEnabled = ref.watch(chatTranslatorEntryEnabledProvider);
    final toolkitOn =
        ref.watch(conflictToolkitEnabledProvider).valueOrNull ?? false;
    // Spec §12's `ai_assist_enabled`, read through Task 5's RPC-backed
    // capability service and NEVER through `feature_flags` directly --
    // that table's SELECT policy hides every `ai_%` key from clients
    // (migration 20260953200000), so a direct read returns no row and
    // would be permanently false. See `ai_session_capabilities.dart`.
    //
    // `.valueOrNull == true` matches the three flag reads above
    // exactly: loading and (impossible here, the service never throws)
    // error both read as OFF, which is the direction §12's "defaults
    // off" points. The capability is OFF in every environment today, so
    // this resolves false and `onAiButtonTap` stays null -- which is
    // what hides the button, per `ChatTextField.onAiButtonTap`'s own
    // contract.
    final aiAssistEnabled =
        ref.watch(aiSessionCapabilitiesProvider).valueOrNull?.assist == true;
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
        (_) => unawaited(_jumpToMessage(initialJumpId, state.messages)),
      );
    }

    // The header height a fixed AppBar used to reserve (72, matching the
    // old toolbarHeight) — the message column below still needs this
    // much clearance now that nothing reserves it automatically, so
    // pinned/state banners and the first message don't render under the
    // floating pills.
    const headerHeight = 72.0;

    // No outer keyboard-unfocus GestureDetector wrapping the whole
    // screen: that used to compete with the header pills' own InkWell
    // taps in the same gesture arena (both are TapGestureRecognizers on
    // an ancestor/descendant pair), which was the actual cause of the
    // insights-tap regression — the unfocus handler is scoped to the
    // message-list layer below instead, so header taps are never
    // contested by it.
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Theme.of(context).colorScheme.neutral,
          // No AppBar: the header is three separate floating pills
          // (back+avatar, name+status, expand chevron) painted directly
          // over the wallpaper inside the body, with the pattern
          // visible through the gaps between and around them — an
          // AppBar's own opaque bar has no way to let the wallpaper
          // show through it, so the header moved into the body Stack
          // entirely.
          extendBodyBehindAppBar: true,
            body: Stack(
              children: [
                Positioned.fill(
                  child: AttuneChatWallpaper(
                    scrollController: _scrollController,
                    child: const SizedBox.expand(),
                  ),
                ),
                // Bubbles stop short of the header rather than scrolling
                // underneath it (tried the scroll-under-with-blur
                // treatment; it did not read well against the floating
                // pills, so this reverted to a fixed reserve).
                //
                // The keyboard-unfocus tap is scoped to THIS layer, not
                // the whole screen: wrapping the whole Stack (including
                // the header) used to put the header pills' own InkWell
                // taps in the same gesture arena as this GestureDetector,
                // which was the actual cause of a real regression where
                // tapping the name/status pill stopped opening Pulse.
                Positioned.fill(
                  top: MediaQuery.of(context).padding.top + headerHeight,
                  child: GestureDetector(
                    onTap: () => FocusScope.of(context).unfocus(),
                    behavior: HitTestBehavior.translucent,
                    // On an iPad the conversation is a centred column on
                    // the full-screen wallpaper (header and message bar too).
                    child: AppContentWidth(
                      maxWidth: ContentWidth.chat,
                      child: Column(
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
                          // A failed first load stays up until a page lands
                          // or Retry, not just until the next state write.
                          errorMessage: state.bannerErrorFor(
                            isOnline: isOnline,
                          ),
                          onRetry: () => notifier.loadMessages(),
                        ),
                        Expanded(
                          // A hand on the list takes it back from a jump in
                          // progress (see _cancelJumpFromList).
                          child: Listener(
                            onPointerDown: (_) => _cancelJumpFromList(),
                            onPointerSignal: (_) => _cancelJumpFromList(),
                            onPointerPanZoomStart:
                                (_) => _cancelJumpFromList(),
                            child: _MessageList(
                            conversation: widget.conversation,
                            state: state,
                            scrollController: _scrollController,
                            animatedMessageIds: _animatedMessageIds,
                            messageKeys: _messageKeys,
                            bubbleFillKeys: _bubbleFillKeys,
                            reactionImpactTokens: _reactionImpactTokens,
                            flyingMessageIds: _flyingMessageIds,
                            flyingGameSessionIds: _flyingGameSessionIds,
                            highlightedMessageId: _highlightedMessageId,
                            bottomOverlayHeight: _bottomOverlayHeight,
                            initialUnreadCount: widget.conversation.unreadCount,
                            onScrollToLatest: _scrollToLatest,
                            onReply: _setReplyTarget,
                            onJumpToParent: _jumpToMessage,
                            onReactionFlight: _startReactionFlight,
                          ),
                          ),
                        ),
                      ],
                    ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: AppContentWidth(
                      maxWidth: ContentWidth.chat,
                      child: SizedBox(
                      height: headerHeight,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: Spacing.md.w,
                          vertical: Spacing.sm.h,
                        ),
                        child: _ConversationHeaderCard(
                          conversation: conversation,
                          isExpanded: _headerExpanded,
                          expandedEnabled:
                              headerDrawerEnabled.valueOrNull == true,
                          onToggleExpanded: _toggleHeaderExpanded,
                          isOnline: isOnline,
                          lastSyncedAt: state.lastSyncedAt,
                          onTapHeader: () => unawaited(_openPulse()),
                          onBack: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                    ),
                  ),
                ),
                if (_jumpLoading)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + headerHeight + 8,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: Semantics(
                          liveRegion: true,
                          child: Material(
                            color: Theme.of(context).chatControlSurface,
                            borderRadius: BorderRadius.circular(999),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Under reduce motion a still glyph, as
                                  // everywhere else in the chat.
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child:
                                        reduceMotionOf(context)
                                            ? Icon(
                                              Icons.search_rounded,
                                              key: const ValueKey(
                                                'chat_jump_chip_still_icon',
                                              ),
                                              size: 14,
                                              color:
                                                  Theme.of(
                                                    context,
                                                  ).colorScheme.onSurfaceVariant,
                                            )
                                            : const CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Finding that message…',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: MeasureSize(
                    onChange: _onBottomOverlayMeasured,
                    child: SafeArea(
                    top: false,
                    child: AppContentWidth(
                      maxWidth: ContentWidth.chat,
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
                            final reduceMotion = reduceMotionOf(context);
                            return SizedBox(
                              width: double.infinity,
                              child: AnimatedSwitcher(
                                duration:
                                    reduceMotion
                                        ? Duration.zero
                                        : const Duration(milliseconds: 260),
                                reverseDuration:
                                    reduceMotion
                                        ? Duration.zero
                                        : const Duration(milliseconds: 180),
                                switchInCurve: Curves.linear,
                                switchOutCurve: Curves.linear,
                                layoutBuilder: (currentChild, previousChildren) {
                                  return Stack(
                                    alignment: Alignment.bottomLeft,
                                    children: [
                                      ...previousChildren,
                                      if (currentChild != null) currentChild,
                                    ],
                                  );
                                },
                                transitionBuilder: (child, animation) {
                                  final fade = CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOut,
                                    reverseCurve: Curves.easeIn,
                                  );
                                  final scale = CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutBack,
                                    reverseCurve: Curves.easeInCubic,
                                  );
                                  if (child.key ==
                                      const ValueKey(
                                        'typing_indicator_hidden',
                                      )) {
                                    return child;
                                  }
                                  return Padding(
                                    // No transparent headroom: the list
                                    // clears this measured overlay (#33).
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      8,
                                      16,
                                      8,
                                    ),
                                    child: FadeTransition(
                                      opacity: fade,
                                      child: ScaleTransition(
                                        alignment: Alignment.center,
                                        scale: Tween<double>(
                                          begin: 0.86,
                                          end: 1,
                                        ).animate(scale),
                                        child: child,
                                      ),
                                    ),
                                  );
                                },
                                child:
                                    typing
                                        ? const _TypingIndicatorBubble(
                                          key: ValueKey('typing_indicator'),
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
                          IgnorePointer(
                            ignoring: _replyPreviewHidden,
                            child: Opacity(
                              opacity: _replyPreviewHidden ? 0 : 1,
                              child: ReplyComposerPreview(
                                surfaceKey: _replyPreviewSurfaceKey,
                                quotedText: _replyToQuotedText ?? '',
                                isMine: _replyMessageIsMine,
                                replyingToLabel: _replyingToLabel,
                                kind: _replyPreviewKind,
                                gameType: _replyPreviewGameType,
                                onClose: () => unawaited(_cancelReplyTarget()),
                              ),
                            ),
                          ),
                        // A staged game sits ABOVE the composer rather
                        // than replacing it, so the field stays free to
                        // carry a note about the game being sent.
                        if (conversation.canSend && stagedGame != null)
                          GameComposerBar(
                            relationshipId: conversation.relationshipId,
                            gameType: stagedGame,
                            payloadKey: _gameComposerPayloadKey,
                            onCancel:
                                () =>
                                    ref
                                        .read(
                                          gameComposerProvider(
                                            conversation.relationshipId,
                                          ).notifier,
                                        )
                                        .cancel(),
                          ),
                        // Spec 8 (B3 (a)): the sender's own pause card.
                        if (conversation.canSend && toolkitOn)
                          PauseTimerCard(
                            relationshipId: conversation.relationshipId,
                            onStartConversation:
                                () => unawaited(_openStartConversation()),
                          ),
                        if (conversation.canSend)
                          ChatTextField(
                            controller: _controller,
                            composerTextKey: _composerTextKey,
                            onSend: () {
                              unawaited(_send());
                            },
                            // Drops the camera, attachments and the mic,
                            // keeps the games icon, and makes Send live
                            // with an empty field -- the staged game is
                            // the payload, the text is an optional note.
                            gameStaged: stagedGame != null,
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
                            // Spec 7 (B1): only while the feature is on.
                            onAppreciation:
                                (ref.watch(appreciationEnabledProvider).valueOrNull ??
                                        false)
                                    ? () => showAppreciationSheet(
                                      context,
                                      relationshipId:
                                          widget.conversation.relationshipId,
                                      offerThankful: ref.read(thankfulPhrasingProvider),
                                    )
                                    : null,
                            // Spec 7 (B2): only while the feature is on.
                            onShareWin:
                                (ref.watch(winsEnabledProvider).valueOrNull ??
                                        false)
                                    ? () => showShareWinSheet(
                                      context,
                                      relationshipId:
                                          widget.conversation.relationshipId,
                                    )
                                    : null,
                            // Spec 7 (B9 (b)): a fixed, editable line; never
                            // sent by itself.
                            onAskSupport:
                                (ref.watch(quietStatesEnabledProvider).valueOrNull ??
                                        false)
                                    ? _askForSupport
                                    : null,
                            // Spec 8 (B3; plan review I5, M8): both flags.
                            onHardMoment:
                                toolkitOn
                                    ? () => unawaited(_openHardMoment())
                                    : null,
                            onSendLongPress:
                                toolkitOn
                                    ? () => unawaited(_openRepairTray())
                                    : null,
                            onOpenGames: _openGames,
                            // Null hides the entry point, and that IS
                            // the capability gate (ChatTextField's own
                            // contract). Nothing else about the
                            // composer changes: `aiMode` is NOT passed,
                            // so it stays at its `false` default and
                            // every control the composer draws today
                            // keeps drawing. Entering AI mode is a
                            // later task's work; this task only opens
                            // the door.
                            onAiButtonTap:
                                aiAssistEnabled ? _openAiSession : null,
                            showAttachImage:
                                imageSharingEnabled.valueOrNull == true,
                            showAttachVideo: videoAttachEnabled,
                            showCaptureVideo: captureVideoEnabled,
                            showGames: true,
                            showTranslator:
                                translatorEnabled.valueOrNull == true,
                            showVoiceMessage:
                                voiceMessagesEnabled.valueOrNull == true,
                            haptics: ref.read(hapticsProvider),
                            recordingHaptics: ref.read(
                              recordingHapticsProvider,
                            ),
                            soundService: ref.read(soundServiceProvider),
                            soundsEnabled: ref.watch(
                              messageSoundsEnabledProvider,
                            ),
                            onVoiceMessageRecorded:
                                voiceMessagesEnabled.valueOrNull == true
                                    ? (recording) {
                                      unawaited(
                                        _onVoiceMessageRecorded(recording),
                                      );
                                    }
                                    : null,
                            // An optimistic send is delivery work, not a reason
                            // to disable composing. Disabling TextField drops
                            // focus and closes the keyboard; the sent draft is
                            // already cleared synchronously in _sendDraftText.
                            enabled: true,
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
    required this.onTapHeader,
    required this.onBack,
  });

  final Conversation conversation;
  final bool isExpanded;
  final bool expandedEnabled;
  final VoidCallback onToggleExpanded;
  final bool isOnline;
  final DateTime? lastSyncedAt;

  /// Tapping the avatar/name/status pill opens Pulse — matches the
  /// original AppBar title's own `onTap: _openPulse` (this was
  /// mistakenly re-pointed at chat insights during the pill redesign;
  /// insights is reached from the expand-chevron drawer's own explicit
  /// "Open Insights" affordance, a separate, correct path that this
  /// does not touch).
  final VoidCallback onTapHeader;

  final VoidCallback onBack;

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

    // No Hero: this header and the conversation row shared a
    // `tag: conversation.name`, flying a full-width preview row into a
    // 40pt avatar and title. Different shapes, so the flight distorted
    // both rather than reading as one element moving.
    //
    // Three SEPARATE floating pills, not one bar: back, avatar+name+
    // status, and the expand chevron each sit in their own rounded
    // surface with the wallpaper pattern showing through the gaps
    // between them — the same floating-pill language the composer
    // already uses on this screen (kComposerShadows, translucent
    // colorScheme.surface, fully rounded corners), not a new one.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _HeaderPill(
          padding: EdgeInsets.zero,
          child: IconButton(
            padding: EdgeInsets.zero,
            iconSize: 25,
            visualDensity: VisualDensity.standard,
            constraints: const BoxConstraints.tightFor(
              width: ComposerSatellite.size,
              height: ComposerSatellite.size,
            ),
            // BackButtonIcon: Flutter's own platform-adaptive glyph — a
            // chevron on iOS/macOS, the Material arrow elsewhere —
            // rather than a hardcoded Icons.arrow_back.
            icon: const BackButtonIcon(),
            onPressed: onBack,
          ),
        ),
        Gap(Spacing.sm.w),
        Expanded(
          child: _HeaderPill(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            onTap: onTapHeader,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Breathes a few times when the partner is here, then
                // settles to a static glow — a moment, not a
                // session-long loop.
                GlowPulse(
                  // Follows the partner, not the viewer's
                  // connectivity, so the avatar stops glowing
                  // permanently for everyone.
                  active: partnerActive,
                  child: ProfileAvatar(
                    avatarUrl: conversation.avatarUrl ?? '',
                    currentUserId: '',
                    size: 40.h,
                    enableHero: false,
                  ),
                ),
                Gap(Spacing.sm.w),
                Flexible(
                  child: RichText(
                    textAlign: TextAlign.left,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: conversation.name,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),

                        // "Online" here used to be driven by isOnline --
                        // the VIEWER's own connectivity -- so it read
                        // Online whenever you had a connection, whatever
                        // your partner was doing. It was decoration, not
                        // data.
                        //
                        // Now it reports whether the partner is in THIS
                        // conversation. Deliberately not a general online
                        // status: in a couples app that answers "they
                        // are on their phone and not replying to me",
                        // which starts arguments the app should not help
                        // start. Scoped here it says something kinder
                        // and true -- they are with you now -- and it is
                        // the only thing chat_presence actually
                        // measures.
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
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // more_vert removed: it duplicated the expand chevron's own
        // onToggleExpanded action rather than opening a distinct menu.
        if (expandedEnabled) ...[
          Gap(Spacing.sm.w),
          _HeaderPill(
            padding: EdgeInsets.zero,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 25,
              visualDensity: VisualDensity.standard,
              constraints: const BoxConstraints.tightFor(
                width: ComposerSatellite.size,
                height: ComposerSatellite.size,
              ),
              icon: Icon(
                isExpanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              onPressed: onToggleExpanded,
              tooltip: isExpanded ? 'Hide chat details' : 'Show chat details',
            ),
          ),
        ],
      ],
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({
    required this.child,
    required this.padding,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(999);
    // Paint the shadow outside the clipped Material so the tappable center
    // pill has the same visible depth as the two buttons.
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: kComposerShadows,
      ),
      child: Material(
        color: Theme.of(context).chatControlSurface,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? Padding(padding: padding, child: child)
            : InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
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

class _ReplyPayloadFlight extends StatelessWidget {
  const _ReplyPayloadFlight({
    required this.quotedText,
    required this.isMine,
    required this.replyingToLabel,
    required this.kind,
    this.gameType,
    required this.morphProgress,
  });

  final String quotedText;
  final bool isMine;
  final String replyingToLabel;
  final ReplyPreviewKind kind;
  final String? gameType;
  final double morphProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatColors = theme.chatColors;
    final morph = Curves.easeInOutCubic.transform(
      morphProgress.clamp(0.0, 1.0),
    );
    final bubbleColor =
        isMine ? chatColors.senderBubble : chatColors.receiverBubble;
    final onBubbleColor =
        isMine ? chatColors.onSenderBubble : chatColors.onReceiverBubble;
    final targetSurface =
        isMine ? chatColors.senderBubble : theme.colorScheme.surface;
    final targetForeground =
        isMine ? chatColors.onSenderBubble : theme.colorScheme.onSurface;
    final targetAccent =
        isMine ? chatColors.senderMetadata : theme.colorScheme.primary;
    final surface = Color.lerp(bubbleColor, targetSurface, morph)!;
    final foreground = Color.lerp(onBubbleColor, targetForeground, morph)!;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22 - (10 * morph)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(22 - (10 * morph)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08 + (0.03 * morph)),
              blurRadius: 6 + (2 * morph),
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding:
              EdgeInsets.lerp(
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                const EdgeInsets.fromLTRB(12, 8, 4, 8),
                morph,
              )!,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: (1 - (morph * 1.8)).clamp(0.0, 1.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    quotedText,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                ),
              ),
              Opacity(
                opacity: ((morph - 0.2) / 0.8).clamp(0.0, 1.0),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 38,
                      decoration: BoxDecoration(
                        color: targetAccent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (kind != ReplyPreviewKind.text) ...[
                      _ReplyFlightTypeIcon(kind: kind, gameType: gameType),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: RichText(
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'Replying to $replyingToLabel',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: targetAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: '\n$quotedText',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: foreground.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 36),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplyFlightTypeIcon extends StatelessWidget {
  const _ReplyFlightTypeIcon({required this.kind, this.gameType});

  final ReplyPreviewKind kind;
  final String? gameType;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final chatColors = Theme.of(context).chatColors;
    // Requested for this media chip: inverse of the surrounding background.
    // ignore: deprecated_member_use
    final adaptiveBackground = colors.onBackground;
    // ignore: deprecated_member_use
    final adaptiveForeground = colors.background;
    final resolvedGameType = gameType;
    final icon =
        kind == ReplyPreviewKind.game && resolvedGameType != null
            ? gameGlyphFor(resolvedGameType)
            : _fallbackIconFor(kind);
    final background =
        kind == ReplyPreviewKind.game && resolvedGameType != null
            ? GamePalette.of(resolvedGameType).end
            : adaptiveBackground;
    final foreground =
        kind == ReplyPreviewKind.game && resolvedGameType != null
            ? Colors.white
            : adaptiveForeground;

    if (kind == ReplyPreviewKind.streakOpened) {
      return SizedBox(
        width: 34,
        height: 34,
        child: Icon(
          Icons.check_box_outline_blank_rounded,
          size: 20,
          color: colors.onSurfaceVariant,
        ),
      );
    }

    if (kind == ReplyPreviewKind.audio) {
      return Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: chatColors.voiceAccent,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Color(0x18000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.play_arrow_rounded,
          size: 24,
          color: adaptiveForeground,
        ),
      );
    }

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: foreground),
    );
  }

  IconData _fallbackIconFor(ReplyPreviewKind kind) {
    switch (kind) {
      case ReplyPreviewKind.game:
        return Icons.sports_esports_outlined;
      case ReplyPreviewKind.image:
        return Icons.image_outlined;
      case ReplyPreviewKind.video:
        return Icons.videocam_outlined;
      case ReplyPreviewKind.audio:
        return Icons.play_arrow_rounded;
      case ReplyPreviewKind.streak:
        return Icons.play_arrow_rounded;
      case ReplyPreviewKind.streakOpened:
        return Icons.check_box_outline_blank_rounded;
      case ReplyPreviewKind.text:
        return Icons.chat_bubble_outline_rounded;
    }
  }
}

class _OutgoingTextFlight extends StatelessWidget {
  const _OutgoingTextFlight({required this.text, required this.progress});

  final String text;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final glyphs = emojiOnlyGlyphs(text);
    if (glyphs.isNotEmpty) {
      return FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: glyphs.length == 1 ? 68 : glyphs.length <= 3 ? 168 : 240,
          child: EmojiMessageContent(glyphs: glyphs, animate: false, replayOnVisibility: false),
        ),
      );
    }
    final theme = Theme.of(context);
    final chatColors = theme.chatColors;
    final surfaceProgress = Curves.easeOutCubic.transform(
      (progress / 0.42).clamp(0.0, 1.0),
    );
    final fill = Color.lerp(
      theme.colorScheme.surface.withValues(alpha: 0),
      chatColors.senderBubble,
      surfaceProgress,
    );
    final foreground = Color.lerp(
      theme.colorScheme.onSurface,
      chatColors.onSenderBubble,
      surfaceProgress,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1 * surfaceProgress),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              maxLines: 5,
              overflow: TextOverflow.fade,
              softWrap: true,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: foreground,
                fontSize: 18 - (2 * surfaceProgress),
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutgoingGameFlight extends StatelessWidget {
  const _OutgoingGameFlight({required this.gameType, required this.progress});

  final String gameType;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatColors = theme.chatColors;
    final morph = Curves.easeOutCubic.transform(
      (progress / 0.55).clamp(0.0, 1.0),
    );
    final foreground =
        Color.lerp(
          theme.colorScheme.onSurface,
          chatColors.onSenderBubble,
          morph,
        )!;
    final surface =
        Color.lerp(
          theme.colorScheme.surface.withValues(alpha: 0.94),
          chatColors.senderBubble,
          morph,
        )!;
    final palette = GamePalette.of(gameType);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20 + (4 * morph)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 7,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: palette.end,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                gameGlyphFor(gameType),
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gameTypeDisplayName(gameType),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Invite them to play',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: foreground.withValues(alpha: 0.65),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageList extends ConsumerStatefulWidget {
  const _MessageList({
    required this.conversation,
    required this.state,
    required this.scrollController,
    required this.animatedMessageIds,
    required this.messageKeys,
    required this.bubbleFillKeys,
    required this.reactionImpactTokens,
    required this.flyingMessageIds,
    required this.flyingGameSessionIds,
    required this.highlightedMessageId,
    required this.bottomOverlayHeight,
    required this.initialUnreadCount,
    required this.onScrollToLatest,
    required this.onReply,
    required this.onJumpToParent,
    required this.onReactionFlight,
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

  /// Owned by the screen State (survives list-item recycling); see its
  /// declaration for why a play-once ledger is required.
  final Set<String> animatedMessageIds;

  /// Owned by the screen State — see `_ChatScreenState._messageKeys` for why
  /// keys are registered fresh on every build rather than only-if-absent.
  final Map<String, GlobalKey> messageKeys;

  /// Exact fill targets for payload flights, keyed by stable client id.
  final Map<String, GlobalKey> bubbleFillKeys;

  /// Per-message revisions fired exactly when a reaction flight lands.
  final Map<String, int> reactionImpactTokens;

  /// Optimistic bubbles stay laid out but invisible while their visual
  /// payload is travelling toward them, enabling a seamless overlay handoff.
  final Set<String> flyingMessageIds;

  /// Server-created game messages are hidden by session id during their
  /// composer-to-bubble flight because they have no client optimistic id.
  final Set<String> flyingGameSessionIds;

  /// The message currently flashed as a jump target, or null.
  final String? highlightedMessageId;

  /// Measured height of everything stacked over the bottom of the list
  /// (typing indicator, reply strip, staged game, pause card, composer,
  /// home-indicator inset). The list pads itself by exactly this much so
  /// the newest bubble is always fully above the overlay (#33). Null until
  /// the first frame has measured it.
  final double? bottomOverlayHeight;

  /// conversation.unreadCount as it was when the screen opened — the
  /// one-shot "N unread messages" divider is placed from it, never from the
  /// live count (which drops to 0 as soon as the view is active).
  final int initialUnreadCount;

  /// Returns the list to the newest message (the pill's tap).
  final VoidCallback onScrollToLatest;

  /// Flies this message into the screen's reply-composer preview.
  final void Function(Message message) onReply;

  /// Jumps to and highlights a reply's parent message, given the current
  /// message list for the index-based fallback estimate.
  final Future<void> Function(String messageId, List<Message> currentMessages)
  onJumpToParent;

  final void Function(Message message, String emoji, Rect sourceRect)
  onReactionFlight;

  @override
  ConsumerState<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends ConsumerState<_MessageList>
    with TickerProviderStateMixin {
  static const _timestampReturnDuration = Duration(milliseconds: 220);
  /// Used only until the overlay has been measured (the first frame).
  static const _messageListBottomReserve = 120.0;

  /// Breathing room between the newest row and the top of the overlay.
  static const _messageListOverlayGap = 12.0;

  /// At the bottom a reserve change glides instead of snapping every row
  /// by the strip's height (a typing toggle is ~60px, many times a minute).
  static const _reserveGlideDuration = Duration(milliseconds: 220);
  late final AnimationController _reserveController;
  late double _reserveFrom;
  late double _reserveTo;

  /// The bottom padding painted this frame.
  double get _bottomReserve =>
      _reserveFrom +
      (_reserveTo - _reserveFrom) *
          Curves.easeOutCubic.transform(_reserveController.value);

  final ValueNotifier<double> _timestampRevealOffset = ValueNotifier(0);
  final Map<String, GlobalKey> _rowKeys = {};
  /// Pins the row being read while the list changes under it (#32).
  final ChatListAnchor _listAnchor = ChatListAnchor();
  final MessageArrivalTracker _arrivalTracker = MessageArrivalTracker();

  /// Cards that moved (sort_at advanced) get a fresh motion key so they
  /// settle into their new slot like an arrival; see GameMoveLedger.
  final GameMoveLedger _gameMoves = GameMoveLedger();
  final PendingArrivals _pendingArrivals = PendingArrivals();
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

  /// The reader has left the newest messages (more than a few bubbles up;
  /// WhatsApp shows its arrow early). Drives the scroll-to-newest pill.
  bool _awayFromBottom = false;
  static const _awayThreshold = 240.0;

  /// Partner messages that arrived while [_awayFromBottom]: the pill badge.
  int _unseenWhileAway = 0;
  bool _awayCheckScheduled = false;

  /// The one-shot "N unread messages" divider, placed once from the first
  /// server-backed page (and only moved further back as older history
  /// loads, while the first page held fewer rows than the count).
  UnreadDividerPlacement? _unreadDivider;
  bool _unreadDividerResolved = false;

  /// When this visit began — about when [_MessageList.initialUnreadCount]
  /// was counted. Rows the server stamped later are not part of it.
  final DateTime _openedAt = clock.now();
  List<Message>? _unreadDividerCheckedMessages;

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
    _reserveFrom = _reserveTo = _bottomPaddingFor(widget.bottomOverlayHeight);
    _reserveController = AnimationController(
      vsync: this,
      duration: _reserveGlideDuration,
      value: 1,
    )..addListener(_onReserveTick);
    _syncArrivals(widget.state);
    _attachListAnchor(widget.scrollController);
  }

  @override
  void didUpdateWidget(covariant _MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncArrivals(widget.state);
    if (oldWidget.scrollController != widget.scrollController) {
      _detachListAnchor(oldWidget.scrollController);
      _attachListAnchor(widget.scrollController);
    }
    if (!identical(oldWidget.state.messages, widget.state.messages)) {
      _armListAnchor();
      _scheduleAwayCheck();
    }
    _followReserveChange(oldWidget.bottomOverlayHeight);
    if (oldWidget.bottomOverlayHeight != widget.bottomOverlayHeight) {
      _scheduleAwayCheck();
    }
  }

  /// Whether the list is more than [_awayThreshold] from its newest end,
  /// read live from the position (null before it has laid out). Never from
  /// accumulated scroll deltas: the place hold (Task 9) and the reserve hold
  /// (Task 8) move pixels with correctPixels, which sends no notification.
  bool? _measureAwayFromBottom() {
    final controller = widget.scrollController;
    if (!controller.hasClients || controller.positions.length != 1) {
      return null;
    }
    final position = controller.position;
    if (!position.hasPixels || !position.hasContentDimensions) return null;
    return position.pixels - position.minScrollExtent > _awayThreshold;
  }

  /// Rebuilds only when the threshold is crossed, never per scroll tick.
  /// Back within it, the reader has seen what arrived: the badge clears.
  void _setAwayFromBottom(bool away) {
    if (away == _awayFromBottom) return;
    setState(() {
      _awayFromBottom = away;
      if (!away) _unseenWhileAway = 0;
    });
  }

  /// Re-reads [_awayFromBottom] after this frame's layout, where a hold may
  /// have moved the list without telling anyone.
  bool _loadMoreScheduled = false;

  /// Pages older history after the current frame/build, never inside it.
  /// A scroll notification can be dispatched mid-frame (a ballistic restart
  /// inside applyContentDimensions, a position hand-over while the tree
  /// builds); loadMoreMessages writes the controller's state synchronously,
  /// and doing that while the tree builds trips Riverpod's "modify a
  /// provider while the widget tree was building" assert. A microtask runs
  /// once the frame's callbacks return (and right away after a pointer
  /// event), and one burst of notifications schedules one call.
  void _scheduleLoadMore() {
    if (_loadMoreScheduled) return;
    _loadMoreScheduled = true;
    scheduleMicrotask(() {
      _loadMoreScheduled = false;
      if (!mounted) return;
      ref
          .read(chatControllerProvider(widget.conversation).notifier)
          .loadMoreMessages();
    });
  }

  void _scheduleAwayCheck() {
    if (_awayCheckScheduled) return;
    _awayCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _awayCheckScheduled = false;
      if (!mounted) return;
      final away = _measureAwayFromBottom();
      if (away != null) _setAwayFromBottom(away);
    });
  }

  /// Whether the list sits at its newest end (or has not laid out yet).
  /// Read live: rows are built lazily, during layout, as the list scrolls.
  bool _atNewestEnd() {
    final controller = widget.scrollController;
    if (!controller.hasClients || controller.positions.length != 1) {
      return true;
    }
    final position = controller.position;
    return !position.hasPixels ||
        !position.hasContentDimensions ||
        position.pixels <= position.minScrollExtent + 1;
  }

  void _attachListAnchor(ScrollController controller) {
    if (controller is ChatListScrollController) {
      controller.layoutCorrection = _listAnchor.consume;
      controller.pinRowBeingRead = _pinRowBeingRead;
      controller.rowPinned = _isRowPinned;
    }
  }

  void _detachListAnchor(ScrollController controller) {
    if (controller is ChatListScrollController &&
        controller.layoutCorrection == _listAnchor.consume) {
      controller.layoutCorrection = null;
      controller.pinRowBeingRead = null;
      controller.rowPinned = null;
    }
  }

  bool _isRowPinned() => _listAnchor.isArmed;

  /// Asked by the list's position at the start of every layout: while
  /// scrolled up, pin the row being read so any
  /// content shift under it — Flutter's own origin repair included, which
  /// moves the content by more than the offset — is cancelled in the same
  /// layout. Already pinned (an arrival this frame, pinned at build, before
  /// the sliver re-targets its rows): keep that pin. At the newest end:
  /// nothing to hold, new rows push the list up.
  bool _pinRowBeingRead() {
    if (_listAnchor.isArmed) return true;
    if (_atNewestEnd()) return false;
    if (!_armAmongBuiltRows()) return false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _listAnchor.clear());
    return true;
  }

  /// Scrolled up, pins the bottom-most visible row before this frame's
  /// change (an arrival, a reorder) is laid out, and the list's position
  /// cancels whatever that change moved it by in the same layout pass — so
  /// the text being read never moves. At the bottom nothing is pinned: a new
  /// message still pushes the list up into view, as before.
  ///
  /// Measured in CONTENT offsets, so it composes with
  /// [_followReserveChange]'s padding hold (padding sits outside the row
  /// offsets) and never undoes the reader's own scroll. Unpinned after the
  /// frame, so a change that never reaches layout cannot linger.
  ///
  /// A running animateTo / ensureVisible writes absolute pixels on every
  /// tick and would overwrite the hold on its next one. The controller
  /// carries it across the hold (and across Flutter's later correctBy of
  /// the content origin): toward the newest end it still lands there, on
  /// time; toward a row it moves with the content and lands on that row.
  void _armListAnchor() {
    if (widget.scrollController is! ChatListScrollController) return;
    if (_atNewestEnd()) {
      _listAnchor.clear();
      return;
    }
    if (_armAmongBuiltRows()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _listAnchor.clear());
    }
  }

  /// The list's sliver element, found once and kept while it is mounted.
  SliverMultiBoxAdaptorElement? _listElement;

  /// Pins among the rows the list has BUILT (a screenful), not every loaded
  /// one — after a far jump that is thousands, on every layout while
  /// scrolled up. Before the list has laid out, every loaded row (cheap:
  /// nothing is built yet, so each lookup misses at once).
  bool _armAmongBuiltRows() {
    final controller = widget.scrollController;
    var list = _listElement;
    if (list == null || !list.mounted) {
      list = _listElement =
          controller.hasClients && controller.positions.length == 1
              ? ChatListAnchor.findListElement(controller.position)
              : null;
    }
    if (list == null) return _listAnchor.arm(_rowKeys.values);
    return _listAnchor.armAmongBuilt(list, (rowKey) {
      if (rowKey is! ValueKey<String>) return null;
      final value = rowKey.value;
      if (!value.startsWith('row-')) return null;
      return _rowKeys[value.substring(4)];
    });
  }

  void _onReserveTick() {
    if (mounted) setState(() {});
  }

  /// List bottom padding for a measured overlay height (the fallback guess
  /// only until the first measurement lands; a measured 0 is honoured).
  static double _bottomPaddingFor(double? bottomOverlayHeight) =>
      bottomOverlayHeight == null
          ? _messageListBottomReserve
          : bottomOverlayHeight + _messageListOverlayGap;

  /// Moves the list's bottom reserve to the new measurement.
  ///
  /// The list is reversed, so a bigger reserve pushes every row up.
  /// - At the bottom that is exactly right (the newest message stays fully
  ///   above the grown overlay), and it GLIDES there over
  ///   [_reserveGlideDuration] rather than hopping in one frame. A new
  ///   measurement mid-glide retargets from the value painted now, so two
  ///   strips arriving together never jump. Reduce motion, and the very
  ///   first measurement, snap.
  /// - Scrolled up into history it would shift the page under the reader,
  ///   so the reserve snaps and the offset moves by the same amount: the
  ///   rows stay put. correctPixels (not jumpTo) leaves a drag running, and
  ///   a fling survives because the extent change restarts its simulation
  ///   from the corrected offset. A running animateTo / ensureVisible
  ///   follows the hold (the controller carries it, as for any correction):
  ///   no hop on its next tick, and it still lands on its target.
  void _followReserveChange(double? oldOverlayHeight) {
    if (oldOverlayHeight == widget.bottomOverlayHeight) return;
    final target = _bottomPaddingFor(widget.bottomOverlayHeight);
    final current = _bottomReserve;
    final controller = widget.scrollController;
    final position =
        controller.hasClients &&
                controller.positions.length == 1 &&
                controller.position.hasPixels &&
                controller.position.hasContentDimensions
            ? controller.position
            : null;
    final atBottom =
        position == null || position.pixels <= position.minScrollExtent + 1;

    if (atBottom &&
        oldOverlayHeight != null &&
        target != current &&
        !reduceMotionOf(context)) {
      _reserveFrom = current;
      _reserveTo = target;
      _reserveController.forward(from: 0);
      return;
    }

    _reserveController.stop();
    _reserveFrom = _reserveTo = target;
    if (position != null && !atBottom) {
      final held = math.max(
        position.minScrollExtent,
        position.pixels + target - current,
      );
      if (controller is ChatListScrollController) {
        controller.correctPixelsCarryingDrive(held);
      } else {
        position.correctPixels(held);
      }
    }
  }

  void _syncArrivals(ChatState state) {
    // Copy: the tracker returns a const set on its baseline frames.
    final arrivals = <String>{
      ..._arrivalTracker.sync(
        state.messages.map((message) => message.clientMessageId),
        initialLoading: state.isLoading,
        loadingMore: state.isLoadingMore,
      ),
    };
    // A trail is a marker of where a card WAS (leave_game_trail inserts a
    // new row at the card's old sort_at). It is never an arrival: it used
    // to slide/fade in twenty messages up, where nobody was looking.
    for (final message in state.messages) {
      if (message.isGameTrail && arrivals.remove(message.clientMessageId)) {
        widget.animatedMessageIds.add(message.clientMessageId);
      }
    }
    // A moved card re-arrives at its new slot. Runs on every frame (baseline
    // and history pages too) so the ledger always holds the latest slot.
    // It animates like an arrival but stays out of `arrivals`, which the
    // unseen-count block below reads: a move re-sorts an existing card —
    // activity, not a new message — so neither the badge nor the divider
    // counts it, and the pill must not either (final review M-2). A new
    // invite card is a genuine tracker arrival and still counts.
    final moved = _gameMoves.sync(state.messages);
    for (final id in moved) {
      widget.animatedMessageIds.remove(id);
    }
    _pendingArrivals.add({...arrivals, ...moved}, clock.now());

    // --- Task 10: unseen-count block (#32b) ---
    // Genuine arrivals only (the tracker drops history pages, and edits or
    // reactions keep their client id, so they are never arrivals); my own
    // rows never count. Read live: the reader's place before this change.
    // Runs from didUpdateWidget, so the build that follows paints it.
    if (arrivals.isNotEmpty &&
        (_measureAwayFromBottom() ?? _awayFromBottom)) {
      for (final message in state.messages) {
        if (arrivals.contains(message.clientMessageId) &&
            countsTowardUnread(message)) {
          _unseenWhileAway++;
        }
      }
    }
    // --- end Task 10 unseen-count block ---
  }

  /// Stable per row, fresh per game move. Revision 0 keeps the plain
  /// client-id key every existing test and flight lookup relies on.
  Key _motionKey(String clientMessageId, String slot) {
    final revision = _gameMoves.revisionOf(clientMessageId);
    if (revision == 0) {
      return slot == 'settle'
          ? ValueKey(clientMessageId)
          : ValueKey('$slot:$clientMessageId');
    }
    return ValueKey('$slot:$clientMessageId#move$revision');
  }

  /// Places the unread divider once a server page of the newest messages
  /// has landed ([ChatState.firstPageLanded]: a warm cache painted before it
  /// may not hold the unread rows yet, and counting from it would put the
  /// divider on read messages). On a late placement only
  /// ([ChatState.firstPageLate]: an offline open, then a reconnect) rows
  /// sent after the open are skipped, so it still marks the rows that were
  /// unread at the open. After that it stays put for the
  /// visit; a placement the first page could not complete only moves
  /// further back, as older history loads.
  void _resolveUnreadDivider(ChatState state) {
    if (state.isLoading || !state.firstPageLanded) return;
    if (identical(state.messages, _unreadDividerCheckedMessages)) return;
    _unreadDividerCheckedMessages = state.messages;
    final before = _unreadDivider;
    if (!_unreadDividerResolved) {
      _unreadDividerResolved = true;
      _unreadDivider = placeUnreadDivider(
        state.messages,
        widget.initialUnreadCount,
        // Only a late page can hold rows sent after the open. A normal
        // open's first page is already a snapshot taken after the count,
        // and comparing server stamps with this phone's clock would drop
        // unread rows whenever the clock runs behind the server's.
        sentBy: state.firstPageLate ? _openedAt : null,
      );
    } else if (before != null && before.unplaced > 0) {
      _unreadDivider = extendUnreadDivider(state.messages, before);
    }
    // Inserting (or moving) the divider changes a row's height: pin the
    // row being read, as for any other list change (no-op at the bottom).
    if (_unreadDivider?.messageId != before?.messageId) _armListAnchor();
  }

  @override
  void dispose() {
    _timestampReturnAnimation?.removeListener(_onTimestampReturnTick);
    _timestampReturnController.dispose();
    _reserveController.dispose();
    _detachListAnchor(widget.scrollController);
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

  // Spec 7 (B1): keep a received "I noticed…" note, or let it go.
  Future<void> _keepNote(BuildContext context, String messageId, bool keep) async {
    final service = ref.read(appreciationServiceProvider);
    try {
      if (keep) {
        await service.save(messageId);
      } else {
        await service.remove(messageId);
      }
      ref.invalidate(appreciationJarIdsProvider);
      ref.invalidate(appreciationJarProvider);
      if (context.mounted) {
        context.showSuccessSnackbar(
          keep ? 'Saved to your jar' : 'Removed from your jar',
        );
      }
    } catch (_) {
      if (context.mounted) context.showErrorSnackbar("Couldn't do that. Try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversation = widget.conversation;
    final state = widget.state;
    final scrollController = widget.scrollController;
    final animatedMessageIds = widget.animatedMessageIds;
    final messageKeys = widget.messageKeys;
    final bubbleFillKeys = widget.bubbleFillKeys;
    final highlightedMessageId = widget.highlightedMessageId;
    final onReply = widget.onReply;
    final onJumpToParent = widget.onJumpToParent;

    // Chat feel preference (Spec §1.1 tone floor, §3.7): expressive turns the
    // shimmer sweep and reconnect cascade up slightly; calm (default) keeps
    // both a whisper-subtle. Content-blind — only the enum is read here.
    final expressive =
        ref.watch(chatExpressivenessProvider) == ChatExpressiveness.expressive;
    // Spec 7 (A9): nothing sparkles while the person is quiet.
    final quiet = ref.watch(isQuietProvider);
    // Spec 7 (B1): which received notes this person kept.
    final appreciationOn =
        ref.watch(appreciationEnabledProvider).valueOrNull ?? false;
    // Spec 8 (B3 (a)): the reply chip under a received pause.
    final toolkitOn =
        ref.watch(conflictToolkitEnabledProvider).valueOrNull ?? false;
    final jarIds =
        appreciationOn
            ? ref.watch(appreciationJarIdsProvider).valueOrNull ??
                const <String>{}
            : const <String>{};

    // RULING 23: §12's `ai_assist_enabled`, which gates the long-press
    // "Ask Attune" entry point. Nothing gated it before — Task 5
    // confirmed that across all 16 `ChatFeatureFlags.` call sites, and
    // it is the BASE spec's own recorded finding rather than something
    // Plan D introduced.
    //
    // Read through Task 5's capability service, NEVER `feature_flags`:
    // that table's SELECT policy hides every `ai_%` key from clients
    // (migration 20260953200000), so a direct read returns no row and
    // the flag would be false forever whatever an operator sets (PF2).
    //
    // `.valueOrNull?.assist == true` matches `translatorEnabled`'s own
    // `.valueOrNull == true` shape at the composer site: loading reads
    // as OFF, which is where §12's "defaults off" points. The
    // capability is OFF in every environment today, so this is
    // `false` — the ONE behavioural change this task makes with the
    // flags as they ship, and it closes a gap rather than opening one.
    final assistEnabled =
        ref.watch(aiSessionCapabilitiesProvider).valueOrNull?.assist == true;

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
      // An empty chat greets the partner and shows what the chat can do,
      // one card per feature that is switched on. Gone with the first
      // message.
      // Cards wait for the feature flags, so they appear together rather
      // than the always-on ones first and the rest a moment later.
      final flags = ref.watch(documentationFlagsProvider).valueOrNull;
      return ChatEmptyState(
        // The partner's profile name (the same source "Replying to" uses),
        // then the conversation's; never the "Partner" placeholder.
        partnerName:
            realPartnerName(ref.watch(gamePartnerNameProvider).valueOrNull) ??
            realPartnerName(state.conversation.partnerName),
        modules: flags == null ? const [] : chatEmptyStateModules(flags),
        bottomInset: _bottomReserve,
      );
    }

    // Prune keys for messages no longer in state.messages (scrolled-out
    // history that got dropped, or a pagination/reload replacing the list)
    // — without this, messageKeys only ever grows across the screen's
    // lifetime, leaking GlobalKeys and skewing _nearestBuiltRow's walk
    // (the jump's anchored extrapolation) over every key ever built.
    final currentIds = state.messages.map((m) => m.id).toSet();
    final currentClientIds =
        state.messages.map((m) => m.clientMessageId).toSet();
    messageKeys.removeWhere((id, _) => !currentIds.contains(id));
    bubbleFillKeys.removeWhere(
      (clientId, _) => !currentClientIds.contains(clientId),
    );
    _rowKeys.removeWhere((id, _) => !currentIds.contains(id));
    final mediaRuns = ChatMediaRunLayout.fromMessages(state.messages);
    // Key → index map for findChildIndexCallback, so the sliver matches a
    // row by WHICH message it is, not by its position. Without it an
    // arrival at index 0 re-targets every element one message over and each
    // row is rebuilt into its neighbour's slot (#32). Keeping rows put on
    // screen is the place hold's job (_armListAnchor); this keeps each
    // row's element and render object with its message.
    final indexByRowKey = <String, int>{
      for (var i = 0; i < state.messages.length; i++)
        'row-${state.messages[i].id}': i,
    };
    final pinnedLabel = _pinnedDateLabel;
    _resolveUnreadDivider(state);
    final unreadDividerId = _unreadDivider?.messageId;
    final firstOwnIndex = state.messages.indexWhere((m) => m.isMine);

    return Stack(
      children: [
        Listener(
          onPointerUp: (_) => _closeTimestampReveal(),
          onPointerCancel: (_) => _closeTimestampReveal(),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.pixels >=
                  notification.metrics.maxScrollExtent - 200) {
                _scheduleLoadMore();
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
              // The pill: the list's own notifications only (depth 0, not
              // a scrollable inside a row). One can be dispatched
              // mid-layout (a ballistic restart inside
              // applyContentDimensions); then it is read after the frame
              // rather than setState during layout.
              if (notification.depth == 0) {
                if (WidgetsBinding.instance.schedulerPhase ==
                    SchedulerPhase.persistentCallbacks) {
                  _scheduleAwayCheck();
                } else {
                  _setAwayFromBottom(
                    notification.metrics.pixels -
                            notification.metrics.minScrollExtent >
                        _awayThreshold,
                  );
                }
              }
              return false;
            },
            child: Scrollbar(
              controller: scrollController,
              child: ListView.builder(
                controller: scrollController,
                reverse: true,
                // Reserves room so the newest message doesn't sit behind the
                // floating overlay Positioned on top of this list (typing
                // indicator, reply strip, staged game, composer, safe area).
                // The reserve is that overlay's MEASURED height plus a gap,
                // so it follows every strip and a growing multi-line draft
                // (#33). It already rides above the keyboard (the Scaffold
                // resizes its body), so viewInsets are never added here.
                // No horizontal inset on the LIST: the date separator's
                // rule has to reach both screen edges, and a list-level
                // padding clips it however wide the row asks to be. The
                // 8px moves onto the message rows themselves, which are
                // the only children that wanted it.
                padding: EdgeInsets.fromLTRB(
                  0,
                  10,
                  0,
                  _bottomReserve,
                ),
                itemCount:
                    state.messages.length + (state.isLoadingMore ? 1 : 0),
                findChildIndexCallback: (key) {
                  if (key is ValueKey<String>) return indexByRowKey[key.value];
                  return null;
                },
                itemBuilder: (context, index) {
                  if (index == state.messages.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (mediaRuns.hiddenIndices.contains(index)) {
                    return KeyedSubtree(
                      key: ValueKey<String>('row-${state.messages[index].id}'),
                      child: const SizedBox.shrink(),
                    );
                  }

                  final message = state.messages[index];
                  final bubbleFillKey = bubbleFillKeys.putIfAbsent(
                    message.clientMessageId,
                    GlobalKey.new,
                  );
                  final mediaGroup = mediaRuns.runs[index] ?? const <Message>[];
                  // Keep the rendered row stable while timestamp drag updates
                  // rebuild the visible list. Replacing this key on every pointer
                  // delta disposes the active GestureDetector mid-gesture, making
                  // the reveal stop after its first movement.
                  final messageKey = _rowKeys.putIfAbsent(
                    message.id,
                    GlobalKey.new,
                  );
                  // Top-level row key read back by findChildIndexCallback;
                  // messageKey stays the ensureVisible target inside it.
                  final rowKey = ValueKey<String>('row-${message.id}');
                  messageKeys[message.id] = messageKey;
                  for (final groupedMessage in mediaGroup) {
                    messageKeys[groupedMessage.id] = messageKey;
                  }
                  // A bubble is "first of its day" if its local date differs from the
                  // next-older message's local date (list is newest-first). Only
                  // genuinely-new first-of-day messages shimmer — cached history on
                  // open does not. Content-blind: only dates are compared.
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
                  // Arrival detection is identity-based, not timestamp-based: delayed
                  // delivery and server/device clock skew must not suppress the
                  // receiver animation. Pagination is filtered by the tracker.
                  final shouldAnimate =
                      _pendingArrivals.take(message.clientMessageId, clock.now()) &&
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

                  // #37: "Copy link" is offered only when the text has a web
                  // link; it copies the first one ("Copy" keeps the whole text).
                  final messageLinks = detectLinks(message.content);
                  final firstLink =
                      messageLinks.isEmpty ? null : messageLinks.first;

                  Widget bubble = MessageBubble(
                          message: message,
                          // RULING 23: §12's `ai_assist_enabled`, the
                          // base spec's own missing gate on Ask
                          // Attune. Read here, at the one site that
                          // already resolves every other chat
                          // capability from a provider, so
                          // `MessageBubble` stays the deliberate
                          // `StatelessWidget` it is.
                          assistEnabled: assistEnabled,
                          animateEmojiArrival: shouldAnimate || index == 0,
                          emojiPlaybackEnabled: !widget.flyingMessageIds.contains(message.clientMessageId),
                          bubbleFillKey: bubbleFillKey,
                          reactionImpactToken:
                              widget.reactionImpactTokens[message
                                  .clientMessageId] ??
                              0,
                          mediaGroup: mediaGroup,
                          conversation: conversation,
                          showStatus: showsDeliveryStatus(
                            isMine: message.isMine,
                            isNewestOwn: index == firstOwnIndex,
                            isGroupEnd: !isGroupedWithPrevious,
                            status: message.status,
                          ),
                          showLatestTimestamp: index == 0,
                          showTimestamp: true,
                          timestampRevealListenable: _timestampRevealOffset,
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
                          onGameTap: (gameType, sessionId, autoAccept) {
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
                                sessionId: sessionId,
                                autoAccept: autoAccept,
                              ),
                            );
                          },
                          onCancelSend:
                              (toCancel) => ref
                                  .read(
                                    chatControllerProvider(
                                      conversation,
                                    ).notifier,
                                  )
                                  .cancelSend(toCancel),
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
                          // Retry on a read-only chat can only fail again;
                          // Remove stays.
                          onRetry:
                              message.isFailed && state.conversation.canSend
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
                                  ? () => onReply(message)
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
                          viewerUserId: ref.read(currentUserProvider)?.id,
                          isStarred: state.starredMessageIds.contains(
                            message.id,
                          ),
                          isPinned: state.pinnedMessages.any(
                            (p) => p.id == message.id,
                          ),
                          isInJar: jarIds.contains(message.id),
                          onSaveToJar:
                              appreciationOn
                                  ? () => _keepNote(context, message.id, true)
                                  : null,
                          onRemoveFromJar:
                              appreciationOn
                                  ? () => _keepNote(context, message.id, false)
                                  : null,
                          parentDeleted: parentDeleted,
                          onCopy: () {
                            Clipboard.setData(
                              ClipboardData(text: message.content),
                            );
                            context.showSuccessSnackbar('Copied to clipboard');
                          },
                          onCopyLink:
                              firstLink == null
                                  ? null
                                  : () {
                                    Clipboard.setData(
                                      ClipboardData(text: firstLink.copyText),
                                    );
                                    context.showSuccessSnackbar('Link copied');
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
                          onReactionFlight:
                              (emoji, sourceRect) => widget.onReactionFlight(
                                message,
                                emoji,
                                sourceRect,
                              ),
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
                  );
                  if (widget.flyingMessageIds.contains(
                        message.clientMessageId,
                      ) ||
                      (message.gameSessionId != null &&
                          widget.flyingGameSessionIds.contains(
                            message.gameSessionId,
                          ))) {
                    bubble = Opacity(opacity: 0, child: bubble);
                  }
                  if (toolkitOn &&
                      state.conversation.canSend &&
                      mayOfferPauseReply(message, DateTime.now())) {
                    bubble = Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        bubble,
                        PauseReplyChip(pauseMessageId: message.id),
                      ],
                    );
                  }
                  if (isFirstOfDay && shouldAnimate && !quiet) {
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
                  // history always uses the base duration.
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
                      // Only at the newest end (#32): scrolled up, the row
                      // lands at full height in one frame, so the place
                      // hold cancels it whole, and a row first built later
                      // as the reader scrolls back cannot lift the rows
                      // above it while it grows.
                      child: MakeRoom(
                        // Fresh per game move: both decide "animate or not"
                        // once per State, so a moved card needs a new one.
                        key: _motionKey(message.clientMessageId, 'room'),
                        animate: shouldAnimate && _atNewestEnd(),
                        child: SettleIn(
                          key: _motionKey(message.clientMessageId, 'settle'),
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

                  // The unread divider sits directly above its row (a media
                  // run draws as its newest member, so match any of it).
                  final showsUnreadDivider =
                      unreadDividerId != null &&
                      (message.id == unreadDividerId ||
                          mediaGroup.any((m) => m.id == unreadDividerId));
                  if (!isFirstOfDay && !showsUnreadDivider) {
                    return KeyedSubtree(key: rowKey, child: row);
                  }

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
                  return KeyedSubtree(
                    key: rowKey,
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isFirstOfDay)
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
                      // Below the day's separator: it must sit immediately
                      // above the first unread row.
                      if (showsUnreadDivider)
                        UnreadDivider(count: widget.initialUnreadCount),
                      row,
                    ],
                    ),
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
        // Rides the same measured overlay height as the list's reserve
        // (Task 8), so the typing indicator, reply strip and staged game
        // bar push it up rather than cover it. Inside the list's column,
        // so on an iPad it sits at the conversation's edge.
        // The pill's 48 px hit box has a 2 px margin round its 44 px
        // circle: the circle keeps a 16 px inset and the 12 px gap.
        PositionedDirectional(
          end: 14,
          bottom:
              (widget.bottomOverlayHeight ?? _messageListBottomReserve) +
              _messageListOverlayGap -
              2,
          child: ScrollToLatestPill(
            key: const ValueKey('chat_scroll_to_latest'),
            visible: _awayFromBottom,
            count: _unseenWhileAway,
            onTap: () {
              ref.read(hapticsProvider).selection();
              widget.onScrollToLatest();
            },
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
            inputFormatters: [
              RuneLengthLimitingTextInputFormatter(
                Message.maxContentRunes,
                onTruncated:
                    () => dialogContext.showWarningSnackbar(
                      overLimitPasteNotice(),
                    ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final edited = controller.text.trim();
                // Programmatic or pre-existing over-limit text: keep the
                // dialog open with the text intact rather than failing later.
                if (edited.isNotEmpty && !Message.isValidContent(edited)) {
                  dialogContext.showErrorSnackbar(tooLongMessageNotice());
                  return;
                }
                Navigator.of(dialogContext).pop(edited);
              },
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
                      MyDateFormat.join([
                        MyDateFormat.toDate(entry.editedAt),
                        MyDateFormat.toTime(entry.editedAt),
                      ]),
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
                                  ? (message.isMine
                                      ? 'You deleted this message'
                                      : 'This message was deleted')
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
  const _TypingIndicatorBubble({super.key});

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
Future<void> showChatGamesPicker(
  BuildContext context, {
  required String relationshipId,

  /// Called when a NEW game is picked from the catalogue, with the game
  /// type to stage in the composer. Absent for callers with no composer
  /// (the sheet then opens the game directly, as it always did).
  void Function(String gameType)? onStageNewGame,
}) async {
  await BottomSheetUtils.showDocumentationBottomSheet<void>(
    context: context,
    backgroundColor: Color(0xFF0B0B0F),
    maxHeight: MediaQuery.sizeOf(context).height * 0.86,
    padding: Spacing.md,
    widget: ChatGamesSheet(
      onSelect: (destination) {
        Navigator.of(context).pop();
        unawaited(
          openGameRoute(context, destination, relationshipId: relationshipId),
        );
      },
      // A new game is staged, not started. The sheet closes and the
      // composer shows the card that is about to be sent, so backing out
      // costs nothing -- picking a game used to create the session and
      // post a card the moment it was tapped.
      onStageNewGame:
          onStageNewGame == null
              ? null
              : (destination) {
                final gameType = chatGameTypeForDestination(destination);
                Navigator.of(context).pop();
                // Only games the server will actually create from a bare
                // session row are staged. The rest open their own screen,
                // which is where their setup happens -- staging them
                // would be a Send that always fails.
                if (gameType != null &&
                    kInvitableGameTypes.contains(gameType)) {
                  onStageNewGame(gameType);
                } else {
                  // Prototypes have no game type and so no invitation:
                  // they are pass-and-play on one device.
                  unawaited(
                    openGameRoute(
                      context,
                      destination,
                      relationshipId: relationshipId,
                    ),
                  );
                }
              },
      onOpenPaintBallSession: (sessionId) {
        Navigator.of(context).pop();
        unawaited(
          _openPaintBallRecap(
            context,
            sessionId: sessionId,
            relationshipId: relationshipId,
          ),
        );
      },
    ),
  );
}

Future<void> _openPaintBallRecap(
  BuildContext context, {
  required String sessionId,
  required String relationshipId,
}) async {
  final action = await context.pushNamed<PaintBallExitAction>(
    'paintBallKnockout',
    pathParameters: {'sessionId': sessionId},
  );
  if (!context.mounted) return;
  await _handlePaintBallExit(
    context,
    action: action,
    relationshipId: relationshipId,
  );
}

Future<void> _handlePaintBallExit(
  BuildContext context, {
  required PaintBallExitAction? action,
  required String relationshipId,
}) async {
  if (action == PaintBallExitAction.openGames) {
    await showChatGamesPicker(context, relationshipId: relationshipId);
    return;
  }
  if (action != PaintBallExitAction.playAgain) return;

  final nextAction = await context.pushNamed<PaintBallExitAction>(
    'paintBallLobby',
    pathParameters: {'relationshipId': relationshipId},
  );
  if (!context.mounted) return;
  await _handlePaintBallExit(
    context,
    action: nextAction,
    relationshipId: relationshipId,
  );
}

Future<void> openGameRoute(
  BuildContext context,
  ChatGameDestination destination, {
  required String relationshipId,

  /// The session a chat card refers to. Null when the picker opened this,
  /// because starting a game from the hub has no session yet.
  String? sessionId,

  /// Accept [sessionId] before opening, so tapping an invitation someone
  /// sent you lands on the board rather than a screen asking whether you
  /// meant it. Only ever true from a card, and only for an invitation the
  /// viewer did not send -- see GameMessageBubble.
  bool autoAccept = false,
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
    case ChatGameDestination.snakesAndLadders:
      // Straight to the board, whatever state the game is in. It shows
      // the invitation, the wait, the turn or the result itself -- there
      // is no lobby left to route through, and autoAccept is not needed
      // because the board asks before joining a game you did not start.
      await context.pushNamed(
        'snakesGame',
        pathParameters: {'relationshipId': relationshipId},
        queryParameters: {if (sessionId != null) 'session': sessionId},
      );
    case ChatGameDestination.wordHunt:
      // Straight to the hunt, like Snakes. It shows the invitation, the
      // start gate, the grid or the reveal itself.
      await context.pushNamed(
        'wordHuntGame',
        pathParameters: {'relationshipId': relationshipId},
        queryParameters: {if (sessionId != null) 'session': sessionId},
      );
    // Prototypes take no relationship: they are pass-and-play on one
    // device, with no session, no server and no partner.
    case ChatGameDestination.dotsAndBoxesPrototype:
      await context.pushNamed('dotsBoxesPrototype');
    case ChatGameDestination.constellationPrototype:
      await context.pushNamed('constellationPrototype');
    case ChatGameDestination.paintBall:
      final action = await context.pushNamed<PaintBallExitAction>(
        'paintBallLobby',
        pathParameters: {'relationshipId': relationshipId},
      );
      if (!context.mounted) return;
      await _handlePaintBallExit(
        context,
        action: action,
        relationshipId: relationshipId,
      );
  }
}
