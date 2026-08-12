import 'dart:async';

import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/ui/motion/glow_pulse.dart';
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/settle_in.dart';
import 'package:attune/core/ui/motion/shimmer.dart';
import 'package:attune/core/ui/presence/breathing_dots.dart';
import 'package:attune/core/utils/animations/animated_scale_fade.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/services/chat_image_preparer.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/state/typing_controller.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:attune/features/conflict_translator/data/models/translator_request.dart';
import 'package:attune/features/conflict_translator/presentation/providers/translator_providers.dart'
    as translator_providers;
import 'package:attune/features/conflict_translator/presentation/screens/translator_sheet.dart';
import 'package:attune/features/settings/data/chat_feel_preference.dart';
import 'package:attune/features/settings/data/sound_preference.dart';
import 'package:attune/core/services/media/image_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePickerService();
  final DateTime _messageListCutoff = DateTime.now();
  // Once-per-message animation ledger: ListView.builder recycles item State
  // when a bubble scrolls out of cacheExtent, so a time-based `isNew` alone
  // would replay SettleIn/Shimmer every time a new message scrolls back into
  // view. IDs recorded here animate exactly once per screen lifetime.
  final Set<String> _animatedMessageIds = <String>{};
  bool _headerExpanded = false;
  bool _isForeground = true;

  /// Reply target set by swiping a message — mirrors
  /// DebateRoomScreen._replyToPostId/_replyToQuotedText exactly. Null means
  /// no reply is pending; the quoted-preview strip above the composer only
  /// renders when this is non-null.
  String? _replyToMessageId;
  String? _replyToQuotedText;

  /// One GlobalKey per message, registered fresh on every build (never
  /// only-if-absent, so a key never survives past the message it was
  /// created for) — mirrors DebateRoomScreen._postKeys, adapted from that
  /// screen's SliverList to this screen's ListView.builder. Used by
  /// _jumpToMessage to scroll a currently-built message into view.
  final Map<String, GlobalKey> _messageKeys = {};

  /// The message currently flashed as a jump target, and a timer to clear
  /// the flash — mirrors DebateRoomScreen._highlightedPostId/_highlightTimer.
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onDraftChanged);
    Future.microtask(_restoreDraft);
    // Mark the view active once the first frame has rendered so read receipts
    // are only sent when the conversation is visible, foregrounded, and the
    // message list has drawn (Spec 6.4).
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncViewActive());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onDraftChanged);
    _controller.dispose();
    _scrollController.dispose();
    _highlightTimer?.cancel();
    super.dispose();
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

    // Enforce the private-image upload contract (Spec 8.1) before touching the
    // send path: sniff MIME from bytes, strip EXIF/location, resize, and keep
    // the output under the size ceiling. Rejects hostile/oversized files with a
    // safe, content-free reason.
    final PreparedChatImage prepared;
    try {
      prepared = await const ChatImagePreparer().prepare(picked.path);
    } on ChatImageRejected catch (rejected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_imageRejectionMessage(rejected.code))),
      );
      return;
    }
    if (!mounted) return;

    final caption = _controller.text;
    _controller.clear();
    await _clearDraft();
    // sendImageMessage has no replyToMessageId/quotedText params (image
    // replies are out of scope), so any pending reply target would silently
    // survive this send and get attached to the NEXT text message instead —
    // clear it here so the "Replying to..." strip never outlives the reply
    // it was showing.
    _clearReplyTarget();
    await ref
        .read(chatControllerProvider(widget.conversation).notifier)
        .sendImageMessage(
          localPath: prepared.file.path,
          mimeType: prepared.mimeType,
          caption: caption,
        );
    _scrollToLatest();
  }

  String _imageRejectionMessage(String code) {
    switch (code) {
      case 'media_type_unsupported':
        return 'That file type is not supported. Choose a JP, PNG, or WebP image.';
      case 'media_too_large':
      case 'media_compress_failed':
        return 'That image is too large to send. Try a smaller one.';
      case 'media_decode_failed':
      case 'media_dimensions_excessive':
        return 'That image could not be read. Try a different one.';
      default:
        return 'That image is no longer available.';
    }
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
        partnerName: widget.conversation.name,
      ),
    );
    _syncViewActive();
  }

  Future<void> _openHistoricalImport() async {
    _syncViewActive();
    await context.pushNamed('chatImport', extra: widget.conversation);
    _syncViewActive();
  }

  Future<void> _openChatSettings() async {
    _syncViewActive();
    await context.pushNamed('chatSettings', extra: widget.conversation);
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
    final translatorEnabled = ref.watch(chatTranslatorEntryEnabledProvider);
    final headerDrawerEnabled = ref.watch(
      chatExpandedHeaderDrawerEnabledProvider,
    );
    final historicalImportEnabled = ref.watch(
      chatHistoricalImportEnabledProvider,
    );
    final isOnline = ref.watch(chatConnectivityProvider).valueOrNull ?? true;
    final headerSnapshot = ref.watch(
      chatHeaderSnapshotProvider(conversation.relationshipId),
    );

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => unawaited(_openChatSettings()),
          child: Text(conversation.name),
        ),
        actions: [
          if (historicalImportEnabled.valueOrNull == true)
            IconButton(
              onPressed: () => unawaited(_openHistoricalImport()),
              tooltip: 'Import chat history',
              icon: const Icon(Icons.history_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          _ConversationStateBanner(
            conversation: conversation,
            state: state,
            isOnline: isOnline,
          ),
          _ConversationHeaderCard(
            conversation: conversation,
            snapshot: headerSnapshot,
            isExpanded: _headerExpanded,
            expandedEnabled: headerDrawerEnabled.valueOrNull == true,
            onToggleExpanded: () {
              setState(() => _headerExpanded = !_headerExpanded);
            },
            onOpenPulse: () => unawaited(_openPulse()),
            onOpenInsights: () => unawaited(_openInsights()),
            isOnline: isOnline,
            lastSyncedAt: state.lastSyncedAt,
          ),
          if (state.error != null)
            MaterialBanner(
              content: Text(state.error!),
              actions: [
                TextButton(
                  onPressed: () => notifier.loadMessages(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          Expanded(
            child: _MessageList(
              state: state,
              scrollController: _scrollController,
              firstBuildCutoff: _messageListCutoff,
              animatedMessageIds: _animatedMessageIds,
              messageKeys: _messageKeys,
              highlightedMessageId: _highlightedMessageId,
              onReply: _setReplyTarget,
              onJumpToParent: _jumpToMessage,
            ),
          ),
          Consumer(
            builder: (context, ref, _) {
              final typing =
                  ref
                      .watch(
                        typingControllerProvider(conversation.relationshipId),
                      )
                      .partnerTyping;
              if (!typing) return const SizedBox.shrink();
              return Padding(
                key: const ValueKey('typing_indicator'),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(
                  children: [
                    Text(
                      '${conversation.name} is typing',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 8),
                    const BreathingDots(size: 6),
                  ],
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
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                TextSpan(
                                  text: '\n${_replyToQuotedText ?? ''}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withValues(alpha: 0.8),
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
              onAttachImage:
                  imageSharingEnabled.valueOrNull == true
                      ? () {
                        unawaited(_attachImage());
                      }
                      : null,
              onOpenTranslator:
                  translatorEnabled.valueOrNull == true
                      ? () {
                        unawaited(_openTranslator());
                      }
                      : null,
              showAttachImage: imageSharingEnabled.valueOrNull == true,
              showTranslator: translatorEnabled.valueOrNull == true,
              enabled: !state.isSending,
            )
          else
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  conversation.readOnlyReason ??
                      'This conversation is read-only.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
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
  });

  final Conversation conversation;
  final ChatState state;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final queuedCount =
        state.messages
            .where((message) => message.isMine && message.isQueued)
            .length;
    final failedCount =
        state.messages
            .where((message) => message.isMine && message.isFailed)
            .length;

    String? title;
    String? body;
    IconData icon = Icons.info_outline;
    Color? color;

    if (conversation.isArchived) {
      title = 'Conversation archived';
      body = conversation.readOnlyReason;
      icon = Icons.archive_outlined;
      color = Theme.of(context).colorScheme.errorContainer;
    } else if (!isOnline) {
      title = 'Offline';
      body =
          queuedCount > 0
              ? '$queuedCount message${queuedCount == 1 ? '' : 's'} queued. They will send when you reconnect.'
              : 'Messages will queue locally until you reconnect.';
      icon = Icons.cloud_off_outlined;
      color = Theme.of(context).colorScheme.surfaceContainerHighest;
    } else if (state.isLoading && state.messages.isNotEmpty) {
      title = 'Reconnecting';
      body = 'Syncing the latest messages now.';
      icon = Icons.sync_rounded;
      color = Theme.of(context).colorScheme.primaryContainer;
    } else if (failedCount > 0) {
      title = 'Needs attention';
      body =
          '$failedCount message${failedCount == 1 ? '' : 's'} failed to send. Retry or remove them below.';
      icon = Icons.error_outline_rounded;
      color = Theme.of(context).colorScheme.errorContainer;
    } else if (!conversation.canSend && conversation.readOnlyReason != null) {
      title = 'Read-only';
      body = conversation.readOnlyReason;
      icon = Icons.lock_outline;
      color = Theme.of(context).colorScheme.surfaceContainerHighest;
    }

    if (title == null || body == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(body, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationHeaderCard extends StatelessWidget {
  const _ConversationHeaderCard({
    required this.conversation,
    required this.snapshot,
    required this.isExpanded,
    required this.expandedEnabled,
    required this.onToggleExpanded,
    required this.onOpenPulse,
    required this.onOpenInsights,
    required this.isOnline,
    required this.lastSyncedAt,
  });

  final Conversation conversation;
  final AsyncValue<ChatHeaderSnapshot> snapshot;
  final bool isExpanded;
  final bool expandedEnabled;
  final VoidCallback onToggleExpanded;
  final VoidCallback onOpenPulse;
  final VoidCallback onOpenInsights;
  final bool isOnline;
  final DateTime? lastSyncedAt;

  @override
  Widget build(BuildContext context) {
    final pulse = snapshot.valueOrNull?.pulse;
    final subtitle =
        !isOnline
            ? 'Offline'
            : lastSyncedAt == null
            ? 'Syncing'
            : 'Synced ${_relativeSyncLabel(lastSyncedAt!)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GlowPulse(
                active:
                    conversation.availability ==
                        ConversationAvailability.active &&
                    isOnline,
                child: CircleAvatar(
                  backgroundImage:
                      conversation.avatarUrl == null
                          ? null
                          : NetworkImage(conversation.avatarUrl!),
                  child:
                      conversation.avatarUrl == null
                          ? Text(_initialForName(conversation.name))
                          : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _PulseBadge(pulse: pulse),
              if (expandedEnabled)
                IconButton(
                  onPressed: onToggleExpanded,
                  icon: Icon(
                    isExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                  tooltip:
                      isExpanded ? 'Hide chat details' : 'Show chat details',
                ),
            ],
          ),
          if (expandedEnabled && isExpanded) ...[
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
        ],
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

class _MessageList extends ConsumerWidget {
  const _MessageList({
    required this.state,
    required this.scrollController,
    required this.firstBuildCutoff,
    required this.animatedMessageIds,
    required this.messageKeys,
    required this.highlightedMessageId,
    required this.onReply,
    required this.onJumpToParent,
  });

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

  /// Sets the screen's reply target to (messageId, contentPreview).
  final void Function(String messageId, String contentPreview) onReply;

  /// Jumps to and highlights a reply's parent message, given the current
  /// message list for the index-based fallback estimate.
  final Future<void> Function(String messageId, List<Message> currentMessages)
  onJumpToParent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Chat feel preference (Spec §1.1 tone floor, §3.7): expressive turns the
    // shimmer sweep and reconnect cascade up slightly; calm (default) keeps
    // both a whisper-subtle. Content-blind — only the enum is read here.
    final expressive =
        ref.watch(chatExpressivenessProvider) == ChatExpressiveness.expressive;

    if (state.isLoading && state.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
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

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 200) {
          ref
              .read(chatControllerProvider(state.conversation).notifier)
              .loadMoreMessages();
        }
        if (notification.metrics.pixels <= 120) {
          ref
              .read(chatControllerProvider(state.conversation).notifier)
              .markAsReadDebounced();
        }
        return false;
      },
      child: ListView.builder(
        controller: scrollController,
        reverse: true,
        itemCount: state.messages.length + (state.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == state.messages.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final message = state.messages[index];
          final messageKey = messageKeys[message.id] = GlobalKey();
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
          final isNew = message.createdAt.isAfter(firstBuildCutoff);
          // Play-once ledger: animate only the first time this message is ever
          // built on this screen. Without it, list recycling replays entry
          // animations whenever a new message scrolls back into view.
          final shouldAnimate =
              isNew && !animatedMessageIds.contains(message.clientMessageId);
          if (shouldAnimate) {
            animatedMessageIds.add(message.clientMessageId);
          }

          Widget bubble = MessageBubble(
            message: message,
            onRetry:
                message.isFailed
                    ? () => ref
                        .read(
                          chatControllerProvider(state.conversation).notifier,
                        )
                        .retryMessage(message)
                    : null,
            onRemove:
                message.isFailed
                    ? () => ref
                        .read(
                          chatControllerProvider(state.conversation).notifier,
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
          );
          if (isFirstOfDay && shouldAnimate) {
            bubble = Shimmer(
              period: expressive ? kShimmerSweepExpressive : kShimmerSweepCalm,
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
              expressive ? kCascadeStepExpressiveMs : kCascadeStepCalmMs;
          final staggeredDuration =
              shouldAnimate
                  ? kSettleDuration +
                      Duration(milliseconds: stepMs * index.clamp(0, 6))
                  : kSettleDuration;

          return KeyedSubtree(
            key: messageKey,
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
          );
        },
      ),
    );
  }
}

String _initialForName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'P';
  return trimmed.characters.first.toUpperCase();
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
