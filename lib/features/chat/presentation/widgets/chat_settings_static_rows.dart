import 'dart:async';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/features/settings/data/streak_replay_preference.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';

/// The three CardInkWell sections that used to sit in the (now deleted)
/// ChatSettingsScreen below its avatar/name identity card, and that now
/// render inside Pulse — Shared location/End relationship, Search/
/// Media/Starred, and Export/Import/Previous relationships. None of this
/// content depends on Conversation having resolved: every icon, title, and
/// subtitle is static, only each row's onTap closure needs the real
/// [conversation] (for navigation `extra` params). Extracted here so
/// PulseTab's _ChatSettingsTab wrapper can render this real content
/// immediately — before Conversation has loaded — while only the identity
/// card above it shows a loading skeleton, instead of blocking the WHOLE
/// page behind a spinner for data most of the page doesn't actually need.
///
/// [conversation] is null while still resolving: every row still renders
/// with its real icon/title/subtitle, but onTap is disabled (InfoRowWidget
/// shows its normal disabled-opacity treatment) rather than either
/// crashing on a null conversation or silently doing nothing with no
/// visual feedback.
class ChatSettingsStaticRows extends ConsumerWidget {
  const ChatSettingsStaticRows({super.key, required this.conversation});

  final Conversation? conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relationshipId = this.conversation?.relationshipId;
    // Defaults to false while loading: a privacy toggle must never show
    // "on" for a state it has not confirmed.
    final isSharingLocation =
        relationshipId == null
            ? false
            : ref
                    .watch(presenceStateProvider(relationshipId))
                    .valueOrNull
                    ?.isOn ??
                false;
    final historicalImportEnabled = ref.watch(
      chatHistoricalImportEnabledProvider,
    );
    final conversation = this.conversation;

    final allowStreakReplays = ref.watch(streakReplayPreferenceProvider);

    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        children: [
          CardInkWell(
            child: Column(
              children: [
                // This toggle used to be hardcoded on and persist
                // nowhere -- the worst shape for a privacy control, since
                // it told every user their location was being shared when
                // nothing was. It is now the real switch.
                //
                // Turning it off DELETES the stored position rather than
                // hiding it, and the partner is not notified: an exit that
                // announces itself is not an exit.
                InfoRowWidget(
                  title: 'Share my location',
                  subtitle: 'Shares your neighbourhood, never your address.',
                  icon: Icons.location_on_outlined,
                  isToggleItem: true,
                  showAvatar: false,
                  showTrailingArrow: false,
                  showDivider: true,
                  toggleValue: isSharingLocation,
                  iconColor: Colors.grey,
                  // InfoRowWidget requires a callback on toggle rows; with
                  // no couple yet there is nothing to share with.
                  onToggleChanged:
                      relationshipId == null
                          ? (_) {}
                          : (value) async {
                            final repository = ref.read(
                              presenceRepositoryProvider,
                            );
                            try {
                              if (value) {
                                await repository.startSharing(relationshipId);
                              } else {
                                await repository.stopSharing(relationshipId);
                              }
                            } catch (_) {
                              // Offline, or the couple has ended: say so —
                              // a silent failure here could leave someone
                              // believing they stopped sharing.
                              if (context.mounted) {
                                context.showErrorSnackbar(
                                  "Couldn't update location sharing. Try again.",
                                );
                              }
                            } finally {
                              // Re-read either way, so the switch shows the
                              // real state.
                              ref.invalidate(
                                coupleMapPresenceProvider(relationshipId),
                              );
                            }
                          },
                ),

                InfoRowWidget(
                  title: 'End relationship',
                  subtitle: 'End this relationship if you have brocken up.',
                  icon: Icons.heart_broken_outlined,
                  iconColor: Colors.grey,
                  showAvatar: false,
                  showTrailingArrow: true,
                  showDivider: false,
                  onTap:
                      conversation == null
                          ? null
                          : () => context.pushNamed(
                            'starredMessages',
                            extra: conversation,
                          ),
                ),
              ],
            ),
          ),
          CardInkWell(
            child: Column(
              children: [
                InfoRowWidget(
                  title: 'Search',
                  subtitle: 'Look for a message in this chat',
                  icon: Icons.search,
                  showTrailingArrow: true,
                  iconColor: Colors.grey,
                  showAvatar: false,
                  showDivider: true,
                  onTap:
                      conversation == null
                          ? null
                          : () async {
                            // Reached from Chat settings (not an already-open
                            // ChatScreen), so a tapped result pops this
                            // settings screen too and pushes a fresh
                            // ChatScreen with jumpTo — same shape as
                            // ChatMediaScreen's own "Go to message" handling
                            // below.
                            final jumpToId = await context.pushNamed<String>(
                              'chatMessageSearch',
                              extra: conversation,
                            );
                            if (jumpToId != null && context.mounted) {
                              context.pop();
                              context.pushNamed(
                                'chatScreen',
                                queryParameters: {'jumpTo': jumpToId},
                                extra: conversation,
                              );
                            }
                          },
                ),

                InfoRowWidget(
                  title: 'Media, docs and links',
                  subtitle: 'Media exachanged in these chat',
                  icon: Icons.image_outlined,
                  showTrailingArrow: true,
                  iconColor: Colors.grey,
                  showAvatar: false,
                  showDivider: true,
                  onTap:
                      conversation == null
                          ? null
                          : () => context.pushNamed(
                            'chatMedia',
                            extra: conversation,
                          ),
                ),

                InfoRowWidget(
                  title: 'Starred messages',
                  subtitle: 'Messages you\'ve starred, just for you',
                  icon: Icons.star_border,
                  showAvatar: false,
                  showTrailingArrow: true,
                  iconColor: Colors.grey,
                  showDivider: false,
                  onTap:
                      conversation == null
                          ? null
                          : () => context.pushNamed(
                            'starredMessages',
                            extra: conversation,
                          ),
                ),
              ],
            ),
          ),
          CardInkWell(
            child: Column(
              children: [
                InfoRowWidget(
                  title: 'Export chat history',
                  iconColor: const Color.fromRGBO(158, 158, 158, 1),
                  subtitle: 'Export read-only chat from Attune',
                  icon: Icons.arrow_upward,
                  showAvatar: false,
                  showDivider: true,
                  onTap:
                      conversation == null
                          ? null
                          : historicalImportEnabled.valueOrNull == true
                          ? () => unawaited(
                            context.pushNamed(
                              'chatImport',
                              extra: conversation,
                            ),
                          )
                          : () {
                            context.showErrorSnackbar(
                              'Cannot import chats rightnow',
                            );
                          },
                ),

                InfoRowWidget(
                  title: 'Import chat history',
                  iconColor: Colors.grey,
                  subtitle:
                      'Bring in a previous conversation from other platforms like WhatsApp',
                  icon: Icons.arrow_downward,
                  showAvatar: false,
                  showDivider: true,
                  onTap:
                      conversation == null
                          ? null
                          : historicalImportEnabled.valueOrNull == true
                          ? () => unawaited(
                            context.pushNamed(
                              'chatImport',
                              extra: conversation,
                            ),
                          )
                          : () {
                            context.showErrorSnackbar(
                              'Cannot import chats rightnow',
                            );
                          },
                ),

                InfoRowWidget(
                  title: 'Previous relationships',
                  showTrailingArrow: true,
                  subtitle: 'Read-only chat history from past relationships',
                  icon: Icons.history,
                  iconColor: Colors.grey,
                  showAvatar: false,
                  showDivider: false,
                  onTap: () => context.pushNamed('previousRelationships'),
                ),
                if (conversation != null)
                  InfoRowWidget(
                    key: const ValueKey('streak_replays_toggle'),
                    title: 'Allow streak replays',
                    subtitle:
                        'They can rewatch your streaks up to 3 times instead of once',
                    icon: Icons.replay_rounded,
                    isToggleItem: true,
                    showAvatar: false,
                    showTrailingArrow: false,
                    showDivider: false,
                    toggleValue: allowStreakReplays,
                    iconColor: Colors.grey,
                    onToggleChanged:
                        (value) => unawaited(
                          ref
                              .read(streakReplayPreferenceProvider.notifier)
                              .setAllowReplays(value),
                        ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
