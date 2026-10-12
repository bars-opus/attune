import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/chat/domain/services/chat_image_preparer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/planning_models.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';

const _maxPhotos = 10;

/// Up to 10 photos, private to the couple. Each is re-encoded to JPEG on
/// the device (EXIF and GPS stripped) before it is uploaded.
class PhotoBlockView extends ConsumerStatefulWidget {
  const PhotoBlockView({super.key, required this.args, required this.block});
  final PlanningEntryArgs args;
  final PlanningBlock block;

  @override
  ConsumerState<PhotoBlockView> createState() => _PhotoBlockViewState();
}

class _PhotoBlockViewState extends ConsumerState<PhotoBlockView> {
  bool _busy = false;

  Future<void> _add() async {
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
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final prepared = await const ChatImagePreparer().prepare(picked.path);
      final bytes = await prepared.file.readAsBytes();
      await ref.read(planningEntryProvider(widget.args).notifier).addPhoto(widget.block.id, bytes);
    } on ChatImageRejected {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("That photo couldn't be used. Try a JPEG or PNG.")));
      }
    } catch (e) {
      if (mounted) showPlanningError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(int index) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _PhotoViewer(args: widget.args, blockId: widget.block.id, paths: widget.block.photoPaths, index: index),
      ));

  @override
  Widget build(BuildContext context) {
    final paths = widget.block.photoPaths;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.block.title ?? 'Photos', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: Spacing.sm),
      if (paths.isNotEmpty)
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: Spacing.xs,
          crossAxisSpacing: Spacing.xs,
          children: [
            for (var i = 0; i < paths.length; i++)
              Semantics(
                button: true,
                label: 'Photo ${i + 1} of ${paths.length}',
                child: InkWell(onTap: () => _open(i), child: PlanningStoredImage(path: paths[i])),
              ),
          ],
        ),
      if (_busy) const Padding(padding: EdgeInsets.only(top: Spacing.sm), child: LinearProgressIndicator()),
      if (paths.length < _maxPhotos)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Add photo'),
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
