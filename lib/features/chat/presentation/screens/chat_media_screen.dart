import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/resolved_media_url.dart';
import 'package:attune/features/chat/presentation/widgets/voice_message_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Reached from Chat settings' "Media, docs and links" row. Five tabs —
/// Images/Videos use a GridView of thumbnails (tap opens the same
/// full-screen swipeable viewer used from the chat bubble); Audio, Links,
/// and Documents use a ListView of InfoRowWidget/VoiceMessagePlayer rows,
/// matching the design spec's grid-for-visual, list-for-everything-else
/// split. Links and Documents have no real data source yet (no link
/// detection, no file-sending — see chat_text_field.dart's Files stub), so
/// those two tabs render a friendly empty state rather than fake content.
class ChatMediaScreen extends ConsumerWidget {
  const ChatMediaScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        // title: const Text('Media, docs and links')
      ),
      body: TabsWithContent(
        showContent: true,
        initialIndex: 0,
        scrollable: true,
        tabs: [
          AppTabItem(
            label: 'Images',
            icon: Icons.image_outlined,
            content: _MediaGridTab(
              conversation: conversation,
              mediaType: 'image',
            ),
          ),
          AppTabItem(
            label: 'Videos',
            icon: Icons.videocam_outlined,
            content: _MediaGridTab(
              conversation: conversation,
              mediaType: 'video',
            ),
          ),
          AppTabItem(
            label: 'Audio',
            icon: Icons.mic_none_rounded,
            content: _AudioListTab(conversation: conversation),
          ),
          const AppTabItem(
            label: 'Links',
            icon: Icons.link,
            content: _EmptyMediaTab(icon: Icons.link, message: 'No links yet'),
          ),
          const AppTabItem(
            label: 'Documents',
            icon: Icons.insert_drive_file_outlined,
            content: _EmptyMediaTab(
              icon: Icons.insert_drive_file_outlined,
              message: 'No documents yet',
            ),
          ),
        ],
      ),
    );
  }
}

/// Fetches every message of [mediaType] ('image' or 'video') for
/// [conversation] and renders them as a 3-column thumbnail grid. Tapping a
/// tile opens the same full-screen viewer the chat bubble uses, seeded
/// with this tab's own filtered list (not the live chat's message list —
/// this screen has no ChatController subscription, just a one-shot fetch),
/// so swiping moves through media in THIS grid's order.
class _MediaGridTab extends ConsumerStatefulWidget {
  const _MediaGridTab({required this.conversation, required this.mediaType});

  final Conversation conversation;
  final String mediaType;

  @override
  ConsumerState<_MediaGridTab> createState() => _MediaGridTabState();
}

class _MediaGridTabState extends ConsumerState<_MediaGridTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late Future<List<Message>> _future = _fetch();

  Future<List<Message>> _fetch() {
    return ref
        .read(chatRepositoryProvider)
        .getMediaMessages(
          widget.conversation.relationshipId,
          mediaType: widget.mediaType,
        );
  }

  Future<void> _refresh() async {
    final next = _fetch();
    await next;
    if (mounted) setState(() => _future = next);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<Message>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              widget.mediaType == 'image'
                  ? "Couldn't load images."
                  : "Couldn't load videos.",
            ),
          );
        }
        // rows come back newest-first (getMediaMessages' own ordering);
        // the viewer wants chronological order to swipe forward the same
        // direction as ImageViewerScreen/VideoViewerScreen's other call
        // site, so reverse here once rather than re-deriving per tap.
        final items = snapshot.data ?? const <Message>[];
        if (items.isEmpty) {
          return Center(
            child: Text(
              widget.mediaType == 'image' ? 'No images yet' : 'No videos yet',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }
        final chronological = items.reversed.toList();

        return RefreshIndicator(
          onRefresh: _refresh,
          child: GridView.builder(
            padding: const EdgeInsets.all(2),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            itemCount: chronological.length,
            itemBuilder: (context, index) {
              final message = chronological[index];
              return _MediaGridTile(
                message: message,
                onTap: () async {
                  final jumpToId =
                      widget.mediaType == 'image'
                          ? await context.pushNamed<String>(
                            'imageViewer',
                            extra: ImageViewerRouteArgs(
                              images: chronological,
                              initialIndex: index,
                            ),
                          )
                          : await context.pushNamed<String>(
                            'videoViewer',
                            extra: VideoViewerRouteArgs(
                              videos: chronological,
                              initialIndex: index,
                            ),
                          );
                  if (jumpToId != null && context.mounted) {
                    context.pop();
                    context.pushNamed(
                      'chatScreen',
                      queryParameters: {'jumpTo': jumpToId},
                      extra: widget.conversation,
                    );
                  }
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _MediaGridTile extends StatelessWidget {
  const _MediaGridTile({required this.message, required this.onTap});

  final Message message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thumbnail = ResolvedMediaUrl(
      // Videos are keyed by their thumbnail (media_thumbnail_url), not the
      // video file itself — the grid shows a poster, not a decoded video
      // frame. Images use their own media key directly.
      signedMediaUrl:
          message.mediaType == 'video'
              ? message.signedThumbnailUrl
              : message.signedMediaUrl,
      mediaKey:
          message.mediaType == 'video'
              ? message.mediaThumbnailKey
              : message.mediaKey,
      loading: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      error: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Icon(
          Icons.broken_image_outlined,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      builder:
          (context, url) => CachedNetworkImage(
            imageUrl: url,
            cacheKey:
                message.mediaType == 'video'
                    ? message.mediaThumbnailKey
                    : message.mediaKey,
            fit: BoxFit.cover,
            placeholder:
                (context, url) => Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
            errorWidget:
                (context, url, error) => Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
          ),
    );

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          thumbnail,
          if (message.mediaType == 'video')
            const Center(
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
        ],
      ),
    );
  }
}

/// Every audio message for [conversation], newest first, each rendered as
/// its real VoiceMessagePlayer (waveform + scrub + play) rather than a
/// static InfoRowWidget — the design spec's list-for-non-visual-media
/// still benefits from the real player here, same as the chat bubble.
class _AudioListTab extends ConsumerStatefulWidget {
  const _AudioListTab({required this.conversation});

  final Conversation conversation;

  @override
  ConsumerState<_AudioListTab> createState() => _AudioListTabState();
}

class _AudioListTabState extends ConsumerState<_AudioListTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final Future<List<Message>> _future = ref
      .read(chatRepositoryProvider)
      .getMediaMessages(widget.conversation.relationshipId, mediaType: 'audio');

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<Message>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text("Couldn't load audio."));
        }
        final items = snapshot.data ?? const <Message>[];
        if (items.isEmpty) {
          return Center(
            child: Text(
              'No audio yet',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final message = items[index];
            final audioUrl = message.localMediaPath ?? message.signedMediaUrl;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat.yMMMd().add_jm().format(message.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                if (audioUrl != null)
                  VoiceMessagePlayer(
                    key: ValueKey(message.clientMessageId),
                    messageId: message.clientMessageId,
                    audioUrl: audioUrl,
                    durationMs: message.mediaDurationMs ?? 0,
                    waveform: message.waveform ?? const [],
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _EmptyMediaTab extends StatelessWidget {
  const _EmptyMediaTab({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
