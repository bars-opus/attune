// lib/features/planning/presentation/screens/planning_home_screen.dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/app_divider.dart';
import 'package:attune/core/widgets/buttons/app_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../data/repositories/planning_error.dart';
import '../../data/models/planning_goal_model.dart';
import '../../data/models/planning_task_model.dart';
import '../providers/planning_providers.dart';
import '../widgets/planning_goal_row.dart';
import '../widgets/planning_task_row.dart';
import 'create_planning_goal_screen.dart';
import 'create_planning_task_screen.dart';
import 'create_planning_event_screen.dart';

/// Three sections, not tabs (spec §6.2): Goals, Tasks, Events, each
/// with its own "+". Notes is deliberately NOT a fourth section here —
/// there is no `PlanningNotesScreen` yet (a later task on top of this
/// plan owns it); this screen has nothing to route to for Notes today,
/// so no Notes row is added rather than linking to a screen that does
/// not exist.
class PlanningHomeScreen extends ConsumerWidget {
  const PlanningHomeScreen({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planning'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.read(planningGoalsProvider(relationshipId).notifier).refresh(),
            ref.read(planningTasksProvider(relationshipId).notifier).refresh(),
            ref.read(planningEventsProvider(
              PlanningEventsKey(relationshipId: relationshipId, upcoming: true),
            ).notifier).refresh(),
          ]);
        },
        child: ListView(
          padding: EdgeInsets.all(Spacing.md),
          children: [
            _SectionHeader(
              title: 'Goals',
              onAdd: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CreatePlanningGoalScreen(relationshipId: relationshipId),
              )),
            ),
            _GoalsSection(relationshipId: relationshipId),
            Gap(Spacing.md),
            const AppDivider(),
            Gap(Spacing.md),
            _SectionHeader(
              title: 'Tasks',
              onAdd: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CreatePlanningTaskScreen(relationshipId: relationshipId),
              )),
            ),
            _TasksSection(relationshipId: relationshipId),
            Gap(Spacing.md),
            const AppDivider(),
            Gap(Spacing.md),
            _SectionHeader(
              title: 'Events',
              onAdd: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CreatePlanningEventScreen(relationshipId: relationshipId),
              )),
            ),
            _EventsSection(relationshipId: relationshipId),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onAdd});
  final String title;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        AppIconButton(icon: Icons.add, onPressed: onAdd, size: 36, iconSize: 20),
      ],
    );
  }
}

class _GoalsSection extends ConsumerWidget {
  const _GoalsSection({required this.relationshipId});
  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(planningGoalsProvider(relationshipId));
    return goalsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _SectionError(
        message: 'Could not load goals.',
        onRetry: () => ref.read(planningGoalsProvider(relationshipId).notifier).refresh(),
      ),
      data: (goals) {
        if (goals.isEmpty) {
          return const _EmptySectionText('No goals yet.');
        }
        // Incomplete first (spec §6.2).
        final sorted = [...goals]
          ..sort((a, b) {
            if (a.isComplete != b.isComplete) {
              return a.isComplete ? 1 : -1;
            }
            return b.updatedAt.compareTo(a.updatedAt);
          });
        return Column(
          children: [
            for (final goal in sorted)
              _ExpandableGoal(relationshipId: relationshipId, goal: goal),
          ],
        );
      },
    );
  }
}

class _ExpandableGoal extends ConsumerStatefulWidget {
  const _ExpandableGoal({required this.relationshipId, required this.goal});
  final String relationshipId;
  final PlanningGoalModel goal;

  @override
  ConsumerState<_ExpandableGoal> createState() => _ExpandableGoalState();
}

class _ExpandableGoalState extends ConsumerState<_ExpandableGoal> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PlanningGoalRow(
          goal: widget.goal,
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded)
          Padding(
            padding: EdgeInsets.only(left: Spacing.lg),
            child: Consumer(
              builder: (context, ref, _) {
                final tasksAsync = ref.watch(planningGoalTasksProvider(widget.goal.id));
                return tasksAsync.when(
                  loading: () => const SizedBox(
                    height: 32,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  error: (_, __) => const _SectionError(message: 'Could not load tasks.'),
                  data: (tasks) => Column(
                    children: [
                      for (final task in tasks)
                        PlanningTaskRow(
                          task: task,
                          onToggleComplete: (isComplete) => _toggleTask(task, isComplete),
                          onTap: () => _confirmDelete(task),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _toggleTask(PlanningTaskModel task, bool isComplete) async {
    final repository = ref.read(planningRepositoryProvider);
    try {
      await repository.setTaskCompletion(taskId: task.id, isComplete: isComplete);
      ref.invalidate(planningGoalTasksProvider(widget.goal.id));
      ref.read(planningGoalsProvider(widget.relationshipId).notifier).refresh();
    } on PlanningError catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  Future<void> _confirmDelete(PlanningTaskModel task) async {
    // Long-press to delete, matching this project's existing message
    // long-press-to-act convention rather than inventing a swipe
    // gesture for this one list.
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text('Delete "${task.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return;

    final repository = ref.read(planningRepositoryProvider);
    try {
      await repository.deleteItem(id: task.id);
      ref.invalidate(planningGoalTasksProvider(widget.goal.id));
      ref.read(planningGoalsProvider(widget.relationshipId).notifier).refresh();
    } on PlanningError catch (error) {
      if (!mounted) return;
      // The sole-child-delete rejection surfaces here as a
      // PlanningValidationError. Rather than a generic error toast,
      // spec §6.2 requires the two-choice prompt: delete the goal
      // instead, or add another task first.
      if (error is PlanningValidationError &&
          error.message.contains('Delete the goal instead')) {
        await _offerDeleteGoalInstead(error.message);
        return;
      }
      _showError(error);
    }
  }

  Future<void> _offerDeleteGoalInstead(String message) async {
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete_goal'),
            child: const Text('Delete this goal instead'),
          ),
        ],
      ),
    );
    if (choice != 'delete_goal' || !mounted) return;

    final repository = ref.read(planningRepositoryProvider);
    try {
      await repository.deleteItem(id: widget.goal.id);
      ref.read(planningGoalsProvider(widget.relationshipId).notifier).refresh();
    } on PlanningError catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  void _showError(PlanningError error) {
    final message = switch (error) {
      PlanningValidationError(message: final m) => m,
      PlanningUnauthorizedError() => 'Planning is no longer available.',
      PlanningNotFoundError() => 'That item is no longer there.',
      PlanningNetworkError() => 'Could not reach the server. Try again.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TasksSection extends ConsumerWidget {
  const _TasksSection({required this.relationshipId});
  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(planningTasksProvider(relationshipId));
    return tasksAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _SectionError(
        message: 'Could not load tasks.',
        onRetry: () => ref.read(planningTasksProvider(relationshipId).notifier).refresh(),
      ),
      data: (tasks) {
        if (tasks.isEmpty) return const _EmptySectionText('No tasks yet.');
        return Column(
          children: [
            for (final task in tasks)
              _TopLevelTaskRow(relationshipId: relationshipId, task: task),
          ],
        );
      },
    );
  }
}

/// A top-level Task row's own toggle handler, following the identical
/// optimistic-mutation ordering as `_ExpandableGoalState._toggleTask`
/// above: this provider's list is a `PlanningKeysetPager`, which has no
/// per-item optimistic-update method of its own (only whole-page
/// `refresh()`/`loadMore()`), so the optimism happens at THIS widget's
/// level — apply the flipped-completion value to local state
/// immediately, call the RPC, then on success replace with the RPC's
/// authoritative row (its `completed_at` is server-generated, never
/// the client's guess) via a full provider refresh, or on failure roll
/// back to the exact pre-mutation task captured before this call
/// started (never to "whatever refresh() has now" — a concurrent
/// partner edit may have already changed that).
class _TopLevelTaskRow extends ConsumerStatefulWidget {
  const _TopLevelTaskRow({required this.relationshipId, required this.task});
  final String relationshipId;
  final PlanningTaskModel task;

  @override
  ConsumerState<_TopLevelTaskRow> createState() => _TopLevelTaskRowState();
}

class _TopLevelTaskRowState extends ConsumerState<_TopLevelTaskRow> {
  // The optimistic local override, if a mutation is in flight or its
  // result hasn't yet round-tripped through a provider refresh. Null
  // means "trust the provider's own state" (the common case).
  PlanningTaskModel? _optimisticTask;

  // The last task instance this widget was actually rebuilt with FROM
  // THE PROVIDER (i.e. widget.task, not our own optimistic override).
  // Used to tell "the provider gave us a genuinely new row" (a real
  // refresh landed — drop the override and trust it) apart from "we
  // are rebuilding for some unrelated reason while widget.task hasn't
  // changed at all" (e.g. our own setState from the optimistic apply
  // itself, which must NOT wipe the override it just set).
  late PlanningTaskModel _lastProviderTask;

  @override
  void initState() {
    super.initState();
    _lastProviderTask = widget.task;
  }

  @override
  void didUpdateWidget(_TopLevelTaskRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only clear the optimistic override when the INCOMING widget.task
    // is not the same object the last provider-driven build saw — that
    // is what "a fresh provider refresh actually landed" looks like.
    // Comparing widget.task to oldWidget.task instead would also be
    // true on this very setState's own rebuild (since neither side of
    // that comparison is ever our optimistic value — the parent always
    // passes the provider's task straight through), wiping the
    // override the instant it's set.
    if (!identical(widget.task, _lastProviderTask)) {
      _lastProviderTask = widget.task;
      _optimisticTask = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = _optimisticTask ?? widget.task;
    return PlanningTaskRow(
      task: task,
      onToggleComplete: (isComplete) => _toggleTask(task, isComplete),
    );
  }

  Future<void> _toggleTask(PlanningTaskModel preMutationTask, bool isComplete) async {
    // 1. Apply the mutation locally, right away.
    setState(() {
      _optimisticTask = PlanningTaskModel(
        id: preMutationTask.id,
        relationshipId: preMutationTask.relationshipId,
        createdBy: preMutationTask.createdBy,
        parentGoalId: preMutationTask.parentGoalId,
        title: preMutationTask.title,
        note: preMutationTask.note,
        assignedTo: preMutationTask.assignedTo,
        dueDate: preMutationTask.dueDate,
        // Client-guessed only for the optimistic frame — never treated
        // as authoritative. The real value comes from the RPC below.
        completedAt: isComplete ? DateTime.now() : null,
        createdAt: preMutationTask.createdAt,
        updatedAt: preMutationTask.updatedAt,
      );
    });

    final repository = ref.read(planningRepositoryProvider);
    try {
      // 2. Call the RPC.
      final authoritative = await repository.setTaskCompletion(
        taskId: preMutationTask.id,
        isComplete: isComplete,
      );
      if (!mounted) return;
      // 3. Success: replace the optimistic guess with the RPC's own
      // returned row (its completed_at is server-generated) and let
      // the provider's own refresh bring the list back in sync.
      setState(() => _optimisticTask = authoritative);
      ref.read(planningTasksProvider(widget.relationshipId).notifier).refresh();
    } on PlanningError catch (error) {
      if (!mounted) return;
      // 4. Failure: roll back to the PRE-mutation state captured at
      // the top of this method — not to whatever the provider's
      // current state happens to be now, which a concurrent partner
      // edit may have already changed.
      setState(() => _optimisticTask = preMutationTask);
      _showError(error);
    }
  }

  void _showError(PlanningError error) {
    final message = switch (error) {
      PlanningValidationError(message: final m) => m,
      PlanningUnauthorizedError() => 'Planning is no longer available.',
      PlanningNotFoundError() => 'That item is no longer there.',
      PlanningNetworkError() => 'Could not reach the server. Try again.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EventsSection extends ConsumerWidget {
  const _EventsSection({required this.relationshipId});
  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = PlanningEventsKey(relationshipId: relationshipId, upcoming: true);
    final eventsAsync = ref.watch(planningEventsProvider(key));
    return eventsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _SectionError(
        message: 'Could not load events.',
        onRetry: () => ref.read(planningEventsProvider(key).notifier).refresh(),
      ),
      data: (events) {
        if (events.isEmpty) return const _EmptySectionText('No upcoming events.');
        return Column(
          children: [
            for (final event in events)
              ListTile(
                leading: const Icon(Icons.event_outlined),
                title: Text(event.title),
                dense: true,
              ),
          ],
        );
      },
    );
  }
}

class _EmptySectionText extends StatelessWidget {
  const _EmptySectionText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(message)),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
