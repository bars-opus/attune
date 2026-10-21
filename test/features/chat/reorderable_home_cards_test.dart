// Conversations: the cards below the chat (Journals, Together, any added
// later) can be put in each person's own order — long-press to lift and
// drag, or Move up / Move down for screen readers. The order is saved for
// that person; until it loads, or if it can't, the default order shows.
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/features/chat/data/home_card_order_repository.dart';
import 'package:attune/features/chat/presentation/widgets/reorderable_home_cards.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Memory implements HomeCardOrderRepository {
  _Memory([this.saved, this.failLoad = false]);
  List<String>? saved;
  final bool failLoad;
  final writes = <List<String>>[];
  @override
  Future<List<String>?> load() async {
    if (failLoad) throw Exception('offline');
    return saved;
  }

  @override
  Future<void> save(List<String> order) async {
    writes.add(order);
    saved = order;
  }
}

var _taps = 0;

Widget _card(String text) => SizedBox(
  height: 120,
  child: Card(
    child: InkWell(onTap: () => _taps++, child: Center(child: Text(text))),
  ),
);

var _haptics = FakeHaptics();

Future<_Memory> _pump(WidgetTester t, _Memory repo) async {
  _haptics = FakeHaptics();
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        homeCardOrderRepositoryProvider.overrideWithValue(repo),
        hapticsProvider.overrideWithValue(_haptics),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              const SizedBox(height: 80, child: Text('Chat (fixed)')),
              ReorderableHomeCards(
                cards: [
                  HomeCard(
                    id: 'journals',
                    label: 'Journals',
                    child: _card('Journals card'),
                  ),
                  HomeCard(
                    id: 'together',
                    label: 'Together',
                    child: _card('Together card'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return repo;
}

List<String> _order(WidgetTester t) {
  final y = {
    for (final s in ['Journals card', 'Together card'])
      s: t.getTopLeft(find.text(s)).dy,
  };
  return (y.keys.toList()..sort((a, b) => y[a]!.compareTo(y[b]!)));
}

void main() {
  group('resolveHomeCardOrder', () {
    test(
      'the saved order, without cards that are gone, with new ones at the end',
      () {
        expect(
          resolveHomeCardOrder(
            ['together', 'old', 'journals'],
            ['journals', 'together', 'pulse'],
          ),
          ['together', 'journals', 'pulse'],
        );
      },
    );

    test('nothing saved: the default order', () {
      expect(resolveHomeCardOrder(null, ['journals', 'together']), [
        'journals',
        'together',
      ]);
    });
  });

  testWidgets('nothing saved: Journals, then Together', (t) async {
    await _pump(t, _Memory());
    expect(_order(t), ['Journals card', 'Together card']);
  });

  testWidgets('a saved order is the order on screen', (t) async {
    await _pump(t, _Memory(['together', 'journals']));
    expect(_order(t), ['Together card', 'Journals card']);
  });

  testWidgets('long-press, drag, drop: the new order shows and is saved', (
    t,
  ) async {
    final repo = await _pump(t, _Memory());
    final drag = await t.startGesture(t.getCenter(find.text('Journals card')));
    await t.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    // Past the other card, a step at a time (the list reorders as it goes).
    for (var i = 0; i < 10; i++) {
      await drag.moveBy(const Offset(0, 20));
      await t.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await t.pumpAndSettle();
    expect(_order(t), ['Together card', 'Journals card']);
    expect(repo.writes, [
      ['together', 'journals'],
    ]);
  });

  group('haptics', () {
    Future<void> dragJournals(WidgetTester t, double by) async {
      final drag = await t.startGesture(t.getCenter(find.text('Journals card')));
      await t.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      for (var i = 0; i < 10; i++) {
        await drag.moveBy(Offset(0, by / 10));
        await t.pump(const Duration(milliseconds: 16));
      }
      await drag.up();
      await t.pumpAndSettle();
    }

    testWidgets('a medium tap on lift, a light one when it lands somewhere new', (t) async {
      await _pump(t, _Memory());
      await dragJournals(t, 200);
      expect((_haptics.mediumCount, _haptics.lightCount), (1, 1));
    });

    testWidgets('dropped where it started: only the lift', (t) async {
      await _pump(t, _Memory());
      await dragJournals(t, 10);
      expect((_haptics.mediumCount, _haptics.lightCount), (1, 0));
    });
  });

  testWidgets('a tap still opens the card', (t) async {
    _taps = 0;
    await _pump(t, _Memory());
    await t.tap(find.text('Together card'));
    await t.pumpAndSettle();
    expect(_taps, 1);
  });

  testWidgets('screen readers can move a card down and up', (t) async {
    final semantics = t.ensureSemantics();
    final repo = await _pump(t, _Memory());
    final journals = t.getSemantics(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Journals',
      ),
    );
    t.binding.pipelineOwner.semanticsOwner!.performAction(
      journals.id,
      SemanticsAction.customAction,
      CustomSemanticsAction.getIdentifier(
        const CustomSemanticsAction(label: 'Move down'),
      ),
    );
    await t.pumpAndSettle();
    expect(repo.writes.last, ['together', 'journals']);
    expect(_order(t), ['Together card', 'Journals card']);
    semantics.dispose();
  });

  testWidgets('if the order can\'t load, the default order shows', (t) async {
    await _pump(t, _Memory(['together', 'journals'], true));
    expect(_order(t), ['Journals card', 'Together card']);
  });
}
