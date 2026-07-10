// lib/features/games/this_or_that/presentation/screens/session_history_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/this_or_that/data/models/this_or_that_session.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/session_detail_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/session_history_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SessionHistoryScreen extends ConsumerStatefulWidget {
  const SessionHistoryScreen({super.key});

  @override
  ConsumerState<SessionHistoryScreen> createState() =>
      _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends ConsumerState<SessionHistoryScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  String? _cursor;
  final List<ThisOrThatSession> _sessions = [];
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadInitialSessions();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialSessions() async {
    ref.invalidate(completedSessionsProvider);
    final sessions = await ref.read(completedSessionsProvider.future);
    if (mounted) {
      setState(() {
        _sessions.clear();
        _sessions.addAll(sessions);
        _hasMore = sessions.length >= 20;
        _cursor =
            sessions.isNotEmpty
                ? sessions.last.createdAt.toIso8601String()
                : null;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final moreSessions = await ref.read(
        completedSessionsCursorProvider(_cursor).future,
      );
      if (mounted) {
        setState(() {
          _sessions.addAll(moreSessions);
          _hasMore = moreSessions.length >= 20;
          _cursor =
              moreSessions.isNotEmpty
                  ? moreSessions.last.createdAt.toIso8601String()
                  : null;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _hideSession(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Hide this session?'),
            content: const Text(
              'This session will be hidden from your view only. '
              'Your partner will still be able to see it.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Hide'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await ref.read(hideSessionProvider(sessionId).future);
      await _loadInitialSessions();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Session hidden')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Game history'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadInitialSessions,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            if (_sessions.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history_outlined,
                        size: 64,
                        color: colorScheme.onSurface.withOpacity(0.3),
                      ),
                      Gap(Spacing.md.h),
                      Text('No game history yet', style: textTheme.titleMedium),
                      Gap(Spacing.sm.h),
                      Text(
                        'Play a game of This or That to see your history here.',
                        style: textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      Gap(Spacing.lg.h),
                      AppButton(
                        label: 'Play This or That',
                        onPressed: () {
                          Navigator.pop(context);
                          // Navigate to games hub
                        },
                      ),
                    ],
                  ),
                ),
              ),
            if (_sessions.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final session = _sessions[index];
                  return SessionHistoryCard(
                    session: session,
                    onHide: () => _hideSession(session.id),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => SessionDetailScreen(sessionId: session.id),
                        ),
                      ).then((_) => _loadInitialSessions());
                    },
                  );
                }, childCount: _sessions.length),
              ),
            if (_isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
