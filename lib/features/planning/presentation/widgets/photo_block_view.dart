import 'dart:typed_data';
import 'package:gap/gap.dart';
import 'package:attune/core/widgets/feedback/export_extensions.dart';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/media/stacked_media_cards.dart';
import 'package:attune/features/chat/domain/services/chat_image_preparer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/planning_models.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';

const _maxPhotos = 10;

/// Photos ready to upload, and how many of those picked couldn't be used.
typedef PlanningPickedPhotos = ({List<Uint8List> photos, int rejected});

/// Picks up to [limit] photos (several from the library, one from the
/// camera) and re-encodes each to a JPEG with EXIF and GPS removed. Empty
/// when the person cancels.
typedef PlanningPhotoPicker = Future<PlanningPickedPhotos> Function(ImageSource source, int limit);

/// A provider so tests can stand in for the camera and gallery.
final planningPhotoPickerProvider = Provider<PlanningPhotoPicker>((ref) => (source, limit) async {
      final picker = ImagePicker();
      // The library's multi-pick needs room for at least two.
      final files = source == ImageSource.gallery && limit > 1
          ? await picker.pickMultiImage(limit: limit)
          : [if (await picker.pickImage(source: source) case final one?) one];
      final photos = <Uint8List>[];
      var rejected = 0;
      for (final f in files.take(limit)) {
        try {
          photos.add(await (await const ChatImagePreparer().prepare(f.path)).file.readAsBytes());
        } on ChatImageRejected {
          rejected++;
        }
      }
      return (photos: photos, rejected: rejected);
    });

/// Up to 10 photos, private to the couple. Each is re-encoded to JPEG on
/// the device (EXIF and GPS stripped) before it is uploaded.
class PhotoBlockView extends ConsumerStatefulWidget {
  const PhotoBlockView({super.key, required this.args, required this.block, this.menu});
  final PlanningEntryArgs args;
  final PlanningBlock block;

  /// The block's options menu, at the end of the heading row.
  final Widget? menu;

  @override
  ConsumerState<PhotoBlockView> createState() => _PhotoBlockViewState();
}

class _PhotoBlockViewState extends ConsumerState<PhotoBlockView> {
  bool _busy = false;

  /// While several upload: (which one, of how many).
  (int, int)? _progress;

  Future<void> _add() async {
    // Taken up front: the picker and re-encode can outlast this screen.
    final ctl = ref.read(planningEntryProvider(widget.args).notifier);
    final pick = ref.read(planningPhotoPickerProvider);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from library'),
            onTap: () => Navigator.pop(c, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(c, ImageSource.camera),
          ),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    final room = _maxPhotos - widget.block.photoPaths.length;
    setState(() => _busy = true);
    try {
      final picked = await pick(source, room);
      // One after another, in the order picked, so they stack in that order.
      for (var i = 0; i < picked.photos.length; i++) {
        if (mounted && picked.photos.length > 1) setState(() => _progress = (i + 1, picked.photos.length));
        await ctl.addPhoto(widget.block.id, picked.photos[i]);
      }
      if (picked.rejected > 0 && mounted) {
        context.showWarningSnackbar(picked.rejected == 1
            ? "A photo couldn't be used. Try JPEG or PNG."
            : "${picked.rejected} photos couldn't be used. Try JPEG or PNG.");
      }
    } catch (e) {
      if (mounted) showPlanningError(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _open(int index) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _PhotoViewer(args: widget.args, blockId: widget.block.id, paths: widget.block.photoPaths, index: index),
      ));

  @override
  Widget build(BuildContext context) {
    final paths = widget.block.photoPaths;
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(widget.block.title ?? 'Photos', style: Theme.of(context).textTheme.titleMedium)),
        if (widget.menu != null) widget.menu!,
      ]),
      const Gap(Spacing.sm),
      if (paths.isNotEmpty)
        // The app's stacked-photos look, the same as a chat album.
        Semantics(
          label: '${paths.length} ${paths.length == 1 ? 'photo' : 'photos'}. '
              '${paths.length > 1 ? 'Swipe to browse. ' : ''}Double tap to open.',
          child: StackedMediaCards(
            itemCount: paths.length,
            itemKey: (i) => paths[i],
            itemBuilder: (_, i) => PlanningStoredImage(path: paths[i]),
            borderColor: scheme.surfaceContainerHighest,
            backColor: scheme.surfaceContainerHighest,
            // The other photos peek out beneath the front one.
            peekBehind: true,
            onTap: _open,
          ),
        ),
      if (_busy)
        Padding(
          padding: const EdgeInsets.only(top: Spacing.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_progress case (final n, final of)) ...[
              Text('Adding $n of $of', style: Theme.of(context).textTheme.bodySmall),
              const Gap(Spacing.xs),
            ],
            LinearProgressIndicator(value: _progress == null ? null : _progress!.$1 / _progress!.$2),
          ]),
        ),
      if (paths.length < _maxPhotos)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Add photos'),
            onPressed: _busy ? null : _add,
          ),
        ),
    ]);
  }
}

/// A file from planning-media, through a short-lived signed URL; cached by
/// path so a re-signed URL does not download it again.
class PlanningStoredImage extends ConsumerWidget {
  const PlanningStoredImage({super.key, required this.path, this.fit = BoxFit.cover});
  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(planningSignedUrlProvider(path)).valueOrNull;
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(color: scheme.surfaceContainerHighest);
    return ClipRRect(
      borderRadius: BorderRadiusTokens.smAll,
      child: url == null
          ? placeholder
          : CachedNetworkImage(
              imageUrl: url,
              cacheKey: path,
              fit: fit,
              placeholder: (_, __) => placeholder,
              errorWidget: (_, __, ___) =>
                  Container(color: scheme.surfaceContainerHighest, child: Icon(Icons.broken_image_outlined, color: scheme.outline)),
            ),
    );
  }
}

class _PhotoViewer extends ConsumerStatefulWidget {
  const _PhotoViewer({required this.args, required this.blockId, required this.paths, required this.index});
  final PlanningEntryArgs args;
  final String blockId;
  final List<String> paths;
  final int index;

  @override
  ConsumerState<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends ConsumerState<_PhotoViewer> {
  late final _page = PageController(initialPage: widget.index);
  late int _current = widget.index;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _remove() async {
    final ok = await planningConfirm(context,
        title: 'Remove this photo?', message: 'It is removed for both of you.', confirmText: 'Remove', destructive: true);
    if (!ok || !mounted) return;
    try {
      await ref.read(planningEntryProvider(widget.args).notifier).removePhoto(widget.blockId, widget.paths[_current]);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showPlanningError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text('${_current + 1} of ${widget.paths.length}'),
          actions: [IconButton(tooltip: 'Remove photo', icon: const Icon(Icons.delete_outline_rounded), onPressed: _remove)],
        ),
        body: PageView.builder(
          controller: _page,
          itemCount: widget.paths.length,
          onPageChanged: (i) => setState(() => _current = i),
          itemBuilder: (_, i) => InteractiveViewer(child: Center(child: PlanningStoredImage(path: widget.paths[i], fit: BoxFit.contain))),
        ),
      );
}
