import 'dart:async';

import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/paint_ball/models/paint_ball_models.dart';
import 'package:attune/features/games/paint_ball/presentation/state/paint_ball_provider.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PaintBallHistoryScreen extends ConsumerStatefulWidget {
  const PaintBallHistoryScreen({super.key, required this.relationshipId});

  final String relationshipId;

  @override
  ConsumerState<PaintBallHistoryScreen> createState() =>
      _PaintBallHistoryScreenState();
}

class _PaintBallHistoryScreenState
    extends ConsumerState<PaintBallHistoryScreen> {
  final List<PaintBallHistoryEntry> _items = [];
  String? _nextCursor;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _nextCursor = null;
      }
    });

    try {
      final page = await ref
          .read(paintBallServiceProvider)
          .getHistory(
            relationshipId: widget.relationshipId,
            cursor: reset ? null : _nextCursor,
          );
      if (!mounted) return;
      setState(() {
        final known = _items.map((item) => item.sessionId).toSet();
        _items.addAll(page.items.where((item) => known.add(item.sessionId)));
        _nextCursor = page.nextCursor;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load Paint Ball history.';
      });
    }
  }

  Future<void> _hide(PaintBallHistoryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Hide this game?'),
            content: const Text(
              'It will disappear only from your history. Your partner keeps their copy.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Hide'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(paintBallServiceProvider).hideSession(entry.sessionId);
      if (!mounted) return;
      setState(
        () => _items.removeWhere((item) => item.sessionId == entry.sessionId),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not hide that game. Try again.')),
      );
    }
  }

  Future<void> _openRecap(PaintBallHistoryEntry entry) async {
    final action = await context.pushNamed<PaintBallExitAction>(
      'paintBallKnockout',
      pathParameters: {'sessionId': entry.sessionId},
    );
    if (!mounted ||
        action == null ||
        action == PaintBallExitAction.backToChat) {
      return;
    }
    Navigator.of(context).pop(action);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paint Ball history')),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final currentUserId = ref.watch(paintBallCurrentUserIdProvider);

    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items.isEmpty && _error != null) {
      return ListView(
        padding: EdgeInsets.all(Spacing.xl.w),
        children: [
          Gap(MediaQuery.sizeOf(context).height * 0.20),
          Icon(
            Icons.cloud_off_outlined,
            color: colorScheme.onSurface.withValues(alpha: 0.42),
            size: 40.h,
          ),
          Gap(Spacing.md.h),
          Text(_error!, textAlign: TextAlign.center),
          Gap(Spacing.md.h),
          AppButton(
            label: 'Retry',
            onPressed: _load,
            size: ButtonSize.small,
            width: double.infinity,
            animateButton: !reduceMotionOf(context),
          ),
        ],
      );
    }

    if (_items.isEmpty) {
      return ListView(
        padding: EdgeInsets.all(Spacing.xl.w),
        children: [
          Gap(MediaQuery.sizeOf(context).height * 0.20),
          Icon(
            Icons.colorize_outlined,
            color: PaintBallPalette.player,
            size: 42.h,
          ),
          Gap(Spacing.md.h),
          Text(
            'No finished games yet',
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          Gap(Spacing.xs.h),
          Text(
            'Completed matches will appear here, one game at a time.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.58),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        Spacing.md.w,
        Spacing.md.h,
        Spacing.md.w,
        Spacing.xxl.h,
      ),
      itemCount:
          _items.length + (_nextCursor != null || _error != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return Padding(
            padding: EdgeInsets.only(top: Spacing.sm.h),
            child: AppButton(
              label: _error != null ? 'Retry' : 'Load more',
              onPressed: _loading ? null : _load,
              size: ButtonSize.small,
              width: double.infinity,
              isLoading: _loading,
              animateButton: !reduceMotionOf(context),
            ),
          );
        }

        final entry = _items[index];
        final won = entry.winnerUserId == currentUserId;
        final penalty = entry.penaltyType == 'dare' ? 'Dare' : 'Truth';
        final outcome =
            entry.penaltyStatus == 'declined' ? 'skipped' : 'completed';

        return CardInkWell(
          onTap: () => unawaited(_openRecap(entry)),
          padding: EdgeInsets.all(Spacing.md.w),
          margin: EdgeInsets.only(bottom: Spacing.sm.h),
          borderRadius: BorderRadius.circular(12.r),
          child: Row(
            children: [
              Container(
                width: 42.w,
                height: 42.w,
                decoration: BoxDecoration(
                  color: PaintBallPalette.field,
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(
                  Icons.colorize_rounded,
                  color: won ? PaintBallPalette.mine : PaintBallPalette.theirs,
                  size: 22.h,
                ),
              ),
              Gap(Spacing.md.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      won ? 'You landed the final hit' : 'Your partner won',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Gap(Spacing.xs.h),
                    Text(
                      '${_toneLabel(entry.tone)} - $penalty $outcome - ${_dateLabel(entry.completedAt)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.58),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Game options',
                onSelected: (_) => unawaited(_hide(entry)),
                itemBuilder:
                    (_) => const [
                      PopupMenuItem(
                        value: 'hide',
                        child: Row(
                          children: [
                            Icon(Icons.visibility_off_outlined),
                            SizedBox(width: 12),
                            Text('Hide from my history'),
                          ],
                        ),
                      ),
                    ],
              ),
            ],
          ),
        );
      },
    );
  }
}

String _toneLabel(String tone) => switch (tone) {
  'connecting' => 'Connecting',
  'romantic' => 'Romantic',
  _ => 'Playful',
};

String _dateLabel(DateTime value) {
  const months = [
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
  final local = value.toLocal();
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}
