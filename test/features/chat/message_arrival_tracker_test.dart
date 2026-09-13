import 'package:attune/features/chat/presentation/widgets/message_arrival_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessageArrivalTracker', () {
    test('baselines initial history without animating it', () {
      final tracker = MessageArrivalTracker();

      expect(
        tracker.sync(
          const ['newest', 'older'],
          initialLoading: false,
          loadingMore: false,
        ),
        isEmpty,
      );
    });

    test(
      'animates a later insertion regardless of its timestamp or position',
      () {
        final tracker = MessageArrivalTracker();
        tracker.sync(
          const ['newest', 'older'],
          initialLoading: false,
          loadingMore: false,
        );

        expect(
          tracker.sync(
            const ['newest', 'delayed-arrival', 'older'],
            initialLoading: false,
            loadingMore: false,
          ),
          {'delayed-arrival'},
        );
      },
    );

    test('an initially empty conversation establishes an empty baseline', () {
      final tracker = MessageArrivalTracker();
      tracker.sync(const [], initialLoading: false, loadingMore: false);

      expect(
        tracker.sync(
          const ['first-message'],
          initialLoading: false,
          loadingMore: false,
        ),
        {'first-message'},
      );
    });

    test('does not mistake history appended by pagination for arrivals', () {
      final tracker = MessageArrivalTracker();
      tracker.sync(
        const ['newest', 'oldest-loaded'],
        initialLoading: false,
        loadingMore: false,
      );
      tracker.sync(
        const ['newest', 'oldest-loaded'],
        initialLoading: false,
        loadingMore: true,
      );

      expect(
        tracker.sync(
          const ['newest', 'oldest-loaded', 'page-1', 'page-2'],
          initialLoading: false,
          loadingMore: false,
        ),
        isEmpty,
      );
    });

    test('still detects a realtime insertion while pagination completes', () {
      final tracker = MessageArrivalTracker();
      tracker.sync(
        const ['newest', 'oldest-loaded'],
        initialLoading: false,
        loadingMore: false,
      );
      tracker.sync(
        const ['newest', 'oldest-loaded'],
        initialLoading: false,
        loadingMore: true,
      );

      expect(
        tracker.sync(
          const ['realtime', 'newest', 'oldest-loaded', 'page-1', 'page-2'],
          initialLoading: false,
          loadingMore: false,
        ),
        {'realtime'},
      );
    });

    test('never replays an id that was removed and later restored', () {
      final tracker = MessageArrivalTracker();
      tracker.sync(
        const ['initial'],
        initialLoading: false,
        loadingMore: false,
      );
      expect(
        tracker.sync(
          const ['arrival', 'initial'],
          initialLoading: false,
          loadingMore: false,
        ),
        {'arrival'},
      );
      tracker.sync(
        const ['initial'],
        initialLoading: false,
        loadingMore: false,
      );

      expect(
        tracker.sync(
          const ['arrival', 'initial'],
          initialLoading: false,
          loadingMore: false,
        ),
        isEmpty,
      );
    });
  });
}
