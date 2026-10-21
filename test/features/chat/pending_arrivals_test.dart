import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/features/chat/presentation/widgets/pending_arrivals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 10, 19, 12);

  test('an arrival built within the window animates once', () {
    final pending = PendingArrivals();
    pending.add(['a'], t0);
    expect(
      pending.take('a', t0.add(const Duration(milliseconds: 200))),
      isTrue,
    );
    expect(
      pending.take('a', t0.add(const Duration(milliseconds: 300))),
      isFalse,
      reason: 'consumed',
    );
  });

  test('an arrival first built after the window is simply there', () {
    final pending = PendingArrivals();
    pending.add(['late'], t0);
    expect(
      pending.take(
        'late',
        t0.add(kArrivalAnimationWindow + const Duration(milliseconds: 1)),
      ),
      isFalse,
    );
    expect(pending.isEmpty, isTrue, reason: 'expired ids are dropped');
  });

  test('re-adding a pending id does not extend its window', () {
    // Re-added INSIDE the window (an expired entry is pruned on add, so a
    // later re-add is a new arrival — see below).
    final pending = PendingArrivals();
    pending.add(['a'], t0);
    pending.add(['a'], t0.add(const Duration(seconds: 1)));
    expect(
      pending.take(
        'a',
        t0.add(kArrivalAnimationWindow + const Duration(milliseconds: 1)),
      ),
      isFalse,
    );
  });

  test('add prunes ids whose window has passed (T8 carry)', () {
    // An arrival whose row is never built (scrolled away, then deleted, or
    // a history row) used to stay in the map for the whole session.
    final pending = PendingArrivals();
    pending.add(['never-built'], t0);
    pending.add(
      ['b'],
      t0.add(kArrivalAnimationWindow + const Duration(milliseconds: 1)),
    );
    expect(pending.debugPendingIds, {'b'});
  });

  test('an id re-added after its window lapsed is a fresh arrival', () {
    // A game card that moved again after its first move's row was never
    // built: the new move is a new "just now".
    final pending = PendingArrivals();
    pending.add(['card'], t0);
    final later = t0.add(const Duration(seconds: 5));
    pending.add(['card'], later);
    expect(
      pending.take('card', later.add(const Duration(milliseconds: 100))),
      isTrue,
    );
  });

  test('unknown ids are never arrivals', () {
    expect(PendingArrivals().take('x', t0), isFalse);
  });
}
