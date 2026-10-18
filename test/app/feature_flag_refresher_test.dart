// Sync audit (2026-10-18): a flag turned on or off (a dev snippet, or the
// owner in production) reaches a running app the next time it comes back
// to the foreground, without a relaunch.
import 'package:attune/app/feature_flag_refresher.dart';
import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:attune/features/quiet_states/presentation/quiet_state_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('flags are read again when the app resumes', (tester) async {
    var reads = 0;
    var on = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          quietStatesEnabledProvider.overrideWith((ref) async {
            reads++;
            return on;
          }),
        ],
        child: MaterialApp(
          home: FeatureFlagRefresher(
            child: Consumer(
              builder:
                  (_, ref, __) => Text(
                    '${ref.watch(quietStatesEnabledProvider).valueOrNull}',
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('false'), findsOneWidget);
    expect(reads, 1);

    on = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('true'), findsOneWidget);
  });

  test('every Spec 5/7/8 and map flag is refreshed', () {
    expect(refreshedFlagProviders.length, greaterThanOrEqualTo(7));
  });

  // Sync audit: the map flag is named once, with the others.
  test('the couple map flag is a ChatFeatureFlags key, default off', () {
    expect(ChatFeatureFlags.coupleMap, 'couple_map_enabled');
    expect(ChatFeatureFlags.defaultFor(ChatFeatureFlags.coupleMap), isFalse);
    final literal = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('chat_feature_flags.dart'))
        .where((f) => f.readAsStringSync().contains("'couple_map_enabled'"))
        .map((f) => f.path);
    expect(literal, isEmpty);
  });
}
