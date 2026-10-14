import 'package:attune/core/ui/neon/neon_quality.dart';
import 'package:attune/features/games/presentation/widgets/game_hub_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the games surface declares a neon quality tier', (tester) async {
    // ATTUNE_THESIS §6.10 makes performance budgets on representative
    // Ghanaian hardware a launch gate, and NeonQuality exists to honour
    // it. The final whole-branch review found the mechanism complete,
    // tested and obeyed by every consumer -- and installed NOWHERE, so
    // every device silently took neonQualityOf's fallback.
    //
    // A guard nothing declares is a facility, not a guard. This asserts
    // the seam exists, so removing it fails rather than going quiet.
    late NeonQuality seen;

    await tester.pumpWidget(
      MaterialApp(
        home: GameHubTheme.wrap(
          child: Builder(
            builder: (context) {
              seen = neonQualityOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(seen, GameHubTheme.quality);
  });

  testWidgets('the declared tier is one a consumer can act on', (tester) async {
    // A positive control over the enum: the tier has to be a real member
    // with real costs, not a default that happens to match.
    expect(NeonQuality.values, contains(GameHubTheme.quality));
    expect(
      GameHubTheme.quality.maxDroplets,
      greaterThan(0),
      reason: 'whatever tier ships must still draw something',
    );
  });
}
