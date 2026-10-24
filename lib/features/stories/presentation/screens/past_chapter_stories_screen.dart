// lib/features/stories/presentation/screens/past_chapter_stories_screen.dart
/// Download my data → "Your stories from past chapters" (stories Wave 5,
/// review 05 #3): an author's own stories from spaces that are paused or
/// have ended, with Delete all and per-story delete. Dates and kinds only:
/// Storage is closed at an ending, so there are no thumbnails, and nothing
/// here names the other person.
library;

import 'dart:async';

import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/stories/data/past_story_chapters_repository.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _stories(int n) => '$n ${n == 1 ? 'story' : 'stories'}';

/// 48 dp targets for the screen's buttons, whatever the theme says.
const _target = Size(Spacing.xxl, Spacing.xxl);

String _kind(PastStoryItem item) => item.isVideo ? 'video' : 'photo';

/// What a failed delete says. UNAVAILABLE means the space was resumed while
/// deleting: its stories are back on the calendar and deleted there.
({String message, bool retry}) _deleteFailure(Object error) {
  if (error is StoryApiError && error.code == 'UNAVAILABLE') {
    return (
      message: 'This space is open again. Delete these from the calendar.',
      retry: false,
    );
  }
  if (error is StoryApiError && error.code != StoryErrorCodes.network) {
    return (message: "Couldn't delete. Please try again.", retry: true);
  }
  return (
    message: "Couldn't delete. Check your connection, then try again.",
    retry: true,
  );
}

/// A spinner with a label for screen readers.
Widget _spinner(String label) =>
    Center(child: CircularProgressIndicator(semanticsLabel: label));

/// The row on Download my data. Nothing at all while loading, on error, or
/// when there is nothing to show, so the screen looks as before for most
/// people.
class PastChapterStoriesEntry extends ConsumerWidget {
  const PastChapterStoriesEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapters = ref.watch(pastStoryChaptersProvider).valueOrNull;
    if (chapters == null || chapters.isEmpty) return const SizedBox.shrink();
    final total = chapters.fold<int>(0, (n, c) => n + c.storyCount);
    return Padding(
      padding: EdgeInsets.only(top: Spacing.lg.h),
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          minVerticalPadding: Spacing.sm,
          leading: Icon(Icons.auto_stories_outlined, size: IconSizes.md),
          title: const Text('Your stories from past chapters'),
          subtitle: Text('${_stories(total)} only you can see and delete'),
          trailing: Icon(Icons.chevron_right, size: IconSizes.md),
          onTap:
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PastChapterStoriesScreen(),
                ),
              ),
        ),
      ),
    );
  }
}

class PastChapterStoriesScreen extends ConsumerWidget {
  const PastChapterStoriesScreen({super.key});

  static const intro =
      "Stories you posted in a shared space that's paused or has ended. "
      'Nobody can see them now. They stay until you delete them; a space '
      'that has ended is deleted, with its stories, 12 months after it closes.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(pastStoryChaptersProvider);
    final children = <Widget>[
      Text(
        intro,
        style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      Gap(Spacing.lg.h),
    ];
    async.when(
      loading: () => children.add(_spinner('Loading your stories')),
      error:
          (_, __) => children.addAll([
            Text("Couldn't load your stories.", style: text.bodyLarge),
            Gap(Spacing.sm.h),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: _target),
                onPressed: () => ref.invalidate(pastStoryChaptersProvider),
                child: const Text('Try again'),
              ),
            ),
          ]),
      data: (chapters) {
        if (chapters.isEmpty) {
          children.add(Text('Nothing left here.', style: text.bodyLarge));
          return;
        }
        for (final chapter in chapters) {
          children
            ..add(
              _ChapterCard(
                key: ValueKey(chapter.relationshipId),
                chapter: chapter,
              ),
            )
            ..add(Gap(Spacing.md.h));
        }
      },
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Stories from past chapters')),
      body: ListView(padding: EdgeInsets.all(Spacing.lg.w), children: children),
    );
  }
}

class _ChapterCard extends ConsumerStatefulWidget {
  const _ChapterCard({super.key, required this.chapter});
  final PastStoryChapter chapter;

  @override
  ConsumerState<_ChapterCard> createState() => _ChapterCardState();
}

class _ChapterCardState extends ConsumerState<_ChapterCard> {
  bool _open = false;
  bool _busy = false;
  final _deleting = <String>{};

  PastStoryChaptersGateway get _gateway =>
      ref.read(pastStoryChaptersGatewayProvider);

  /// Re-reads through the scope's container, captured before any await, so
  /// the Download my data entry's count refreshes even if this screen was
  /// left mid-delete (review M3).
  void _refresh(ProviderContainer container) {
    container
      ..invalidate(pastStoryChaptersProvider)
      ..invalidate(pastStoryItemsProvider(widget.chapter.relationshipId));
  }

  void _showFailure(Object error, VoidCallback again) {
    if (!mounted) return;
    final f = _deleteFailure(error);
    context.showErrorSnackbar(
      f.message,
      actionLabel: f.retry ? 'Try again' : null,
      onAction: f.retry ? again : null,
    );
  }

  Future<void> _deleteAll() async {
    if (!mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final n = widget.chapter.storyCount;
    // Only a chapter still in the export may suggest a copy (review I1):
    // after 30 days, a seal or the archive, the download no longer has them.
    final ok = await ConfirmationDialog.show(
      context: context,
      type: ConfirmationType.destructive,
      title: 'Delete these stories?',
      message:
          widget.chapter.canDownload
              ? 'Your ${_stories(n)} from this space will be deleted for good. '
                  'If you want a copy, download your data first.'
              : "These can't be downloaded any more. Your ${_stories(n)} "
                  'from this space will be deleted for good.',
      confirmText: 'Delete',
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final gateway = _gateway;
    try {
      final left = await deleteAllMyPastStories(
        gateway,
        widget.chapter.relationshipId,
      );
      if (mounted) {
        if (left <= 0) {
          context.showSuccessSnackbar('Deleted.');
        } else {
          context.showErrorSnackbar(
            'Not all deleted: ${_stories(left)} are left. Try again.',
            actionLabel: 'Try again',
            onAction: () => unawaited(_deleteAll()),
          );
        }
      }
    } catch (e) {
      // Some may be gone already; the refresh below shows what is left.
      _showFailure(e, () => unawaited(_deleteAll()));
    } finally {
      if (mounted) setState(() => _busy = false);
      _refresh(container);
    }
  }

  Future<void> _deleteOne(PastStoryItem item) async {
    if (!mounted) return;
    final ok = await ConfirmationDialog.show(
      context: context,
      type: ConfirmationType.destructive,
      title: 'Delete this story?',
      message: 'It will be deleted for good.',
      confirmText: 'Delete',
    );
    if (ok != true || !mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _deleting.add(item.id));
    try {
      await _gateway.deleteOne(item.id);
    } catch (e) {
      _showFailure(e, () => unawaited(_deleteOne(item)));
    } finally {
      if (mounted) setState(() => _deleting.remove(item.id));
      _refresh(container);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final c = widget.chapter;
    final range =
        c.firstOn == c.lastOn
            ? MyDateFormat.toDateShort(c.firstOn)
            : '${MyDateFormat.toDateShort(c.firstOn)} to '
                '${MyDateFormat.toDateShort(c.lastOn)}';
    final items =
        _open ? ref.watch(pastStoryItemsProvider(c.relationshipId)) : null;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(Spacing.md.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pastStoryChapterTitle(c), style: text.titleMedium),
            Gap(Spacing.xs.h),
            Text(
              MyDateFormat.join([_stories(c.storyCount), range]),
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            Gap(Spacing.md.h),
            Wrap(
              spacing: Spacing.sm.w,
              runSpacing: Spacing.sm.h,
              children: [
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: _target,
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  ),
                  onPressed: _busy ? null : _deleteAll,
                  child: Text(
                    _busy ? 'Deleting…' : 'Delete all ${c.storyCount}',
                    semanticsLabel:
                        _busy
                            ? 'Deleting your stories'
                            : 'Delete all ${_stories(c.storyCount)}',
                  ),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: _target),
                  onPressed: () => setState(() => _open = !_open),
                  child: Text(_open ? 'Hide them' : 'See them'),
                ),
              ],
            ),
            if (items != null) ...[
              Gap(Spacing.sm.h),
              items.when(
                loading:
                    () => Padding(
                      padding: const EdgeInsets.all(Spacing.md),
                      child: _spinner('Loading your stories'),
                    ),
                error:
                    (_, __) => Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: Spacing.sm.w,
                      children: [
                        Text("Couldn't load them.", style: text.bodyMedium),
                        TextButton(
                          style: TextButton.styleFrom(minimumSize: _target),
                          onPressed:
                              () => ref.invalidate(
                                pastStoryItemsProvider(c.relationshipId),
                              ),
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                data:
                    (list) => Column(
                      children: [
                        for (final item in list)
                          ListTile(
                            key: ValueKey(item.id),
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              item.isVideo
                                  ? Icons.videocam_outlined
                                  : Icons.photo_outlined,
                              size: IconSizes.md,
                            ),
                            title: Text(
                              MyDateFormat.join([
                                MyDateFormat.toDate(item.occurredOn),
                                item.isVideo ? 'Video' : 'Photo',
                              ]),
                            ),
                            trailing:
                                _deleting.contains(item.id)
                                    ? Semantics(
                                      label: 'Deleting',
                                      liveRegion: true,
                                      child: SizedBox.fromSize(
                                        size: _target,
                                        child: Center(
                                          child: SizedBox.square(
                                            dimension: IconSizes.md,
                                            child:
                                                const CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                          ),
                                        ),
                                      ),
                                    )
                                    : IconButton(
                                      tooltip:
                                          'Delete the ${_kind(item)} from '
                                          '${MyDateFormat.toDate(item.occurredOn)}',
                                      constraints: BoxConstraints.tight(
                                        _target,
                                      ),
                                      icon: Icon(
                                        Icons.delete_outline,
                                        size: IconSizes.md,
                                      ),
                                      onPressed:
                                          () => unawaited(_deleteOne(item)),
                                    ),
                          ),
                      ],
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
