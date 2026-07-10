import 'dart:async';

import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatInsightsScreen extends ConsumerStatefulWidget {
  const ChatInsightsScreen({
    super.key,
    required this.relationshipId,
    required this.partnerName,
  });

  final String relationshipId;
  final String partnerName;

  @override
  ConsumerState<ChatInsightsScreen> createState() => _ChatInsightsScreenState();
}

class _ChatInsightsScreenState extends ConsumerState<ChatInsightsScreen> {
  bool _markedViewed = false;
  ProviderSubscription<AsyncValue<List<ChatInsightItem>>>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = ref.listenManual<AsyncValue<List<ChatInsightItem>>>(
      chatInsightsProvider(widget.relationshipId),
      (_, next) {
        final insights = next.valueOrNull;
        if (_markedViewed || insights == null) return;
        final unreadIds =
            insights
                .where((item) => item.isUnread)
                .map((item) => item.id)
                .toList();
        if (unreadIds.isEmpty) return;
        _markedViewed = true;
        unawaited(() async {
          await ref
              .read(chatContextRepositoryProvider)
              .markInsightsViewed(unreadIds);
          ref.invalidate(chatHeaderSnapshotProvider(widget.relationshipId));
          ref.invalidate(chatInsightsProvider(widget.relationshipId));
        }());
      },
    );
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insightsAsync = ref.watch(
      chatInsightsProvider(widget.relationshipId),
    );

    return Scaffold(
      appBar: AppBar(title: Text('${widget.partnerName} insights')),
      body: insightsAsync.when(
        data: (insights) {
          if (insights.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No shared-pattern insights are ready yet. As more relationship data settles, Attune will surface private reflections here.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: insights.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final insight = insights[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            insight.isUnread
                                ? Icons.mark_chat_unread_outlined
                                : Icons.lightbulb_outline,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _labelForType(insight.type),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          Text(
                            _formatDate(insight.createdAt),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        insight.body,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (_, __) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Insights are unavailable right now. Please try again shortly.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
      ),
    );
  }

  String _labelForType(String type) {
    switch (type) {
      case 'translator_pattern':
        return 'Translator pattern';
      default:
        return 'Relationship insight';
    }
  }

  String _formatDate(DateTime value) {
    final month = _monthNames[value.month - 1];
    return '$month ${value.day}';
  }
}

const _monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
