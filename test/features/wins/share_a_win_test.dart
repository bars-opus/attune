// Spec 7 (research 06 B2, B9 (b)): "Share a win" and the support chips.
import 'dart:io';

import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/wins/domain/win_card.dart';
import 'package:attune/features/wins/presentation/share_win_sheet.dart';
import 'package:attune/features/wins/presentation/support_chips_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import '../together/together_repository_test.dart' show FakeTogetherGateway;

Widget _app(Widget home, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(home: Scaffold(body: home)),
      ),
    );

void main() {
  test('the ask-about-it draft: the title, then the one question; no AI', () {
    expect(
      winDraft('Got the grant!'),
      'Got the grant! What was the best part?',
    );
    expect(
      winDraft('Passed my driving test.'),
      'Passed my driving test! What was the best part?',
    );
    expect(winDraft('  new job  '), 'new job! What was the best part?');
  });

  test('cards parse from rows', () {
    final c = WinCard.fromRow({
      'event_id': 'e1',
      'title': 'Got the grant!',
      'created_at': '2026-10-18T09:00:00Z',
    });
    expect([c.eventId, c.title], ['e1', 'Got the grant!']);
  });

  testWidgets('sharing a win sends title and note; nothing without a title', (
    t,
  ) async {
    final g = FakeTogetherGateway({'share_a_win': (_) => 'e1'});
    await t.pumpWidget(
      _app(
        const ShareWinSheet(relationshipId: 'r1'),
        overrides: [
          togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
        ],
      ),
    );
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Share'))
          .onPressed,
      isNull,
    );
    await t.enterText(
      find.byKey(const ValueKey('win-title')),
      'Got the grant!',
    );
    await t.enterText(
      find.byKey(const ValueKey('win-note')),
      'Three years of work',
    );
    await t.pump();
    await t.tap(find.text('Share'));
    await t.pump();
    expect(g.calls.single.$1, 'share_a_win');
    expect(g.calls.single.$2, {
      'p_relationship_id': 'r1',
      'p_title': 'Got the grant!',
      'p_note': 'Three years of work',
    });
  });

  testWidgets(
    'support chips put a fixed, editable draft in the composer; they never send',
    (t) async {
      String? picked;
      await t.pumpWidget(_app(SupportChipsSheet(onPick: (d) => picked = d)));
      expect(find.text('I need to vent'), findsOneWidget);
      expect(find.text('Help me decide'), findsOneWidget);
      expect(find.text('Just sit with me'), findsOneWidget);
      await t.tap(find.text('Just sit with me'));
      expect(picked, 'Can you just sit with me for a bit?');
    },
  );

  test('no counts, totals or streaks in the feature (M15)', () {
    for (final f
        in Directory(
          'lib/features/wins',
        ).listSync(recursive: true).whereType<File>()) {
      final src = f.readAsStringSync();
      expect(
        RegExp(r'\b(count|total|streak)\b', caseSensitive: false).hasMatch(src),
        isFalse,
        reason: f.path,
      );
      expect(RegExp(r'\.length\}').hasMatch(src), isFalse, reason: f.path);
    }
  });
}
