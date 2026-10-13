import 'package:attune/app/theme/design_tokens.dart';
import 'package:gap/gap.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../data/planning_error.dart';
import '../../data/planning_models.dart';
import '../../domain/youtube_link.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';

/// Asks for the link's address in the app's sheet and saves it. Used by the
/// block's own "Add link" button and by Edit link in its ⋮ menu.
Future<void> editPlanningLink(BuildContext context, WidgetRef ref, PlanningEntryArgs args, PlanningBlock block) async {
  final raw = await askPlanningText(context,
      title: block.linkUrl == null ? 'Add link' : 'Edit link', label: 'Web address', initial: block.linkUrl ?? '',
      maxLength: 2048,
      keyboardType: TextInputType.url,
      validator: planningUrlError);
  if (raw == null || !context.mounted) return;
  final url = normalizePlanningUrl(raw);
  if (url == null) {
    showPlanningError(context, const PlanningInvalidInput('url'));
    return;
  }
  try {
    await ref.read(planningEntryProvider(args).notifier).updateBlockPayload(block, {
      'url': url,
      if (block.linkLabel != null) 'label': block.linkLabel,
    });
  } catch (e) {
    if (context.mounted) showPlanningError(context, e);
  }
}

/// A saved web link. The preview (title, description, image) is fetched by
/// the server; until then, or if it fails, the host and address show.
class LinkBlockView extends ConsumerWidget {
  const LinkBlockView({super.key, required this.args, required this.block, this.menu});
  final PlanningEntryArgs args;
  final PlanningBlock block;

  /// The block's options menu, which a YouTube link places beside Open in
  /// YouTube so its video can span the note.
  final Widget? menu;

  Future<void> _edit(BuildContext context, WidgetRef ref) => editPlanningLink(context, ref, args, block);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (block.linkUrl == null) {
      // A template's link: just its label until the couple adds the address.
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(block.linkLabel ?? 'Link', style: theme.textTheme.titleMedium),
        Row(children: [
          TextButton.icon(
              icon: const Icon(Icons.add_link_rounded), label: const Text('Add link'), onPressed: () => _edit(context, ref)),
          const Spacer(),
          if (menu != null) menu!,
        ]),
      ]);
    }
    final url = block.linkUrl ?? '';
    final videoId = planningYouTubeId(url);
    if (videoId != null) return _YouTubeLink(block: block, videoId: videoId, menu: menu);
    final uri = Uri.tryParse(url);
    final preview = block.linkPreview;
    final ok = preview != null && preview.isOk;
    final host = (ok ? preview.host : null) ?? uri?.host ?? url;
    final title = block.linkLabel ?? (ok ? preview.title : null);
    void open() => launchUrl(uri!, mode: LaunchMode.externalApplication);
    final hasCard = (ok && preview.imagePath != null) || (title != null && title.isNotEmpty) || (ok && preview.description != null);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (hasCard)
        InkWell(
          borderRadius: BorderRadiusTokens.smAll,
          onTap: uri == null ? null : open,
          child: Container(
            // The whole width is tappable, not just the text.
            width: double.infinity,
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (ok && preview.imagePath != null) ...[
                _PreviewImage(path: preview.imagePath!),
                const Gap(Spacing.sm),
              ],
              if (title != null && title.isNotEmpty)
                Text(title, style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (ok && preview.description != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.xs),
                  child: Text(preview.description!, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                ),
            ]),
          ),
        ),
      // The address, with the block's menu at the end of the same row.
      Row(children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadiusTokens.smAll,
            onTap: uri == null ? null : open,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.link_rounded, size: 16, color: scheme.primary),
                  const Gap(Spacing.xs),
                  Flexible(child: Text(host, style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary))),
                ]),
                if (!ok)
                  Text(url, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline)),
              ]),
            ),
          ),
        ),
        if (menu != null) menu!,
      ]),
    ]);
}
}

class _PreviewImage extends ConsumerWidget {
  const _PreviewImage({required this.path, this.aspectRatio = 1.91});
  final String path;
  final double aspectRatio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(planningSignedUrlProvider(path)).valueOrNull;
    final placeholder = Container(color: Theme.of(context).colorScheme.surfaceContainerHighest);
    return ClipRRect(
      borderRadius: BorderRadiusTokens.smAll,
      child: AspectRatio(
        aspectRatio: aspectRatio, // og:image's usual shape is 1.91
        child: url == null
            ? placeholder
            : CachedNetworkImage(
                imageUrl: url,
                cacheKey: path, // signed URLs change; the file does not
                fit: BoxFit.cover,
                placeholder: (_, __) => placeholder,
                errorWidget: (_, __, ___) => placeholder,
              ),
      ),
    );
  }
}

/// Builds the inline YouTube player for a video id. A provider so widget
/// tests can stand in for the web view.
final planningYouTubePlayerProvider = Provider<Widget Function(String videoId)>(
  (ref) => (videoId) => _PlanningYouTubePlayer(videoId: videoId),
);

/// A YouTube link plays in the note: its thumbnail and a play button until
/// tapped, then the player in place. The player (a web view) loads only on
/// that tap, so opening a note with videos contacts no player.
class _YouTubeLink extends ConsumerStatefulWidget {
  const _YouTubeLink({required this.block, required this.videoId, this.menu});
  final PlanningBlock block;
  final String videoId;
  final Widget? menu;

  @override
  ConsumerState<_YouTubeLink> createState() => _YouTubeLinkState();
}

class _YouTubeLinkState extends ConsumerState<_YouTubeLink> {
  bool _playing = false;

  @override
  void didUpdateWidget(_YouTubeLink oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) _playing = false; // edited to another video
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final preview = widget.block.linkPreview;
    final ok = preview != null && preview.isOk;
    final title = widget.block.linkLabel ?? (ok ? preview.title : null);
    final uri = Uri.tryParse(widget.block.linkUrl ?? '');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadiusTokens.smAll,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: _playing
              ? ref.watch(planningYouTubePlayerProvider)(widget.videoId)
              : Semantics(
                  button: true,
                  label: 'Play video',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () => setState(() => _playing = true),
                    child: Stack(fit: StackFit.expand, children: [
                      // Our stored copy of the preview image when there is one;
                      // otherwise YouTube's own thumbnail (an image, no player).
                      if (ok && preview.imagePath != null)
                        _PreviewImage(path: preview.imagePath!, aspectRatio: 16 / 9)
                      else
                        CachedNetworkImage(
                          imageUrl: 'https://i.ytimg.com/vi/${widget.videoId}/hqdefault.jpg',
                          fit: BoxFit.cover,
                          placeholder: (_, __) => ColoredBox(color: scheme.surfaceContainerHighest),
                          errorWidget: (_, __, ___) => ColoredBox(color: scheme.surfaceContainerHighest),
                        ),
                      const ColoredBox(color: Color(0x29000000)),
                      Center(
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 38),
                        ),
                      ),
                    ]),
                  ),
                ),
        ),
      ),
      const Gap(Spacing.sm),
      if (title != null && title.isNotEmpty)
        Text(title, style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
      if (ok && preview.description != null)
        Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: Text(preview.description!, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ),
      const Gap(Spacing.xs),
      Row(children: [
        InkWell(
          borderRadius: BorderRadiusTokens.smAll,
          onTap: uri == null ? null : () => launchUrl(uri, mode: LaunchMode.externalApplication),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.open_in_new_rounded, size: 16, color: scheme.primary),
              const Gap(Spacing.xs),
              Text('Open in YouTube', style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
            ]),
          ),
        ),
        const Spacer(),
        if (widget.menu != null) widget.menu!,
      ]),
    ]);
  }
}

class _PlanningYouTubePlayer extends StatefulWidget {
  const _PlanningYouTubePlayer({required this.videoId});
  final String videoId;

  @override
  State<_PlanningYouTubePlayer> createState() => _PlanningYouTubePlayerState();
}

/// The inline player's settings. It loads from YouTube's privacy-enhanced
/// domain: with the package's default (youtube.com) YouTube refuses the
/// embed with error 152-4, and no-cookie also sets no tracking cookies
/// until a video plays.
const planningYouTubePlayerParams = YoutubePlayerParams(
  origin: 'https://www.youtube-nocookie.com',
  playsInline: true,
  strictRelatedVideos: true,
);

/// The player's key, which the package turns into a JavaScript channel
/// name (`Youtube` + key). A raw id would break on a hyphen, so `_` and `-`
/// are escaped to `_1` and `_0`: always a valid name, never shared.
String planningYouTubePlayerKey(String videoId) =>
    videoId.replaceAll('_', '_1').replaceAll('-', '_0');

class _PlanningYouTubePlayerState extends State<_PlanningYouTubePlayer> {
  late final YoutubePlayerController _controller =
      YoutubePlayerController(params: planningYouTubePlayerParams, key: planningYouTubePlayerKey(widget.videoId))
        // It was opened by tapping play, so it starts straight away.
        ..loadVideoById(videoId: widget.videoId);

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => YoutubePlayer(
        controller: _controller,
        // Inside a scrolling note: a vertical drag must scroll, not go full screen.
        enableFullScreenOnVerticalDrag: false,
      );
}
