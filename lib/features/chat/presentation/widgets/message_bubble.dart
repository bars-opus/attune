import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/theme/app_colors.dart';
import 'package:attune/app/theme/design_tokens.dart';
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
import 'package:attune/features/chat/presentation/widgets/video_message_thumbnail.dart';
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
    this.showLatestTimestamp = false,
    this.showTimestamp = true,
    this.timestampRevealOffset = 0,
    this.onTimestampRevealChanged,
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
    this.onVideoTap,
    this.isGrouped = false,
    this.isGroupedWithPrevious = false,
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

  /// True when this message has a same-sender neighbor below it on screen.
  /// ChatScreen passes this from the next-newer message in its newest-first
  /// list so grouped runs can square the touching bottom-side corner too.
  final bool isGroupedWithPrevious;

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
  final bool showLatestTimestamp;
  final bool showTimestamp;
  final double timestampRevealOffset;
  final ValueChanged<double>? onTimestampRevealChanged;

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

  /// Called when the current user taps their own visible reaction pill.
  /// Partner-only reaction pills stay display-only.
  final VoidCallback? onRemoveReaction;

  /// Tapping this message's image thumbnail calls this with the tapped
  /// message — the caller (ChatScreen's _MessageList) owns the full,
  /// ordered message list and opens ImageViewerScreen with the filtered
  /// image-only subset + this message's position in it. Null disables the
  /// tap affordance (matches this file's existing null-disables-gesture
  /// convention) — only meaningful when message.hasImage.
  final void Function(Message message)? onImageTap;

  /// Mirrors [onImageTap] exactly, for a non-ephemeral video bubble — the
  /// caller opens VideoViewerScreen with the filtered video-only subset +
  /// this message's position in it. Null disables the tap affordance. Only
  /// meaningful when message.hasVideo (an ephemeral/view-once video keeps
  /// its own separate tap-to-EphemeralVideoViewerScreen gesture, already
  /// wired independently in _BubbleBody's isEphemeralVideoAvailable
  /// branch — this callback is never consulted there).
  final void Function(Message message)? onVideoTap;

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final colorScheme = Theme.of(context).colorScheme;
    final bubbleColor = _bubbleFill(context, isMine: isMine);
    final bubbleGradient = _bubbleGradient(context, isMine: isMine);
    final bubbleRadius = _groupedBubbleRadius(
      isMine: isMine,
      groupedAbove: isGrouped,
      groupedBelow: isGroupedWithPrevious,
    );
    final onBubbleColor =
        isMine ? colorScheme.onPrimary : colorScheme.onSurface;
    final canOpenActions =
        currentUserId != null && !message.isDeleted && !message.isPreparing;
    final hasVisibleFooter =
        showLatestTimestamp ||
        (showStatus && isMine) ||
        (message.isFailed && (onRetry != null || onRemove != null));

    final bubbleAdornments = _buildBubbleAdornments(
      context,
      message,
      currentUserId,
      isStarred: isStarred,
      onRemoveReaction: onRemoveReaction,
    );

    const timestampRevealColumnWidth = 112.0;
    final timestampRevealBottomInset = hasVisibleFooter ? 24.0 : 0.0;

    // The timestamp reveal belongs to the full message row, not the bubble's
    // shrink-wrapped width. Keeping it row-level gives every visible message
    // the same right-side timestamp column during an iMessage-style left
    // swipe, including short incoming bubbles.
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: EdgeInsets.only(bottom: bubbleAdornments == null ? 0 : 16),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
              child: IntrinsicWidth(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    UniversalBubble(
                      isMine: isMine,
                      bubbleColor: bubbleColor,
                      bubbleGradient: bubbleGradient,
                      onBubbleColor: onBubbleColor,
                      leading: !isMine ? const SizedBox(width: 8) : null,
                      showCardBorder: false,
                      showShadow: false,
                      bubbleBorderRadius: 24,
                      bubbleBorderRadiusOverride: bubbleRadius,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      verticalPadding:
                          isGrouped || isGroupedWithPrevious ? 0 : 4,
                      footerSpacing: hasVisibleFooter ? 4 : 0,
                      showFooter: hasVisibleFooter,
                      dragOffsetOverride:
                          timestampRevealOffset > 0
                              ? -timestampRevealOffset
                              : null,
                      startReveal: null,
                      onEndRevealDragChanged: onTimestampRevealChanged,
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
                      quoteMineBorderColor: colorScheme.error,
                      // Not colorScheme.primary — that's the same green as the "mine"
                      // bubble fill, so it wouldn't read as a distinct accent there.
                      // Blue reads clearly against both bubble fills (green mine /
                      // surfaceContainerHighest theirs).
                      quotePartnerBorderColor:
                          AppColors(
                            Theme.of(context).brightness == Brightness.dark,
                          ).info,
                      onJumpToParent:
                          message.quotedText == null ? null : onJumpToParent,
                      isHighlighted: isHighlighted,
                      bubbleKey: ValueKey(message.clientMessageId),
                      onLongPress:
                          canOpenActions
                              ? (
                                bubbleRect,
                                bubbleSnapshot,
                              ) => showFocusedActionMenu(
                                context: context,
                                anchorRect: bubbleRect,
                                anchorSnapshot: bubbleSnapshot,
                                quickReactions: const [
                                  ReactionQuickOption(emoji: '❤️'),
                                  ReactionQuickOption(emoji: '👍'),
                                  ReactionQuickOption(emoji: '😂'),
                                  ReactionQuickOption(emoji: '🥹'),
                                  ReactionQuickOption(emoji: '🤗'),
                                  ReactionQuickOption(emoji: '😢'),
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
                            onVideoTap: onVideoTap,
                            onBubbleColor: onBubbleColor,
                          ),
                        ],
                      ),
                      footer:
                          hasVisibleFooter
                              ? _MessageMeta(
                                message: message,
                                isMine: isMine,
                                isStarred: false,
                                showStatus: showStatus,
                                showTime: showLatestTimestamp,
                                showEdited: false,
                                onBubbleColor: colorScheme.onSurfaceVariant,
                                onRetry: onRetry,
                                onRemove: onRemove,
                                onShowEditHistory: onShowEditHistory,
                                colorScheme: colorScheme,
                                inline: false,
                              )
                              : const SizedBox.shrink(),
                    ),
                    if (bubbleAdornments != null)
                      Positioned(
                        bottom: -12,
                        left: isMine ? 10 : null,
                        right: isMine ? null : 10,
                        child: bubbleAdornments,
                      ),
                  ],
                ),
              ),
            ),
            // Keep the timestamp above the translated bubble. Incoming
            // bubbles naturally leave this lane clear, but a wide outgoing
            // bubble can otherwise cover the clock's hour/minute and leave
            // only AM/PM visible during the same drag distance.
            if (showTimestamp && timestampRevealOffset > 0)
              Positioned(
                right: 8,
                top: 0,
                bottom: timestampRevealBottomInset,
                width: timestampRevealColumnWidth,
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.surface,
                    child: Center(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _RevealTimestamp(message: message),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static BorderRadius _groupedBubbleRadius({
    required bool isMine,
    required bool groupedAbove,
    required bool groupedBelow,
  }) {
    const outer = Radius.circular(24);
    const inner = Radius.circular(6);

    if (isMine) {
      return BorderRadius.only(
        topLeft: outer,
        bottomLeft: outer,
        topRight: groupedAbove ? inner : outer,
        bottomRight: groupedBelow ? inner : outer,
      );
    }

    return BorderRadius.only(
      topLeft: groupedAbove ? inner : outer,
      bottomLeft: groupedBelow ? inner : outer,
      topRight: outer,
      bottomRight: outer,
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

class _RevealTimestamp extends StatelessWidget {
  const _RevealTimestamp({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Semantics(
        label: MessageBubble._absoluteTimeLabel(context, message.createdAt),
        excludeSemantics: true,
        child: Text(
          MessageBubble._timeLabel(context, message.createdAt),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

Color _bubbleFill(BuildContext context, {required bool isMine}) {
  final colorScheme = Theme.of(context).colorScheme;
  if (isMine) return colorScheme.primary;

  final tint = colorScheme.primary.withValues(
    alpha: Theme.of(context).brightness == Brightness.dark ? 0.08 : 0.02,
  );
  final base =
      Theme.of(context).brightness == Brightness.dark
          ? colorScheme.surfaceContainerHighest
          : const Color(0xFFF0F1F4);
  return Color.alphaBlend(tint, base);
}

Gradient? _bubbleGradient(BuildContext context, {required bool isMine}) {
  if (!isMine) return null;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final appColors = AppColors(isDark);
  return LinearGradient(
    colors:
        isDark
            ? [appColors.primaryDark, appColors.primary]
            : [appColors.primaryDark, appColors.primary, appColors.moderate],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// One small pill per distinct emoji on [message], or null if there are
/// none. Same emoji from multiple reactors collapses into ONE pill with a
/// small count badge (never multiple pills for the same emoji). Display
/// Tapping your own reaction pill removes it; partner-only pills remain
/// display-only.
///
/// [currentUserId] decides each pill's background, following the bubble
/// fill convention: primary when you're one of that emoji's reactors (even
/// if your partner also reacted — your own reaction takes visual
/// priority), the partner bubble color when only they reacted, and the
/// neutral default when currentUserId isn't known (matches this file's
/// existing null-means-unknown gating elsewhere).
Widget? _buildBubbleAdornments(
  BuildContext context,
  Message message,
  String? currentUserId, {
  required bool isStarred,
  VoidCallback? onRemoveReaction,
}) {
  if (message.reactions.isEmpty && !isStarred) return null;
  final colorScheme = Theme.of(context).colorScheme;

  // Your own reaction pill uses the OTHER theme's primary shade (dark
  // mode's brighter green in light mode, and vice versa) rather than this
  // theme's own colorScheme.primary — the mine bubble fill is already that
  // same colorScheme.primary, so reusing it here would make your reaction
  // pill blend into your own bubble instead of standing out against it.
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final myReactionColor = isDark ? LightColors.primary : DarkColors.primary;
  final onMyReactionColor =
      isDark ? LightColors.white : LightColors.textPrimary;

  return Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      for (final entry in message.reactions.entries)
        if (entry.value.isNotEmpty)
          Builder(
            builder: (context) {
              final containsMine =
                  currentUserId != null && entry.value.contains(currentUserId);
              return CardInkWell(
                onTap:
                    containsMine && onRemoveReaction != null
                        ? onRemoveReaction
                        : null,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: EdgeInsets.zero,
                borderRadius: BorderRadius.circular(BorderRadiusTokens.full),
                elevation: ElevationTokens.none,
                enableFeedback: containsMine && onRemoveReaction != null,
                color:
                    currentUserId == null
                        ? colorScheme.surface
                        : containsMine
                        ? myReactionColor
                        : colorScheme.surface,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(entry.key, style: const TextStyle(fontSize: 16)),
                    if (entry.value.length > 1) ...[
                      const SizedBox(width: 3),
                      Text(
                        '${entry.value.length}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color:
                              containsMine
                                  ? onMyReactionColor
                                  : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
      if (isStarred) _StarAdornment(colorScheme: colorScheme),
    ],
  );
}

class _StarAdornment extends StatelessWidget {
  const _StarAdornment({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return CardInkWell(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      margin: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(BorderRadiusTokens.full),
      elevation: ElevationTokens.none,
      enableFeedback: false,
      color: colorScheme.surface,
      child: Semantics(
        label: 'Starred',
        excludeSemantics: true,
        child: const Icon(
          Icons.star_rounded,
          size: 15,
          color: Color(0xFFFFB020),
        ),
      ),
    );
  }
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
    this.onImageTap,
    this.onVideoTap,
  });

  final Message message;
  final bool isMine;
  final Conversation? conversation;
  final void Function(Message message)? onImageTap;
  final void Function(Message message)? onVideoTap;

  final Color onBubbleColor;

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
      // Busy overlay while the image is still on its way out, matching the
      // video tile and WhatsApp: the picture is fully visible from the
      // moment you hit send, with a spinner drawn over it until it lands.
      // Indeterminate — the upload reports no byte-level progress.
      final imageTile =
          message.isSending
              ? Stack(
                alignment: Alignment.center,
                children: [thumbnail, const _MediaBusyOverlay()],
              )
              : thumbnail;
      children.add(
        onImageTap == null
            ? imageTile
            : GestureDetector(
              onTap: () => onImageTap!(message),
              child: imageTile,
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
    } else if (message.isPreparing || message.hasVideo) {
      // ONE branch for both the still-preparing and the finished states, so
      // the same VideoMessageThumbnail element stays mounted across the
      // transition. Two separate branches would swap widget types mid-send,
      // remounting the tile and re-running its poster measurement — a
      // visible flicker and a possible shape jump at the exact moment the
      // user is watching the upload finish.
      //
      // Poster only — never an inline player. Tapping opens the full-screen
      // viewer, matching WhatsApp/iMessage. Beyond being the expected
      // interaction, this is what makes the tile's aspect ratio STABLE: the
      // old inline player derived its shape from the persisted
      // (rotation-blind) media_width/media_height before playback and from
      // the decoder's true ratio after, so the bubble visibly jumped shape
      // mid-tap. VideoMessageThumbnail has one source of truth instead —
      // the decoded poster, which has rotation baked in by construction.
      final isBusy = message.isPreparing || message.isSending;
      children.add(
        SizedBox(
          width: 220,
          child: VideoMessageThumbnail(
            key: ValueKey(message.clientMessageId),
            // Local poster first (the just-sent case, before the canonical
            // row's signed thumbnail URL exists), then the signed URL. The
            // local path now arrives DURING compression (see
            // ChatVideoPreparer's onPosterReady), so the real frame is on
            // screen almost immediately rather than after the transcode.
            thumbnailUrl:
                message.localThumbnailPath ?? message.signedThumbnailUrl,
            durationMs: message.mediaDurationMs ?? 0,
            width: message.mediaWidth ?? 0,
            height: message.mediaHeight ?? 0,
            // Progress ring over the poster while compressing and while
            // uploading — WhatsApp shows one continuous busy state across
            // both, not two different-looking phases. Null once the send
            // completes, which removes the ring and restores the play glyph.
            uploadProgress: isBusy ? message.compressProgress : null,
            showBusyOverlay: isBusy,
            // Not tappable until there's something to play.
            onTap:
                (message.isPreparing || onVideoTap == null)
                    ? null
                    : () => onVideoTap!(message),
          ),
        ),
      );
    }
    final hasText = message.content.trim().isNotEmpty;
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
      // A message that declares a media type but hasn't resolved a source
      // yet is PENDING, not unsupported. This window is real and routinely
      // hit: right after a video's compression finishes, the optimistic row
      // flips isPreparing false and is swapped for the canonical server row
      // a moment before mediaKey/signedMediaUrl land — hasVideo needs one
      // of mediaKey/signedMediaUrl/localMediaPath, so for those few frames
      // every branch above misses and the bubble used to read "Unsupported
      // message". Show the media placeholder instead; "Unsupported" is
      // reserved for a message that genuinely has no renderable type.
      final isPendingMedia =
          message.mediaType == 'image' ||
          message.mediaType == 'audio' ||
          message.mediaType == 'video';
      children.add(
        isPendingMedia
            ? const Shimmer(sweeps: null, child: _ImagePlaceholder())
            : Text('Unsupported message', style: TextStyle(color: color)),
      );
    }

    return IntrinsicWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// Compact message metadata. Chat uses this in two different places:
/// behind the bubble during a rightward drag for time/status, and below the
/// bubble only for the few visible footer markers that should remain.
class _MessageMeta extends StatelessWidget {
  const _MessageMeta({
    required this.message,
    required this.isMine,
    required this.isStarred,
    required this.showStatus,
    required this.showTime,
    required this.showEdited,
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
  final bool showTime;
  final bool showEdited;
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
      if (showEdited && message.editedAt != null && !message.isDeleted)
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
      if (showTime)
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

/// Shown in place of VideoMessagePlayer while ChatController.sendVideoMessage
/// is still running ChatVideoPreparer's compression pass in the background
/// (message.isPreparing) — no real video/thumbnail file exists yet, so this
/// intentionally doesn't try to build a player around one. [progress] is
/// null before the first video_compress progress tick arrives, in which
/// case the indicator just spins indeterminately rather than sitting at 0%.
/// Solid-fill placeholder swept by [Shimmer] while a network image loads —
/// shown only on a genuine first fetch, since CachedNetworkImage skips
/// straight to the decoded image on every subsequent open (disk cache hit).
/// Dim + spinner drawn over a media tile that is still being sent. The
/// media itself stays fully visible underneath — WhatsApp's treatment,
/// where hitting send puts the real picture on screen immediately and only
/// layers a progress affordance on top, rather than hiding it behind a
/// placeholder until the upload finishes.
class _MediaBusyOverlay extends StatelessWidget {
  const _MediaBusyOverlay();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Sending',
      child: Container(
        width: 220,
        height: 220,
        color: Colors.black.withValues(alpha: 0.25),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
        ),
      ),
    );
  }
}

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
