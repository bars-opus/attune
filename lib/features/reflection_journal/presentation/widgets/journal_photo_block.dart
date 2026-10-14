import 'package:attune/app/theme/design_tokens.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/reflection_journal_providers.dart';

/// A private photo in an entry: a 4:3 frame that opens full size.
class JournalPhotoBlock extends ConsumerWidget {
  const JournalPhotoBlock({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final url = ref.watch(journalPhotoUrlProvider(path));
    final fallback = ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Center(child: Icon(Icons.photo_outlined, color: scheme.outline)),
    );
    final image = url.when(
      data: (u) => CachedNetworkImage(imageUrl: u, cacheKey: path, fit: BoxFit.cover, errorWidget: (_, __, ___) => fallback),
      loading: () => ColoredBox(color: scheme.surfaceContainerHigh),
      error: (_, __) => fallback,
    );
    return Semantics(
      image: true,
      label: 'Photo',
      button: true,
      child: GestureDetector(
        onTap: url.hasValue
            ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    backgroundColor: Colors.black,
                    appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
                    body: Center(
                      child: InteractiveViewer(
                        child: CachedNetworkImage(imageUrl: url.requireValue, cacheKey: path, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ))
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
          child: ClipRRect(
            borderRadius: BorderRadiusTokens.mdAll,
            child: AspectRatio(aspectRatio: 4 / 3, child: image),
          ),
        ),
      ),
    );
  }
}
