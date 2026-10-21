import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/ui/motion/settle_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/home_card_order_repository.dart';

/// One movable card on Conversations, below the chat. [id] is what the
/// person's order is saved by; [label] is how a screen reader names it.
class HomeCard {
  const HomeCard({required this.id, required this.label, required this.child});
  final String id;
  final String label;
  final Widget child;
}

/// [saved] in its own order, without cards that no longer exist, then any
/// card it doesn't know yet at the end; the default ([available]) when
/// nothing is saved.
List<String> resolveHomeCardOrder(
  List<String>? saved,
  List<String> available,
) => [
  for (final id in saved ?? const <String>[])
    if (available.contains(id)) id,
  for (final id in available)
    if (!(saved ?? const <String>[]).contains(id)) id,
];

/// The person's own saved order: null until it loads, and null for good if
/// it can't (the default order shows either way). A move shows at once and
/// is saved in the background.
class HomeCardOrderController extends AsyncNotifier<List<String>?> {
  @override
  Future<List<String>?> build() async {
    try {
      return await ref.read(homeCardOrderRepositoryProvider).load();
    } catch (_) {
      return null;
    }
  }

  Future<void> reorder(List<String> order) async {
    state = AsyncData(order);
    try {
      await ref.read(homeCardOrderRepositoryProvider).save(order);
    } catch (_) {
      // Kept on screen for now; the next move saves again.
    }
  }
}

final homeCardOrderProvider =
    AsyncNotifierProvider<HomeCardOrderController, List<String>?>(
      HomeCardOrderController.new,
    );

/// The cards below the chat, in the person's own order. Long-press a card
/// to lift it, then drag; a tap still opens it. Screen readers get Move up
/// and Move down. Anything above (stories, the chat) stays where it is.
class ReorderableHomeCards extends ConsumerWidget {
  const ReorderableHomeCards({
    super.key,
    required this.cards,
    this.animateIn = false,
    this.firstStep = 0,
  });
  final List<HomeCard> cards;

  /// The cards settle in, in turn, as the screen first shows ([firstStep]:
  /// how many settled before them, so they follow on). A card's settle
  /// stays with it when it's moved, so a move never replays it.
  final bool animateIn;
  final int firstStep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byId = {for (final c in cards) c.id: c};
    final order = resolveHomeCardOrder(
      ref.watch(homeCardOrderProvider).valueOrNull,
      [for (final c in cards) c.id],
    );
    final still = reduceMotionOf(context);

    final haptics = ref.read(hapticsProvider);

    // A light tap when a card lands somewhere new; nothing if it didn't move.
    void move(int from, int to) {
      final next = [...order];
      final id = next.removeAt(from);
      next.insert(to.clamp(0, next.length), id);
      if (next.indexOf(id) == from) return;
      haptics.light();
      ref.read(homeCardOrderProvider.notifier).reorder(next);
    }

    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      buildDefaultDragHandles: false,
      // A medium tap as a card lifts: picked up.
      onReorderStart: (_) => haptics.medium(),
      // The lifted card rises a little; with reduce motion it just moves.
      proxyDecorator:
          (child, index, animation) =>
              still
                  ? child
                  : AnimatedBuilder(
                    animation: animation,
                    builder:
                        (context, child) => Transform.scale(
                          scale:
                              1 +
                              0.02 * Curves.easeOut.transform(animation.value),
                          child: Material(
                            color: Colors.transparent,
                            elevation: 8 * animation.value,
                            borderRadius: BorderRadius.circular(24),
                            child: child,
                          ),
                        ),
                    child: child,
                  ),
      onReorder: (from, to) => move(from, to > from ? to - 1 : to),
      children: [
        for (final (i, id) in order.indexed)
          ReorderableDelayedDragStartListener(
            key: ValueKey('home-card-$id'),
            index: i,
            child: Semantics(
              label: byId[id]!.label,
              customSemanticsActions: {
                if (i > 0)
                  const CustomSemanticsAction(label: 'Move up'):
                      () => move(i, i - 1),
                if (i < order.length - 1)
                  const CustomSemanticsAction(label: 'Move down'):
                      () => move(i, i + 1),
              },
              child: SettleIn(
                animate: animateIn,
                // The Stagger timing: each a little after the one before.
                duration: Duration(milliseconds: 260 + 60 * (firstStep + i)),
                child: byId[id]!.child,
              ),
            ),
          ),
      ],
    );
  }
}
