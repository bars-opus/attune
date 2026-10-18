// Spec 3a: the lifecycle hub is on the couples-locked chat screen (where a
// paused or ended person lands), and Settings offers Pause before End.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  test('the couples-locked chat screen hosts the lifecycle card', () {
    final src = _read(
      'lib/features/chat/presentation/screens/chat_couples_locked_screen.dart',
    );
    expect(src, contains('const RelationshipLifecycleCard()'));
  });

  test(
    'while paused the locked screen offers no invite or Dating (review I10)',
    () {
      final src = _read(
        'lib/features/chat/presentation/screens/chat_couples_locked_screen.dart',
      );
      expect(src, contains('LifecycleStatus.paused'));
      expect(src, contains('else if (!pausedSpace) ...['));
    },
  );

  test(
    'the app shell runs the lifecycle watcher inside the PIN gate (review C3)',
    () {
      final src = _read('lib/app/app_shell.dart');
      final gate = src.indexOf('SafetyLockGate(');
      final watcher = src.indexOf('RelationshipLifecycleWatcher(');
      expect(gate, greaterThan(-1));
      expect(watcher, greaterThan(gate));
    },
  );

  test('Settings: Pause our shared space comes right before End', () {
    final src = _read('lib/features/settings/data/settings_data.dart');
    final pause = src.indexOf("id: 'pause_relationship'");
    final end = src.indexOf("id: 'endRelationship'");
    expect(pause, greaterThan(-1));
    expect(end, greaterThan(pause));
    expect(
      src.substring(pause, end),
      contains('PauseRelationshipAction.confirmAndPause'),
    );
  });

  test('the app ends a relationship through the RPC, as the caller', () {
    final src = _read(
      'lib/features/relationships/data/relationship_lifecycle_service.dart',
    );
    expect(src, contains("_transition('end_relationship', relationshipId)"));
    expect(src, isNot(contains("'end-relationship'")));
  });
}
