// Spec 1 §8 W10a: the in-chat Games surfaces (the games sheet from the
// composer, the game card and its trail in the thread, the staged game
// above the composer) get the root cap, because they open over the chat,
// not on a Games route. No Games file is edited, so the cap may only be
// one at which they show no overflow they don't already show at 1.0.
//
// "the measurement" prints, for each phone and text size, the overflows
// that 1.0 doesn't already have (Task 9 reads it to choose the cap); it
// never fails. "the chosen cap" fails if TextScalePolicy.v2Cap lets them
// overflow.
import 'package:attune/app/text_scale_policy.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:attune/features/games/invites/presentation/game_composer_bar.dart';
import 'package:attune/features/games/presentation/providers/game_card_provider.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:attune/features/games/presentation/widgets/game_grid_tile.dart';
import 'package:attune/features/games/presentation/widgets/game_trail_line.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/chat/support/chat_test_harness.dart';
import 'support/large_text_audit.dart';

/// Every size from 1.0 to the highest candidate in 0.05 steps (the phone's
/// own sizes fall between the candidates: Android 1.15, iOS 1.12, 1.24...).
final _steps = [for (var i = 0; i <= 20; i++) 1.0 + i * 0.05];

/// Phones the sheet is checked on, narrowest first.
const _phones = [
  Size(360, 800),
  Size(375, 667),
  Size(390, 844),
  Size(412, 915),
];

Message _game(String id, {required bool mine}) => Message(
  id: id,
  clientMessageId: 'c-$id',
  relationshipId: 'r1',
  senderId: mine ? 'me' : 'partner',
  content: 'Snakes and Ladders',
  createdAt: DateTime(2026, 11, 1),
  status: MessageStatus.delivered,
  isMine: mine,
  mediaType: 'game',
  gameSessionId: 's-$id',
);

/// The overflows in [at] that [atOne] (the same phone at 1.0) doesn't have,
/// or has by fewer pixels (W10 B6 M-6: a worse overflow at a site that
/// already overflows at 1.0 is new too).
Set<String> newOrWorse(Map<String, double> atOne, Map<String, double> at) => {
  for (final MapEntry(key: site, value: px) in at.entries)
    if (!atOne.containsKey(site))
      site
    else if (px > atOne[site]! + 0.5)
      '$site (${px.toStringAsFixed(0)} px, at 1.0 '
          '${atOne[site]!.toStringAsFixed(0)} px)',
};

/// Each overflowing site, with its worst overflow in pixels.
Future<Map<String, double>> _overflowsAt(
  WidgetTester t,
  Size phone,
  double scale,
) {
  setPhone(t, phone, scale);
  return collectOverflowSizes(() async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          activeGamesProvider.overrideWith(
            (ref) async => [
              {
                'id': 'a1',
                'game_type': 'snakes_and_ladders',
                'status': 'active',
                'current_turn_user_id': 'me',
                'updated_at': '2026-11-01T10:00:00Z',
                'created_at': '2026-11-01T10:00:00Z',
              },
            ],
          ),
          recentGamesProvider.overrideWith((ref) async => const []),
          gameSessionEventsProvider.overrideWith((ref) => const Stream.empty()),
          gameCardProvider.overrideWith(
            (ref, id) => Stream.value(
              const GameCardState(
                gameType: 'snakes_and_ladders',
                status: 'active',
                currentTurnUserId: 'me',
                winnerUserId: null,
                currentRound: 3,
                totalRounds: 10,
              ),
            ),
          ),
        ],
        child: withScreenUtil(
          MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            // The root cap under check, as app_shell.dart applies it.
            builder:
                (context, child) => MediaQuery.withClampedTextScaling(
                  maxScaleFactor: scale,
                  child: child!,
                ),
            home: Builder(
              builder:
                  (context) => Scaffold(
                    body: ListView(
                      children: [
                        TextButton(
                          onPressed:
                              () => showChatGamesPicker(
                                context,
                                relationshipId: 'r1',
                                onStageNewGame: (_) {},
                              ),
                          child: const Text('open games'),
                        ),
                        MessageBubble(
                          message: _game('g1', mine: true),
                          currentUserId: 'me',
                          viewerUserId: 'me',
                        ),
                        MessageBubble(
                          message: _game('g2', mine: false),
                          currentUserId: 'me',
                          viewerUserId: 'me',
                        ),
                        const GameTrailLine(
                          label: 'You moved to square 42 in Snakes and Ladders',
                          isMine: true,
                        ),
                        GameComposerBar(
                          relationshipId: 'r1',
                          gameType: 'snakes_and_ladders',
                          onCancel: () {},
                        ),
                      ],
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
    await settle(t, const Duration(milliseconds: 500));
    await t.tap(find.text('open games'));
    await settle(t, const Duration(milliseconds: 1200));
    await scrollToEnd(t);
    // PF-C6: the games sheet really opened and its tiles were laid out (they
    // are what is measured). After the scroll, once its bounce has settled:
    // on 375 x 667 at 2.0 the sheet's header and "Continue playing" fill it
    // before the first tile.
    await settle(t, const Duration(seconds: 1));
    expect(find.byType(GameGridTile), findsWidgets);
    await t.pumpWidget(const SizedBox());
    await settle(t, const Duration(seconds: 1));
  }).then((list) {
    final worst = <String, double>{};
    for (final (site, px) in list) {
      if (px > (worst[site] ?? -1)) worst[site] = px;
    }
    return worst;
  });
}

void main() {
  test('a worse overflow at a site 1.0 already has counts (W10 B6 M-6)', () {
    const tile =
        'lib/features/games/presentation/widgets/game_grid_tile.dart:50';
    expect(newOrWorse({tile: 12}, {tile: 12}), isEmpty);
    expect(newOrWorse({tile: 12}, {tile: 12.4}), isEmpty, reason: 'rounding');
    expect(newOrWorse({tile: 12}, {tile: 40}), hasLength(1));
    expect(newOrWorse({}, {tile: 1}), {tile});
    expect(newOrWorse({tile: 12}, {}), isEmpty);
  });

  group('the measurement', () {
    for (final phone in _phones) {
      testWidgets('${phone.width.toInt()} x ${phone.height.toInt()}', (
        t,
      ) async {
        final atOne = await _overflowsAt(t, phone, 1.0);
        final lines = <String>[];
        for (final scale in _steps.skip(1)) {
          final extra = newOrWorse(atOne, await _overflowsAt(t, phone, scale));
          if (extra.isNotEmpty) {
            lines.add('  ${scale.toStringAsFixed(2)}: ${extra.join(', ')}');
          }
        }
        // ignore: avoid_print
        print(
          'IN-CHAT GAMES ${phone.width.toInt()}x${phone.height.toInt()} '
          '(at 1.0: ${atOne.isEmpty ? 'none' : atOne.keys.join(', ')})\n'
          '${lines.isEmpty ? '  no new overflow up to 2.0' : lines.join('\n')}',
        );
      });
    }
  });

  group('the chosen cap', () {
    for (final phone in _phones) {
      testWidgets(
        '${phone.width.toInt()} wide: nothing new up to ${TextScalePolicy.v2Cap}',
        (t) async {
          final atOne = await _overflowsAt(t, phone, 1.0);
          for (final scale in _steps.where((s) => s <= TextScalePolicy.v2Cap)) {
            final extra = newOrWorse(
              atOne,
              await _overflowsAt(t, phone, scale),
            );
            expect(extra, isEmpty, reason: 'at ${scale.toStringAsFixed(2)}');
          }
        },
      );
    }
  });
}
