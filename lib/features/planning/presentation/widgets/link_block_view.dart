import 'package:attune/app/theme/design_tokens.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/planning_error.dart';
import '../../data/planning_models.dart';
import '../planning_providers.dart';
import '../planning_ui.dart';

/// A saved web link. The preview (title, description, image) is fetched by
/// the server; until then, or if it fails, the host and address show.
class LinkBlockView extends ConsumerWidget {
  const LinkBlockView({super.key, required this.args, required this.block});
  final PlanningEntryArgs args;
  final PlanningBlock block;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final raw = await askPlanningText(context,
        title: 'Edit link', label: 'Web address', initial: block.linkUrl ?? '', maxLength: 2048,
        keyboardType: TextInputType.url);
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final url = block.linkUrl ?? '';
    final uri = Uri.tryParse(url);
    final preview = block.linkPreview;
    final ok = preview != null && preview.isOk;
    final host = (ok ? preview.host : null) ?? uri?.host ?? url;
    final title = block.linkLabel ?? (ok ? preview.title : null);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: InkWell(
          borderRadius: BorderRadiusTokens.smAll,
          onTap: uri == null ? null : () => launchUrl(uri, mode: LaunchMode.externalApplication),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (ok && preview.imagePath != null) ...[
                _PreviewImage(path: preview.imagePath!),
                const SizedBox(height: Spacing.sm),
              ],
              if (title != null && title.isNotEmpty)
                Text(title, style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (ok && preview.description != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.xs),
                  child: Text(preview.description!, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                ),
              const SizedBox(height: Spacing.xs),
              Row(children: [
                Icon(Icons.link_rounded, size: 16, color: scheme.primary),
                const SizedBox(width: Spacing.xs),
                Flexible(child: Text(host, style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary))),
              ]),
              if (!ok)
                Text(url, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline)),
            ]),
          ),
        ),
      ),
      IconButton(tooltip: 'Edit link', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(context, ref)),
    ]);
  }
}

class _PreviewImage extends ConsumerWidget {
  const _PreviewImage({required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(planningSignedUrlProvider(path)).valueOrNull;
    final placeholder = Container(color: Theme.of(context).colorScheme.surfaceContainerHighest);
    return ClipRRect(
      borderRadius: BorderRadiusTokens.smAll,
      child: AspectRatio(
        aspectRatio: 1.91, // og:image's usual shape
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
