import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/schimmer_skeleton.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz_providers;
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:attune/features/timeline/presentation/widgets/moments_list.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../together_providers.dart';

/// Every moment, newest first, a page at a time (spec §6.3; plan R8).
class TogetherMemoriesScreen extends ConsumerStatefulWidget {
  const TogetherMemoriesScreen({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  ConsumerState<TogetherMemoriesScreen> createState() =>
      _TogetherMemoriesScreenState();
}

class _TogetherMemoriesScreenState
    extends ConsumerState<TogetherMemoriesScreen> {
  static const _page = 30;
  final List<TimelineEventModel> _items = [];
  bool _loading = false;
  bool _done = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Bumped by every refresh: a page that was asked for before it answers
  /// into a list that no longer exists, and is dropped.
  int _gen = 0;

  /// The next page, from the last moment on screen.
  Future<void> _load() async {
    if (_loading || _done) return;
    final gen = _gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final last = _items.isEmpty ? null : _items.last;
      final page = await ref
          .read(togetherRepositoryProvider)
          .listMoments(
            widget.relationshipId,
            beforeDate: last?.occurredAt,
            beforeId: last?.id,
            limit: _page,
          );
      if (!mounted || gen != _gen) return;
      setState(() {
        _items.addAll(page);
        _done = page.length < _page;
      });
    } catch (e) {
      if (mounted && gen == _gen) setState(() => _error = e);
    } finally {
      if (mounted && gen == _gen) setState(() => _loading = false);
    }
  }

  /// Re-reads what is on screen (up to the server's 100) without clearing
  /// it, so an edit or a resume doesn't jump me back to the top.
  Future<void> _refresh() async {
    final gen = ++_gen;
    final want = _items.length.clamp(_page, 100);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(togetherRepositoryProvider)
          .listMoments(widget.relationshipId, limit: want);
      if (!mounted || gen != _gen) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page);
        _done = page.length < want;
      });
    } catch (e) {
      if (mounted && gen == _gen) setState(() => _error = e);
    } finally {
      if (mounted && gen == _gen) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Edits, deletes, new moments and app resume: refresh in place.
    ref.listen(
      togetherChangeSignalProvider(widget.relationshipId),
      (_, __) => _refresh(),
    );
    final me = ref.watch(togetherMeProvider) ?? '';
    final partner =
        ref.watch(quiz_providers.partnerNameProvider).valueOrNull ?? 'Partner';
    final Widget body;
    if (_items.isEmpty && _loading) {
      body = ListView(
        padding: EdgeInsets.all(Spacing.md.w),
        children: [
          for (var i = 0; i < 4; i++) ...[
            SchimmerSkeleton(height: 96.h),
            Gap(Spacing.sm.h),
          ],
        ],
      );
    } else if (_items.isEmpty && _error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load your memories.'),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    } else {
      body = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 600) _load();
          return false;
        },
        child: ListView(
          padding: EdgeInsets.all(Spacing.md.w),
          children: [
            MomentsList(
              events: _items,
              currentUserId: me,
              currentMonth: DateTime.now(),
              onDateSelected: (_) {},
              partnerName: partner,
            ),
            if (_loading)
              Padding(
                padding: EdgeInsets.all(Spacing.md.w),
                child: const Center(child: CircularProgressIndicator()),
              ),
            if (_error != null && _items.isNotEmpty)
              TextButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('All memories')),
      body: body,
    );
  }
}
