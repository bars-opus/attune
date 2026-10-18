import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/appreciation/data/appreciation_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The appreciation jar (Spec 7, research 06 B1): notes this person was
/// sent and chose to keep. Theirs alone; nothing here is ever tallied.
class AppreciationJarScreen extends ConsumerWidget {
  const AppreciationJarScreen({super.key});

  static const routeName = '/appreciation-jar';

  // A mistaken tap can be undone; a failure says so (final review M-9).
  Future<void> _remove(BuildContext context, WidgetRef ref, JarNote n) async {
    final service = ref.read(appreciationServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await service.remove(n.messageId);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't remove it. Try again.")),
      );
      return;
    }
    ref.invalidate(appreciationJarProvider);
    ref.invalidate(appreciationJarIdsProvider);
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Removed from your jar'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              await service.save(n.messageId);
            } catch (_) {
              return;
            }
            ref.invalidate(appreciationJarProvider);
            ref.invalidate(appreciationJarIdsProvider);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    // Guards itself as well as its entry tile (sync audit 2026-10-18).
    if (ref.watch(appreciationEnabledProvider).valueOrNull == false) {
      return Scaffold(
        appBar: AppBar(title: const Text('Your appreciation jar')),
        body: Padding(
          padding: EdgeInsets.all(Spacing.lg.w),
          child: Text('Coming soon', style: text.titleMedium),
        ),
      );
    }
    final notes = ref.watch(appreciationJarProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Your appreciation jar')),
      body: notes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (_, __) =>
                Center(child: Text("Couldn't open it.", style: text.bodyLarge)),
        data:
            (list) =>
                list.isEmpty
                    ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(Spacing.lg.w),
                        child: Text(
                          'Notes you keep will be here.',
                          textAlign: TextAlign.center,
                          style: text.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                    : ListView(
                      padding: EdgeInsets.all(Spacing.md.w),
                      children: [
                        for (final n in list)
                          ListTile(
                            leading: Icon(
                              Icons.eco_outlined,
                              color: scheme.primary,
                            ),
                            title: Text(n.content),
                            subtitle: Text(
                              MyDateFormat.toDate(n.sentAt.toLocal()),
                            ),
                            trailing: IconButton(
                              tooltip: 'Remove from my jar',
                              icon: const Icon(Icons.close),
                              onPressed: () => _remove(context, ref, n),
                            ),
                          ),
                      ],
                    ),
      ),
    );
  }
}
