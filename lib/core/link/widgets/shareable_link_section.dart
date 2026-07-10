// lib/core/link/widgets/shareable_link_section.dart
//
// Reusable widget for shop settings (and future freelancer settings).
// Shows the public booking link, copy + share buttons via the system
// share sheet, and an "Edit slug" affordance.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:attune/core/link/config/aurain_link_config.dart';

class ShareableLinkSection extends ConsumerWidget {
  /// The currently-cached slug (read from `shops.booking_slug`). null if
  /// the shop hasn't been saved yet or slug generation failed earlier.
  final String? currentSlug;

  /// Display name used in the share text (e.g. "Book your appointment at `name`...").
  final String entityName;

  /// Called when the owner edits the slug. Caller is responsible for
  /// validating uniqueness (LinkService.createShopLink handles that) and
  /// refreshing the upstream provider so currentSlug updates.
  final Future<void> Function(String newSlug) onEditSlug;

  const ShareableLinkSection({
    super.key,
    required this.currentSlug,
    required this.entityName,
    required this.onEditSlug,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = AuraInLinkConfig.getConfig();

    if (currentSlug == null) {
      return const Card(
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ListTile(
          leading: Icon(Icons.link),
          title: Text('Shareable booking link'),
          subtitle: Text('Link will appear after your profile is saved.'),
        ),
      );
    }

    final url = 'https://${config.baseDomain}/book/$currentSlug';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Shareable booking link',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Share this on WhatsApp or Instagram to let clients book without the app.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                url,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: url));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Link copied')),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.share, size: 16),
                    label: const Text('Share'),
                    onPressed: () => Share.share(
                      'Book your appointment at $entityName: $url',
                      subject: 'Book at $entityName',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _showEditSlugDialog(context),
              child: const Text('Edit slug'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditSlugDialog(BuildContext context) async {
    final config = AuraInLinkConfig.getConfig();
    final ctrl = TextEditingController(text: currentSlug);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit booking link slug'),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            prefixText: '${config.baseDomain}/book/',
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || result == currentSlug) return;
    try {
      await onEditSlug(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Slug updated')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update slug: $e')),
        );
      }
    }
  }
}
