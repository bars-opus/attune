import 'dart:async';

import 'package:attune/features/games/this_or_that/data/models/this_or_that_session.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/session_history_card.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SessionHistoryScreen extends ConsumerStatefulWidget {
  const SessionHistoryScreen({super.key});

  @override
  ConsumerState<SessionHistoryScreen> createState() =>
      _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends ConsumerState<SessionHistoryScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<ThisOrThatSession> _sessions = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _cursor;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_loadInitialSessions());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialSessions() async {
    if (mounted) {
      setState(() {
        _isLoading = _sessions.isEmpty;
        _error = null;
      });
    }
    try {
      final sessions = await ref.refresh(completedSessionsProvider.future);
      if (!mounted) return;
      setState(() {
        _sessions
          ..clear()
          ..addAll(sessions);
        _hasMore = sessions.length >= 20;
        _cursor =
            sessions.isEmpty ? null : sessions.last.createdAt.toIso8601String();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Your past games could not be loaded. Check your connection.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _cursor == null) return;
    setState(() => _isLoadingMore = true);

    try {
      final moreSessions = await ref.read(
        completedSessionsCursorProvider(_cursor).future,
      );
      if (!mounted) return;
      setState(() {
        final knownIds = _sessions.map((session) => session.id).toSet();
        _sessions.addAll(
          moreSessions.where((session) => knownIds.add(session.id)),
        );
        _hasMore = moreSessions.length >= 20;
        if (moreSessions.isNotEmpty) {
          _cursor = moreSessions.last.createdAt.toIso8601String();
        }
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('More games could not be loaded yet.')),
      );
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 220) {
      unawaited(_loadMore());
    }
  }

  Future<void> _hideSession(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            icon: const Icon(Icons.visibility_off_outlined),
            title: const Text('Hide this game?'),
            content: const Text(
              'It disappears from your history only. Your partner keeps their copy.',
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep it'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Hide'),
              ),
            ],
          ),
    );

    if (confirmed != true || !mounted) return;
    try {
      ref.invalidate(hideSessionProvider(sessionId));
      await ref.read(hideSessionProvider(sessionId).future);
      if (!mounted) return;
      setState(
        () => _sessions.removeWhere((session) => session.id == sessionId),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Game hidden from your view.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That game could not be hidden yet.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);

    return ThisOrThatGameScaffold(
      title: 'Past games',
      child:
          _isLoading
              ? const Center(
                key: Key('this-or-that-history-loading'),
                child: ThisOrThatWaitingMark(size: 104),
              )
              : RefreshIndicator(
                onRefresh: _loadInitialSessions,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    if (_error != null && _sessions.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _HistoryStatus(
                          icon: Icons.cloud_off_rounded,
                          title: 'History is out of reach',
                          message: _error!,
                          actionLabel: 'Try again',
                          onAction: _loadInitialSessions,
                        ),
                      )
                    else if (_sessions.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _HistoryStatus(
                          icon: Icons.style_rounded,
                          title: 'Your reveals will live here',
                          message:
                              'Finish a game together, then return to the picks that started a conversation.',
                          actionLabel: 'Play This or That',
                          onAction: () => Navigator.pop(context),
                        ),
                      )
                    else ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text(
                            'Revisit a game without changing anything your partner sees.',
                            textAlign: TextAlign.center,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(
                              color: palette.mutedInk,
                              height: 1.4,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),
                      SliverList.separated(
                        itemCount: _sessions.length,
                        itemBuilder: (context, index) {
                          final session = _sessions[index];
                          return SessionHistoryCard(
                            session: session,
                            onHide: () => _hideSession(session.id),
                            onTap:
                                () => context.pushNamed(
                                  'thisOrThatSessionDetail',
                                  extra: session.id,
                                ),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                      ),
                    ],
                    if (_isLoadingMore)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Center(
                            child: SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  ],
                ),
              ),
    );
  }
}

class _HistoryStatus extends StatelessWidget {
  const _HistoryStatus({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: palette.thatSurface,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(icon, size: 34, color: palette.thatColor),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.mutedInk,
              height: 1.4,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}
