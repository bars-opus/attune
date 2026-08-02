// test/home/relationship_mode_resync_signal_test.dart
import 'package:attune/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Proves the actual bug the prior (reverted) fix missed: writing to
  // SharedPreferences alone does not make HomeScreen rebuild when a
  // Navigator pop reveals it again, because FutureBuilder does not
  // re-invoke its builder for an already-resolved, unchanged future. An
  // explicit listener-based signal is required. This test verifies the
  // signal/listener contract itself (a ValueNotifier a State object can
  // subscribe to and have invoked on-demand, independent of any widget
  // rebuild/navigation), which is the actual mechanism HomeScreen relies
  // on — not a full HomeScreen integration test, which would require
  // mocking Supabase auth/relationships beyond this test's scope.
  test('relationshipModeResyncSignal invokes a registered listener when bumped', () {
    var callCount = 0;
    void listener() => callCount++;

    relationshipModeResyncSignal.addListener(listener);
    addTearDown(() => relationshipModeResyncSignal.removeListener(listener));

    expect(callCount, 0);
    relationshipModeResyncSignal.value++;
    expect(callCount, 1);
    relationshipModeResyncSignal.value++;
    expect(callCount, 2);
  });

  test('removing the listener stops further notifications', () {
    var callCount = 0;
    void listener() => callCount++;

    relationshipModeResyncSignal.addListener(listener);
    relationshipModeResyncSignal.value++;
    expect(callCount, 1);

    relationshipModeResyncSignal.removeListener(listener);
    relationshipModeResyncSignal.value++;
    expect(callCount, 1); // unchanged — listener no longer registered
  });

  testWidgets(
    'a State object subscribed via addListener in initState is invoked without any widget rebuild',
    (tester) async {
      var syncCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: _ListenerProbe(onSignal: () => syncCalls++),
        ),
      );
      expect(syncCalls, 0);

      // Simulates exactly what EndRelationshipAction does: bump the
      // signal from code with no reference to the listening State and no
      // knowledge of whether that State's widget is the visible route.
      relationshipModeResyncSignal.value++;
      // No pump/rebuild triggered here on purpose — addListener callbacks
      // fire synchronously on notifyListeners, independent of the pump
      // cycle, which is exactly the property this fix depends on (a
      // route sitting underneath an active push must still react).
      expect(syncCalls, 1);
    },
  );
}

class _ListenerProbe extends StatefulWidget {
  const _ListenerProbe({required this.onSignal});
  final VoidCallback onSignal;

  @override
  State<_ListenerProbe> createState() => _ListenerProbeState();
}

class _ListenerProbeState extends State<_ListenerProbe> {
  @override
  void initState() {
    super.initState();
    relationshipModeResyncSignal.addListener(widget.onSignal);
  }

  @override
  void dispose() {
    relationshipModeResyncSignal.removeListener(widget.onSignal);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
