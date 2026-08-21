import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/theme/app_colors.dart';
import 'package:attune/core/ui/motion/icon_crossfade.dart';
import 'package:attune/core/ui/motion/shimmer.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/core/widgets/focused_action_menu.dart';
import 'package:attune/core/widgets/universal_bubble.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_actions_sheet.dart';
import 'package:attune/features/chat/presentation/widgets/resolved_media_url.dart';
import 'package:attune/features/chat/presentation/widgets/video_message_player.dart';
import 'package:attune/features/chat/presentation/widgets/voice_message_player.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'dart:io';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.conversation,
    this.onRetry,
    this.onRemove,
    this.showStatus = true,
    this.onReply,
    this.onJumpToParent,
    this.isHighlighted = false,
    this.parentDeleted = false,
    this.parentIsMine,
    this.currentUserId,
    this.isStarred = false,
    this.isPinned = false,
    this.onCopy,
    this.onStar,
    this.onUnstar,
    this.onPin,
    this.onUnpin,
    this.onEdit,
    this.onDelete,
    this.onShowEditHistory,
    this.onReact,
    this.onRemoveReaction,
    this.onImageTap,
    this.isGrouped = false,
  });

  final Message message;

  /// True when this message immediately follows another from the SAME
  /// sender with no reply from the other side (or day boundary) in
  /// between — ChatScreen's _MessageList computes this by comparing
  /// against the next-older message in state.messages. Collapses the
  /// bubble's own built-in vertical padding to 0 so a consecutive run of
  /// same-sender bubbles sits flush together, WhatsApp/iMessage-style; the
  /// list's own per-item spacing (chat_screen.dart) handles the normal gap
  /// that returns once the sender switches. Defaults to false so every
  /// other MessageBubble call site (tests, anywhere not doing grouping)
  /// keeps the original fixed spacing unchanged.
  final bool isGrouped;

  /// Needed to push EphemeralVideoViewerScreen, which requires the full
  /// Conversation (not just relationshipId) to build its own
  /// provider-backed state. Nullable rather than required so this task's
  /// change doesn't force every pre-existing MessageBubble test/call site
  /// (none of which exercise ephemeral video) to start passing one — every
  /// REAL call site (ChatScreen's _MessageList) already has the
  /// conversation in scope and passes it. A null conversation simply
  /// means an isEphemeralVideoAvailable bubble renders its sealed tile as
  /// non-interactive (see _BubbleBody's canView derivation) rather than
  /// crashing — the tombstone branch never needs it at all.
  final Conversation? conversation;
  final VoidCallback? onRetry;
  final VoidCallback? onRemove;
  final bool showStatus;

  /// Swipe-to-reply target. Null (the default) disables the swipe gesture
  /// entirely — e.g. a read-only/archived conversation has nothing
  /// sensible to reply into.
  final VoidCallback? onReply;

  /// Tapping this message's quoted-parent preview (only rendered when
  /// message.quotedText is non-null) calls this to scroll to and flash the
  /// parent. Null means no tap affordance on the quote block.
  final VoidCallback? onJumpToParent;

  /// True while this is the current jump-to target — see UniversalBubble.
  final bool isHighlighted;

  /// True when this message's replied-to parent has been deleted (Task 8
  /// looks this up from ChatScreen's loaded message list by
  /// message.replyToMessageId). Only meaningful when message.quotedText
  /// is non-null. Defaults to false — an off-screen/unloaded parent is
  /// assumed not deleted rather than guessed at.
  final bool parentDeleted;

  /// True when this message's replied-to parent was sent by the CURRENT
  /// user (the same currentUserId-based .isMine check every message
  /// already has, looked up the same way parentDeleted is — by scanning
  /// the loaded message list for message.replyToMessageId). Drives the
  /// "You" / partner-name label above the quoted preview. Null (not just
  /// false) means "unknown, parent not in the loaded window" — distinct
  /// from "known to be the partner's" — so the label is omitted entirely
  /// rather than guessed at, matching parentDeleted's own
  /// only-say-what-you-know convention.
  final bool? parentIsMine;

  /// Needed to compute Message.canEditOrDelete inside the long-press
  /// sheet. Null disables the long-press menu entirely (e.g. a read-only
  /// archived conversation has nothing sensible to act on) — matches the
  /// existing null-disables-gesture convention onReply already uses.
  final String? currentUserId;
  final bool isStarred;
  final bool isPinned;
  final VoidCallback? onCopy;
  final VoidCallback? onStar;
  final VoidCallback? onUnstar;
  final VoidCallback? onPin;
  final VoidCallback? onUnpin;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Tapping the "edited" label calls this with the message, to open a
  /// history view. Null disables the tap affordance (label still renders,
  /// just not interactive) — matches this file's existing null-disables
  /// convention.
  final void Function(Message)? onShowEditHistory;

  /// Called with the selected emoji when the user picks a quick reaction or
  /// an emoji from the full picker. Null disables the reaction affordance
  /// entirely — matches this file's existing null-disables-gesture
  /// convention (`onReply`/`onLongPress`).
  final void Function(String emoji)? onReact;

  /// Reserved for a future "tap your own pill to remove" affordance. Not
  /// yet wired to any gesture in this task — see _buildReactionPills.
  final VoidCallback? onRemoveReaction;

  /// Tapping this message's image thumbnail calls this with the tapped
  /// message — the caller (ChatScreen's _MessageList) owns the full,
  /// ordered message list and opens ImageViewerScreen with the filtered
  /// image-only subset + this message's position in it. Null disables the
  /// tap affordance (matches this file's existing null-disables-gesture
  /// convention) — only meaningful when message.hasImage.
  final void Function(Message message)? onImageTap;

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final colorScheme = Theme.of(context).colorScheme;
    final onBubbleColor =
        isMine ? colorScheme.onPrimary : colorScheme.onSurface;
    final canOpenActions = currentUserId != null && !message.isDeleted;

    final reactionPills = _buildReactionPills(context, message, currentUserId);

    // IntrinsicWidth + Align shrink-wraps the Stack to the bubble's own
    // rendered width (UniversalBubble's Align inside otherwise floats
    // within whatever width this Stack is given — the full message-list
    // row — so a plain Stack here would make the reaction pill's
    // left/right:12 insets track the ROW's edges, not the bubble's own,
    // narrower, content-dependent edge). This keeps the pill flush with
    // the same side the quote block's bar/label sit on.
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: IntrinsicWidth(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            UniversalBubble(
              isMine: isMine,
              bubbleColor:
                  isMine
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest,
              onBubbleColor: onBubbleColor,
              showCardBorder: true,
              showShadow: true,
              verticalPadding: isGrouped ? 0 : 4,
              quotedText:
                  parentDeleted
                      ? 'Original message deleted'
                      : message.quotedText,
              // A step below the message content's own size (bodyLarge) — a
              // little smaller reads as a preview/citation rather than a
              // second full-size message, while UniversalBubble's own 12px
              // fallback read too small next to the bumped-up content text.
              quoteTextStyle: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: onBubbleColor),
              // "You" when replying to your own message; the partner's real
              // chat name otherwise (falls back to "Partner" if conversation
              // wasn't passed — matches this file's existing nullable-
              // conversation convention). Omitted (no label row) when
              // parentIsMine is null — the parent message isn't in the loaded
              // window, so who sent it genuinely isn't known here, same
              // "don't guess" principle as parentDeleted.
              quoteAuthorLabel:
                  message.quotedText == null || parentIsMine == null
                      ? null
                      : parentIsMine!
                      ? 'You'
                      : (conversation?.name ?? 'Partner'),
              // WhatsApp-style colored side border on the quote block. Same
              // null-means-unknown gate as quoteAuthorLabel.
              quoteAuthorIsMine:
                  message.quotedText == null ? null : parentIsMine,
              quoteMineBorderColor: Colors.red,
              // Not colorScheme.primary — that's the same green as the "mine"
              // bubble fill, so it wouldn't read as a distinct accent there.
              // Blue reads clearly against both bubble fills (green mine /
              // surfaceContainerHighest theirs).
              quotePartnerBorderColor: Colors.blue,
              onJumpToParent:
                  message.quotedText == null ? null : onJumpToParent,
              isHighlighted: isHighlighted,
              bubbleKey: ValueKey(message.clientMessageId),
              onLongPress:
                  canOpenActions
                      ? (bubbleRect, bubbleSnapshot) => showFocusedActionMenu(
                        context: context,
                        anchorRect: bubbleRect,
                        anchorSnapshot: bubbleSnapshot,
                        quickReactions: const [
                          ReactionQuickOption(emoji: '❤️'),
                          ReactionQuickOption(emoji: '👍'),
                          ReactionQuickOption(emoji: '👎'),
                          ReactionQuickOption(emoji: '😂'),
                          ReactionQuickOption(emoji: '‼️'),
                          ReactionQuickOption(emoji: '❓'),
                        ],
                        onReact: (emoji) => onReact?.call(emoji),
                        // Resolve the Navigator NOW, while this bubble's element
                        // is definitely still mounted (we are inside its
                        // long-press handler). Looking it up later, after the
                        // menu route pops, can fail because the list may have
                        // recycled this element away by then.
                        onOpenFullPicker: _buildFullPickerOpener(
                          context,
                          onReact,
                        ),
                        actions: buildMessageActionItems(
                          context: context,
                          message: message,
                          currentUserId: currentUserId!,
                          isStarred: isStarred,
                          isPinned: isPinned,
                          onReply: onReply ?? () {},
                          onCopy: onCopy ?? () {},
                          onStar: onStar ?? () {},
                          onUnstar: onUnstar ?? () {},
                          onPin: onPin ?? () {},
                          onUnpin: onUnpin ?? () {},
                          onEdit: onEdit ?? () {},
                          onDelete: onDelete ?? () {},
                        ),
                      )
                      : null,
              onReply: onReply,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.isImported)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        'Imported from WhatsApp',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  _BubbleBody(
                    message: message,
                    isMine: isMine,
                    conversation: conversation,
                    onImageTap: onImageTap,
                    onBubbleColor: onBubbleColor,
                    isStarred: isStarred,
                    showStatus: showStatus,
                    metaBuilder:
                        (inline) => _MessageMeta(
                          message: message,
                          isMine: isMine,
                          isStarred: isStarred,
                          showStatus: showStatus,
                          onBubbleColor: onBubbleColor,
                          onRetry: onRetry,
                          onRemove: onRemove,
                          onShowEditHistory: onShowEditHistory,
                          colorScheme: colorScheme,
                          inline: inline,
                        ),
                  ),
                ],
              ),
              footer: const SizedBox.shrink(),
            ),
            if (reactionPills != null)
              Positioned(
                top: -10,
                left: isMine ? -10 : null,
                right: isMine ? null : -10,
                child: reactionPills,
              ),
          ],
        ),
      ),
    );
  }

  /// Short, locale-aware clock label shown visually (e.g. "3:04 PM").
  static String _timeLabel(BuildContext context, DateTime time) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.jm(locale).format(time);
  }

  /// Full absolute date+time announced to screen readers so relative/short
  /// visual times remain accessible (Spec 11.4). Visual semantics are excluded
  /// so the reader announces this label instead of the terse clock string.
  static String _absoluteTimeLabel(BuildContext context, DateTime time) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMMEEEEd(locale).add_jm().format(time);
  }
}

/// One small pill per distinct emoji on [message], or null if there are
/// none. Same emoji from multiple reactors collapses into ONE pill with a
/// small count badge (never multiple pills for the same emoji). Display
/// only — tapping a pill to toggle your own reaction is explicitly out of
/// scope for this plan (see Task 6's manual smoke-test note).
///
/// [currentUserId] decides each pill's background, following the bubble
/// fill convention: primary when you're one of that emoji's reactors (even
/// if your partner also reacted — your own reaction takes visual
/// priority), the partner bubble color when only they reacted, and the
/// neutral default when currentUserId isn't known (matches this file's
/// existing null-means-unknown gating elsewhere).
Widget? _buildReactionPills(
  BuildContext context,
  Message message,
  String? currentUserId,
) {
  if (message.reactions.isEmpty) return null;
  final colorScheme = Theme.of(context).colorScheme;

  // Your own reaction pill uses the OTHER theme's primary shade (dark
  // mode's brighter green in light mode, and vice versa) rather than this
  // theme's own colorScheme.primary — the mine bubble fill is already that
  // same colorScheme.primary, so reusing it here would make your reaction
  // pill blend into your own bubble instead of standing out against it.
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final myReactionColor = isDark ? LightColors.primary : DarkColors.primary;

  // ReplyAvatar's approach (see reply_avatar_stack.dart): a fixed-size
  // square around the CardInkWell, so BorderRadius.circular(100) draws a
  // true circle rather than a stadium shape stretched to fit a Row's
  // variable content width. The reactor count moves to a small badge
  // overlaid on the circle's corner instead of sitting inline, so adding
  // it never breaks the circle back into an ellipse.
  const diameter = 44.0;

  return Wrap(
    spacing: 4,
    children: [
      for (final entry in message.reactions.entries)
        if (entry.value.isNotEmpty)
          SizedBox(
            width: diameter,
            height: diameter,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CardInkWell(
                  padding: EdgeInsets.zero,
                  margin: EdgeInsets.zero,
                  borderRadius: BorderRadius.circular(diameter),
                  color:
                      currentUserId == null
                          ? null
                          : entry.value.contains(currentUserId)
                          ? myReactionColor
                          : colorScheme.surfaceContainerHighest,
                  child: SizedBox(
                    width: diameter,
                    height: diameter,
                    child: Center(
                      child: Text(
                        entry.key,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  ),
                ),
                if (entry.value.length > 1)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: colorScheme.outline),
                      ),
                      constraints: const BoxConstraints(minWidth: 16),
                      child: Text(
                        '${entry.value.length}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
    ],
  );
}

/// Opens the full `emoji_picker_flutter` sheet so the user can react with
/// any emoji, not just the 6 quick-reaction options. Free function (not a
/// method on MessageBubble) since it needs no widget state — mirrors
/// `_showEditDialog`'s free-function shape in chat_screen.dart.
///
/// Resolves the [NavigatorState] eagerly — while [context] is guaranteed
/// mounted, inside the long-press handler — and returns a callback that opens
/// the picker through it. The lookup must not be deferred into the returned
/// closure: by the time that closure runs, the menu route has popped and this
/// bubble's element may have been recycled, which is exactly what broke the
/// "+" button (see [_openFullEmojiPicker]).
VoidCallback _buildFullPickerOpener(
  BuildContext context,
  void Function(String emoji)? onReact,
) {
  final navigator = Navigator.of(context, rootNavigator: true);
  return () => _openFullEmojiPicker(navigator, onReact);
}

/// Takes the [NavigatorState] captured at long-press time rather than
/// MessageBubble's own build context.
///
/// This is what actually broke the "+" button. MessageBubble is a
/// StatelessWidget built lazily inside ChatScreen's ListView.builder, so its
/// element is recyclable: by the time the focused menu's route has popped and
/// this runs, that element may already have been deactivated (the list
/// rebuilding under the menu — a realtime merge, a reaction patch, a scroll
/// past the cache extent — is enough). Routing the sheet through that context
/// meant `context.mounted` was false and the call returned early, so tapping
/// "+" silently did nothing, with no exception to surface the failure.
///
/// A NavigatorState is owned by the Navigator far above the list, so it
/// outlives any individual bubble element and stays valid regardless of
/// recycling.
void _openFullEmojiPicker(
  NavigatorState navigator,
  void Function(String emoji)? onReact,
) {
  if (!navigator.mounted) return;
  showModalBottomSheet<void>(
    context: navigator.context,
    isScrollControlled: true,
    builder:
        (sheetContext) => SizedBox(
          height: 320,
          child: EmojiPicker(
            config: const Config(
              // checkPlatformCompatibility (default true) makes
              // emoji_picker_flutter invoke a 'getSupportedEmojis'
              // platform-channel call on Android to filter unsupported glyphs
              // — its own internal implementation force-unwraps that call's
              // result with `!` with no null check
              // (emoji_picker_internal_utils.dart), which throws "Null check
              // operator used on a null value" when no native handler answers
              // the channel (reproduced on-device: tapping "+" crashed every
              // time on Android). We don't need platform-level filtering
              // here — false skips the channel call entirely, matching the
              // package's own documented escape hatch for exactly this
              // situation (its emojiTextStyle doc comment recommends the same
              // flag for a related concern).
              checkPlatformCompatibility: false,
              categoryViewConfig: CategoryViewConfig(
                // The package's own default (Category.RECENT) opens the sheet
                // on the "recently used" tab, which is EMPTY on first use
                // (SharedPreferences has no 'recent' key yet) — the sheet
                // opens with no crash but looks completely empty, since
                // nothing has ever been picked before. SMILEYS is always
                // populated and matches iMessage/WhatsApp's own default
                // landing category.
                initCategory: Category.SMILEYS,
              ),
            ),
            onEmojiSelected: (category, emoji) {
              onReact?.call(emoji.emoji);
              Navigator.of(sheetContext).pop();
            },
          ),
        ),
  );
}

class _BubbleBody extends StatelessWidget {
  const _BubbleBody({
    required this.message,
    required this.isMine,
    required this.conversation,
    required this.onBubbleColor,
    required this.metaBuilder,
    required this.isStarred,
    required this.showStatus,
    this.onImageTap,
  });

  final Message message;
  final bool isMine;
  final Conversation? conversation;
  final void Function(Message message)? onImageTap;

  final Color onBubbleColor;

  /// Mirrors MessageBubble.isStarred/showStatus — needed here (not just by
  /// metaBuilder) so the inline meta-width calculation in
  /// _inlineMetaWidth can analytically size the same item set
  /// _MessageMeta itself would render, without building it first.
  final bool isStarred;
  final bool showStatus;

  /// Builds the time/status/starred/edited row painted trailing the
  /// message. Called with inline:true when this message is text-only and
  /// not failed — WhatsApp's "meta rides the last line" look, inlined into
  /// the LAST line of plain text via a WidgetSpan, so a short message
  /// doesn't reserve a whole extra line just for the clock. Called with
  /// inline:false for everything else (media/system/deleted/unsupported
  /// bodies aren't paragraph text, so there's no "last line" to ride; a
  /// failed message's Retry/Remove buttons need Wrap's line-wrap fallback,
  /// which the inline WidgetSpan placement can't provide) — those render
  /// the built meta as its own trailing block instead.
  final Widget Function(bool inline) metaBuilder;

  @override
  Widget build(BuildContext context) {
    final color =
        isMine
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.onSurface;

    if (message.isSystemNotice) {
      return Text(
        message.content,
        style: TextStyle(
          color: color,
          fontStyle: FontStyle.italic,
          fontSize: 13,
        ),
      );
    }

    if (message.isDeleted) {
      return Text(
        'This message was deleted',
        style: TextStyle(color: color, fontStyle: FontStyle.italic),
      );
    }

    final children = <Widget>[];
    if (message.hasImage) {
      final thumbnail = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child:
            message.localMediaPath != null
                ? Image(
                  image: FileImage(File(message.localMediaPath!)),
                  width: 220,
                  height: 220,
                  fit: BoxFit.cover,
                  errorBuilder:
                      (context, error, stackTrace) => const _ImageLoadError(),
                )
                : ResolvedMediaUrl(
                  signedMediaUrl: message.signedMediaUrl,
                  mediaKey: message.mediaKey,
                  loading: const Shimmer(
                    sweeps: null,
                    child: _ImagePlaceholder(),
                  ),
                  error: const _ImageLoadError(),
                  builder:
                      (context, url) => CachedNetworkImage(
                        imageUrl: url,
                        // The signed URL's token/expiry changes on every
                        // fetch (createSignedMediaUrl re-signs with a
                        // fresh ~10min TTL each call), so caching by the
                        // URL string itself would never hit — every
                        // reopen looks like a brand-new image. mediaKey
                        // is the stable storage path underneath, so this
                        // key survives across signed-URL refreshes and
                        // actually serves from disk on repeat opens.
                        cacheKey: message.mediaKey,
                        width: 220,
                        height: 220,
                        fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 150),
                        placeholder:
                            (context, url) => const Shimmer(
                              sweeps: null,
                              child: _ImagePlaceholder(),
                            ),
                        errorWidget:
                            (context, url, error) => const _ImageLoadError(),
                      ),
                ),
      );
      children.add(
        onImageTap == null
            ? thumbnail
            : GestureDetector(
              onTap: () => onImageTap!(message),
              child: thumbnail,
            ),
      );
    }
    if (message.hasAudio) {
      children.add(
        message.localMediaPath != null
            ? VoiceMessagePlayer(
              key: ValueKey(message.clientMessageId),
              messageId: message.clientMessageId,
              audioUrl: message.localMediaPath!,
              durationMs: message.mediaDurationMs ?? 0,
              waveform: message.waveform ?? const [],
            )
            : ResolvedMediaUrl(
              signedMediaUrl: message.signedMediaUrl,
              mediaKey: message.mediaKey,
              loading: const Shimmer(sweeps: null, child: _AudioPlaceholder()),
              error: const _ImageLoadError(),
              builder:
                  (context, url) => VoiceMessagePlayer(
                    // clientMessageId (not message.id) — it's the one
                    // identifier that's stable across the
                    // optimistic-to-canonical swap. The optimistic
                    // (pre-upload) message has a synthetic id like
                    // '_local_<clientMessageId>'; once the server confirms
                    // the send, ChatController replaces it with the
                    // canonical row, which has a real UUID as `id` but the
                    // SAME clientMessageId. Using message.id here would
                    // change out from under this widget mid-playback,
                    // tripping the one-at-a-time-enforcement ref.listen
                    // and pausing/tearing down the player for the single
                    // most common case: listening to what you just sent.
                    key: ValueKey(message.clientMessageId),
                    messageId: message.clientMessageId,
                    audioUrl: url,
                    durationMs: message.mediaDurationMs ?? 0,
                    waveform: message.waveform ?? const [],
                  ),
            ),
      );
    }
    if (message.isEphemeralVideoExpired) {
      children.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              'Video expired',
              style: TextStyle(color: color, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      );
    } else if (message.isEphemeralVideoAvailable) {
      final videoUrl = message.localMediaPath ?? message.signedMediaUrl;
      // Gate the tap on the send having actually completed: an optimistic,
      // still-uploading ephemeral video has only a localMediaPath (no
      // signedMediaUrl yet) and a synthetic '_local_<clientMessageId>' id
      // (see the hasAudio/hasVideo branches' comments above on the
      // optimistic-to-canonical id swap). Tapping it would push
      // EphemeralVideoViewerScreen with that synthetic id, and its
      // markVideoViewed RPC call would safely no-op against a
      // non-existent row — but the UI would look broken (the viewer
      // opening over a clip that isn't actually server-backed yet, for no
      // visible reason). Disabling the tap until MessageStatus.sending
      // clears avoids that confusing state without relying on the RPC's
      // no-op-on-no-match behavior as the only safety net.
      final conv = conversation;
      final canView =
          videoUrl != null &&
          conv != null &&
          message.status != MessageStatus.sending;
      if (videoUrl != null) {
        children.add(
          GestureDetector(
            onTap:
                canView
                    ? () {
                      context.pushNamed(
                        'ephemeralVideoViewer',
                        extra: EphemeralVideoViewerRouteArgs(
                          messageId: message.id,
                          videoUrl: videoUrl,
                          conversation: conv,
                        ),
                      );
                    }
                    : null,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 48,
                  color: canView ? null : color.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        );
      }
    } else if (message.hasVideo) {
      children.add(
        SizedBox(
          width: 220,
          child:
              message.localMediaPath != null
                  ? VideoMessagePlayer(
                    key: ValueKey(message.clientMessageId),
                    messageId: message.clientMessageId,
                    videoUrl: message.localMediaPath!,
                    thumbnailUrl: message.signedThumbnailUrl,
                    durationMs: message.mediaDurationMs ?? 0,
                    width: message.mediaWidth ?? 16,
                    height: message.mediaHeight ?? 9,
                  )
                  : ResolvedMediaUrl(
                    signedMediaUrl: message.signedMediaUrl,
                    mediaKey: message.mediaKey,
                    loading: const Shimmer(
                      sweeps: null,
                      child: _ImagePlaceholder(),
                    ),
                    error: const _ImageLoadError(),
                    builder:
                        (context, url) => VideoMessagePlayer(
                          // clientMessageId, not message.id — the same
                          // stability requirement already established for
                          // VoiceMessagePlayer above: the optimistic
                          // message's id changes when the canonical server
                          // row replaces it, but clientMessageId stays the
                          // same throughout.
                          key: ValueKey(message.clientMessageId),
                          messageId: message.clientMessageId,
                          videoUrl: url,
                          thumbnailUrl: message.signedThumbnailUrl,
                          durationMs: message.mediaDurationMs ?? 0,
                          width: message.mediaWidth ?? 16,
                          height: message.mediaHeight ?? 9,
                        ),
                  ),
        ),
      );
    }
    final hasText = message.content.trim().isNotEmpty;
    // Text-only messages (no media above it) get the WhatsApp treatment:
    // meta rides the end of the LAST line via a trailing WidgetSpan, so a
    // short message's clock/tick sits on the same line as the text instead
    // of always claiming its own line below. A message WITH media still
    // gets meta as its own trailing block (below) — there's no single text
    // paragraph for it to flow into there. A FAILED message is excluded
    // too, even when text-only: meta then includes Retry/Remove buttons,
    // which are routinely too wide to share a line with short text (a
    // RenderFlex overflow, confirmed by a real test failure) — the
    // trailing block's Wrap can actually wrap onto a second line if
    // needed, unlike an inline WidgetSpan.
    if (hasText && children.isEmpty && !message.isFailed) {
      final textStyle = Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: color);
      return _inlineMetaText(
        context: context,
        text: message.content,
        textStyle: textStyle,
        meta: metaBuilder(true),
        // UniversalBubble's own bubble ConstrainedBox(maxWidth: 320) minus
        // EVERY horizontal inset between that box and this text, per side:
        // the highlight AnimatedContainer's Border.all(width: 2) AND its
        // EdgeInsets.all(2) padding (a Border's width insets its child on
        // top of any padding), then the content Padding(horizontal: 14) —
        // 320 - 2*2 - 2*2 - 2*14 = 284. Those first two were previously
        // missed, making this 292; since the gap below is computed to land
        // meta flush at this edge AND the probe predicts line breaks at
        // this width, an over-wide value mis-predicts the wrap entirely.
        // 284 is confirmed against the real rendered RenderParagraph's own
        // reported size in a widget test.
        //
        // Not read via LayoutBuilder: LayoutBuilder's render object
        // explicitly refuses to report intrinsic dimensions ("does not
        // support returning intrinsic dimensions"), and MessageBubble's
        // own outer IntrinsicWidth needs exactly that from this whole
        // content chain — confirmed by a real runtime assertion once
        // LayoutBuilder was tried here. UniversalBubble.maxWidth defaults
        // to 320 and MessageBubble never overrides it, so this mirrors
        // that default directly; if either the cap or either padding ever
        // changes, both need updating together.
        maxWidth: 320 - 4 - 4 - 28,
        metaWidth: _inlineMetaWidth(
          context: context,
          message: message,
          isMine: isMine,
          isStarred: isStarred,
          showStatus: showStatus,
        ),
      );
    }

    if (hasText) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 8));
      }
      children.add(
        Text(
          message.content,
          // Was an unstyled Text (no fontSize at all), which fell back to
          // Flutter's raw default rather than this app's own type scale —
          // bodyLarge (17px) matches how WhatsApp/iMessage actually size
          // message text; bodyMedium (14px, AppTextTheme's paragraph
          // default) reads small for a chat bubble specifically.
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
        ),
      );
    }

    if (children.isEmpty) {
      children.add(Text('Unsupported message', style: TextStyle(color: color)));
    }

    // Every path that reaches here either isn't text-only or is a failed
    // message — no paragraph for meta to ride inline, so it renders as its
    // own trailing, right-aligned block instead (this is the
    // pre-inlining footer look, and Wrap's line-wrap fallback matters here
    // for a failed message's Retry/Remove buttons). SizedBox(width:
    // double.infinity) stretches ONLY this child to the surrounding
    // IntrinsicWidth's computed width (the bubble's actual content width —
    // driven by whichever sibling, text or media, is widest), so Wrap's
    // own end-alignment finally has real room to push into; the Column's
    // crossAxisAlignment stays start throughout, so the message text/media
    // above keeps its normal left-reading position exactly like WhatsApp —
    // only meta moves.
    children.add(
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: SizedBox(width: double.infinity, child: metaBuilder(false)),
      ),
    );

    return IntrinsicWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// Renders [text] with [meta] riding its last wrapped line, floated flush
/// against the paragraph's right edge — real WhatsApp behavior: glued right
/// after the last word when the line is nearly full, pushed further right
/// with a gap when there's slack, or bumped to meta's own line when the
/// last line has no room left. Text.rich's textAlign can't target a single
/// line (it applies to the whole paragraph uniformly), so this measures the
/// wrapped text's own last-line width with TextPainter, computes meta's
/// width analytically (see [_inlineMetaWidth]), and reserves exactly the
/// leading gap needed before the meta WidgetSpan in ONE synchronous layout
/// pass — Flutter's own line-breaking then wraps that reserved gap (and
/// meta after it) to a new line on its own if it doesn't fit.
///
/// This has to be single-pass, not a "measure then rebuild" two-pass
/// widget: this exact content Widget gets reused a SECOND time, unchanged,
/// inside UniversalBubble's long-press snapshot overlay — a fresh copy
/// forced into the real bubble's already-captured, fixed on-screen Rect
/// (see UniversalBubble._handleLongPress). A stateful version starts
/// unmeasured there with no opportunity to settle before that fixed-size
/// container locks its layout, and an unmeasured (zero-gap) render can
/// wrap onto a different number of lines than the real, fully-measured
/// bubble — a real RenderFlex overflow, confirmed by a widget test
/// failure. This version needs no second frame, so both copies always
/// render identically from the very first layout.
Widget _inlineMetaText({
  required BuildContext context,
  required String text,
  required TextStyle? textStyle,
  required Widget meta,
  required double maxWidth,
  required double metaWidth,
}) {
  const metaGap = 6.0;
  // Does the text wrap at all within maxWidth? A single-line message's
  // bubble is sized by IntrinsicWidth to the CONTENT's own natural width
  // (text + gap + meta), not to the full maxWidth cap — so "float meta
  // out to maxWidth" is the wrong target for it: maxWidth can be far
  // wider than the bubble will actually end up being, producing a gap
  // that's too large for the intrinsic-sized bubble the paragraph
  // actually lands in and wrapping it (confirmed by a real test failure).
  // Only a message that GENUINELY wraps has a bubble already pinned at
  // maxWidth, where floating meta out to that same edge is correct.
  final singleLineWidth =
      (TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: Directionality.of(context),
      )..layout()).width;
  if (singleLineWidth + metaGap + metaWidth <= maxWidth) {
    return Text.rich(
      TextSpan(
        text: text,
        style: textStyle,
        children: [
          const WidgetSpan(child: SizedBox(width: metaGap)),
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: meta),
        ],
      ),
    );
  }

  final textDirection = Directionality.of(context);

  // Probe the FULL span tree — text plus both trailing placeholders — at
  // exactly the width the real paragraph will use. Two things here are
  // load-bearing, and getting either wrong was the original bug:
  //
  // 1. Measure the span tree, not the bare text. The trailing meta span
  //    occupies room on the final line and therefore changes where the
  //    paragraph breaks, so a text-only probe can report a different line
  //    count (and a wildly different last-line width) than the layout that
  //    actually renders. Confirmed case: a text-only probe reported 3
  //    lines ending at 285px (leaving remaining=5, so the gap collapsed to
  //    its floor and meta never floated), while the real paragraph broke
  //    into 4 lines whose last text line was only 71px — ~212px of slack
  //    the old math never saw.
  //
  // 2. Probe at `maxWidth`, NOT at some margin-reduced width. Line
  //    breaking is a step function: shaving even 2px off the probe width
  //    can move a word to the next line and invalidate the whole
  //    prediction. (Confirmed: probing 2px narrow pushed ALL text off the
  //    last line, so the computed gap ballooned and drove meta onto its
  //    own line.) The safety margin belongs only on the gap TARGET below,
  //    where rounding between this painter and Text.rich's own actually
  //    matters — never on the width whose breaks we are predicting.
  //
  // The probe uses the floor gap: with meta glued as tightly as it will
  // ever be, this finds the earliest possible final break, which is the
  // break the real layout uses too — widening the gap below only pushes
  // meta rightward within that same last line, it never pulls text back up
  // a line (see the clamp below, which never lets the target exceed the
  // slack the probe actually found).
  final probe = TextPainter(
    text: TextSpan(
      text: text,
      style: textStyle,
      children: const [
        WidgetSpan(child: SizedBox.shrink()),
        WidgetSpan(child: SizedBox.shrink()),
      ],
    ),
    textDirection: textDirection,
  );
  probe.setPlaceholderDimensions([
    const PlaceholderDimensions(
      size: Size(metaGap, 1),
      alignment: PlaceholderAlignment.middle,
    ),
    PlaceholderDimensions(
      size: Size(metaWidth, 1),
      alignment: PlaceholderAlignment.middle,
    ),
  ]);
  probe.layout(maxWidth: maxWidth);

  final lines = probe.computeLineMetrics();
  // Width of just the TEXT on the final line, recovered by subtracting the
  // two placeholders back off that line's total — computeLineMetrics
  // reports the whole line including the placeholders riding it, but the
  // gap has to be measured from where the text itself ends.
  final lastLineTotal = lines.isEmpty ? 0.0 : lines.last.width;
  final lastLineWidth = lastLineTotal - metaGap - metaWidth;
  // A last line holding ONLY the two placeholders (no text left on it)
  // means the probe already wrapped meta onto a line of its own — there is
  // no last-line slack to fill, and widening the gap would only push meta
  // further right on that empty line. Keep the floor gap so the real
  // layout reproduces the same wrap.
  if (lastLineWidth <= 0) {
    return Text.rich(
      TextSpan(
        text: text,
        style: textStyle,
        children: [
          const WidgetSpan(child: SizedBox(width: metaGap)),
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: meta),
        ],
      ),
    );
  }

  // A small safety margin below the true max width: the gap is computed so
  // text + gap + meta sums to exactly this target, then re-laid-out for
  // real inside Text.rich using a DIFFERENT TextPainter instance than the
  // probe above — without this margin, floating-point rounding between the
  // two could push the real layout a fraction of a pixel past maxWidth and
  // wrap an extra line this calculation didn't account for.
  const safetyMargin = 2.0;
  final remaining = maxWidth - safetyMargin - lastLineWidth;
  // Reserve enough gap to push meta flush against the bubble's own content
  // edge when there's slack; floor at metaGap so it never glues with
  // literally zero space when the line is nearly full.
  final gap = (remaining - metaWidth).clamp(metaGap, double.infinity);
  return Text.rich(
    TextSpan(
      // The plain text stays exactly `text` (no appended spaces) so
      // find.text(message.content)-style lookups — used throughout this
      // file's own tests — keep matching via TextSpan.toPlainText(); the
      // gap before meta is a WidgetSpan instead, so it doesn't change the
      // paragraph's plain text.
      text: text,
      style: textStyle,
      children: [
        WidgetSpan(child: SizedBox(width: gap)),
        WidgetSpan(alignment: PlaceholderAlignment.middle, child: meta),
      ],
    ),
  );
}

/// Analytic width of [_MessageMeta]'s inline:true layout — sum of each
/// possible item's own known width plus the 6px Row spacing between
/// present items, matching _MessageMeta.build()'s inline item list and
/// spacing exactly. Deliberately not a real widget measurement (see
/// _inlineMetaText's doc for why this has to be synchronous/analytic
/// rather than "build it and read RenderBox.size"). Icon sizes (12, 14)
/// and the bodySmall text style are the exact same values/theme lookups
/// _MessageMeta itself uses for these items — if _MessageMeta's inline
/// item set or sizing ever changes, this needs the matching update.
double _inlineMetaWidth({
  required BuildContext context,
  required Message message,
  required bool isMine,
  required bool isStarred,
  required bool showStatus,
}) {
  final bodySmall = Theme.of(context).textTheme.bodySmall;
  final textDirection = Directionality.of(context);
  double widthOf(String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  final widths = <double>[];
  if (isStarred) widths.add(12);
  if (message.editedAt != null && !message.isDeleted) {
    widths.add(widthOf('edited', bodySmall));
  }
  widths.add(
    widthOf(MessageBubble._timeLabel(context, message.createdAt), bodySmall),
  );
  if (showStatus && isMine) widths.add(14);

  if (widths.isEmpty) return 0;
  final spacing = 6.0 * (widths.length - 1);
  return widths.reduce((a, b) => a + b) + spacing;
}

/// The starred/edited/time/status-tick/retry/remove row painted trailing a
/// message. Used two ways by [_BubbleBody]: inlined as a WidgetSpan riding
/// the last line of plain text, or appended as its own right-aligned block
/// below non-text content — this widget itself doesn't know which, since
/// Wrap(alignment: WrapAlignment.end) reads correctly either way (a no-op
/// when inline, since a WidgetSpan gets no extra width to align within).
class _MessageMeta extends StatelessWidget {
  const _MessageMeta({
    required this.message,
    required this.isMine,
    required this.isStarred,
    required this.showStatus,
    required this.onBubbleColor,
    required this.onRetry,
    required this.onRemove,
    required this.onShowEditHistory,
    required this.colorScheme,
    required this.inline,
  });

  final Message message;
  final bool isMine;
  final bool isStarred;
  final bool showStatus;
  final Color onBubbleColor;
  final VoidCallback? onRetry;
  final VoidCallback? onRemove;
  final void Function(Message)? onShowEditHistory;
  final ColorScheme colorScheme;

  /// True when _BubbleBody is inlining this as a Text.rich WidgetSpan
  /// (rides the last line of plain text). False for the trailing-block
  /// placement below non-text content. Governs Row vs Wrap below — NOT
  /// cosmetic:
  /// - Row (inline: true): when nested inside a WidgetSpan, the enclosing
  ///   RenderParagraph's max-intrinsic-width pass (driven by
  ///   MessageBubble's/UniversalBubble's own IntrinsicWidth wrappers)
  ///   undersizes a Wrap child's contribution — confirmed by an isolated
  ///   repro where swapping this exact content from Wrap to Row was the
  ///   only change needed to stop a short message like "Yeah" wrapping
  ///   onto two lines. Safe here because _BubbleBody only takes the inline
  ///   path for non-failed messages, so Retry/Remove (the two items wide
  ///   enough to actually need wrapping) never appear in this case.
  /// - Wrap (inline: false): the block placement DOES need a wrap
  ///   fallback — a failed message's Retry/Remove buttons overflowed a
  ///   Row here in exactly this position (confirmed by a real test
  ///   failure) once failed messages were routed to the block path.
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      if (isStarred)
        Semantics(
          label: 'Starred',
          excludeSemantics: true,
          child: Icon(Icons.star, size: 12, color: onBubbleColor),
        ),
      if (message.editedAt != null && !message.isDeleted)
        GestureDetector(
          onTap:
              onShowEditHistory == null
                  ? null
                  : () => onShowEditHistory!(message),
          child: Text(
            'edited',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
              color: onBubbleColor,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      Semantics(
        label: MessageBubble._absoluteTimeLabel(context, message.createdAt),
        excludeSemantics: true,
        child: Text(
          MessageBubble._timeLabel(context, message.createdAt),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: onBubbleColor),
        ),
      ),
      if (showStatus && isMine)
        _StatusChip(
          message: message,
          onRetry: onRetry,
          iconColor: onBubbleColor,
          // Same green-on-green contrast problem the quote border color
          // hit earlier: mine bubble fill is already colorScheme.primary,
          // so the "read" tick needs a color distinct from both that
          // fill AND onBubbleColor used for every other status here.
          readColor: isMine ? colorScheme.onPrimary : colorScheme.primary,
        ),
      if (message.isFailed && onRetry != null)
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      if (message.isFailed && onRemove != null)
        TextButton(onPressed: onRemove, child: const Text('Remove')),
    ];

    if (inline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            items[i],
          ],
        ],
      );
    }

    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: items,
    );
  }
}

/// WhatsApp-style status indicator: icon + color only, no "Sent"/
/// "Delivered"/"Read" text label — the checkmark shape and its color (grey
/// vs primary-tinted for read) carry the meaning on their own.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.message,
    this.onRetry,
    this.iconColor,
    this.readColor,
  });

  final Message message;
  final VoidCallback? onRetry;

  /// Icon color for every status except read. Falls back to
  /// colorScheme.onSurfaceVariant when null — the pre-move default, still
  /// correct for a footer painted on a neutral background (e.g. tests that
  /// construct this directly). MessageBubble's own footer, painted inside
  /// the colored bubble fill, passes onBubbleColor instead.
  final Color? iconColor;

  /// Icon color specifically for the read status. Falls back to
  /// colorScheme.primary when null, same reasoning as [iconColor].
  final Color? readColor;

  @override
  Widget build(BuildContext context) {
    final label = switch (message.status) {
      MessageStatus.queued => 'Queued',
      MessageStatus.sending => 'Sending',
      MessageStatus.sent => 'Sent',
      MessageStatus.delivered => 'Delivered',
      MessageStatus.read => 'Read',
      MessageStatus.failed => 'Failed',
    };

    final icon = switch (message.status) {
      MessageStatus.queued => Icons.schedule_rounded,
      MessageStatus.sending => Icons.sync_rounded,
      MessageStatus.sent => Icons.check_rounded,
      MessageStatus.delivered => Icons.done_all_rounded,
      MessageStatus.read => Icons.done_all_rounded,
      MessageStatus.failed => Icons.error_outline_rounded,
    };

    final color = switch (message.status) {
      MessageStatus.failed => Theme.of(context).colorScheme.error,
      MessageStatus.read => readColor ?? Theme.of(context).colorScheme.primary,
      _ => iconColor ?? Theme.of(context).colorScheme.onSurfaceVariant,
    };

    final child = Semantics(
      label: 'Message status: $label',
      child: IconCrossfade(
        child: Icon(
          icon,
          key: ValueKey(message.status),
          size: 14,
          color: color,
        ),
      ),
    );

    if (message.status != MessageStatus.failed || onRetry == null) {
      return child;
    }

    return InkWell(onTap: onRetry, child: child);
  }
}

/// Solid-fill placeholder swept by [Shimmer] while a network image loads —
/// shown only on a genuine first fetch, since CachedNetworkImage skips
/// straight to the decoded image on every subsequent open (disk cache hit).
class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 220,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}

class _ImageLoadError extends StatelessWidget {
  const _ImageLoadError();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 220,
      color: Theme.of(context).colorScheme.errorContainer,
      child: Icon(
        Icons.broken_image_outlined,
        color: Theme.of(context).colorScheme.onErrorContainer,
      ),
    );
  }
}

/// Slim placeholder swept by [Shimmer] while a voice message's signed URL
/// resolves — sized to roughly match VoiceMessagePlayer's real footprint
/// rather than reusing the 220x220 square image placeholder.
class _AudioPlaceholder extends StatelessWidget {
  const _AudioPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(22),
      ),
    );
  }
}
