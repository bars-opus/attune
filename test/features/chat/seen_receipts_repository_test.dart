import 'package:attune/features/chat/data/seen_receipts_repository.dart';
import 'package:attune/features/chat/domain/seen_receipts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromJson reads mine/effective and defaults to off', () {
    expect(
      SeenReceipts.fromJson({'mine': true, 'effective': false}),
      const SeenReceipts(mine: true, effective: false),
    );
    expect(SeenReceipts.fromJson(null), SeenReceipts.off);
    expect(SeenReceipts.fromJson({'effective': 'yes'}), SeenReceipts.off);
  });

  test('get and set call the two RPCs with the relationship id', () async {
    final calls = <(String, Map<String, dynamic>)>[];
    final repo = SeenReceiptsRepository((fn, params) async {
      calls.add((fn, params));
      return {'mine': params['p_on'] ?? false, 'effective': false};
    });
    await repo.get('r1');
    final after = await repo.set('r1', true);
    // Records compare a Map field by identity, so check name and params apart.
    expect(calls.map((c) => c.$1), ['get_seen_receipts', 'set_seen_receipts']);
    expect(calls[0].$2, {'p_relationship_id': 'r1'});
    expect(calls[1].$2, {'p_relationship_id': 'r1', 'p_on': true});
    expect(after, const SeenReceipts(mine: true, effective: false));
  });

  test('the subtitle is honest about each state and never names anyone', () {
    expect(
      seenReceiptsSubtitle(const SeenReceipts(mine: true, effective: true)),
      'On for both of you. Read ticks and story seen marks show. Either of you can turn this off.',
    );
    expect(
      seenReceiptsSubtitle(const SeenReceipts(mine: true, effective: false)),
      "Turns on once you've both turned it on.",
    );
    expect(
      seenReceiptsSubtitle(SeenReceipts.off),
      'Off. Read ticks and story seen marks stay hidden for both of you. Turn it on together whenever you like.',
    );
    expect(seenReceiptsTitle, "Show when we've seen things");
    expect(
      seenReceiptsAsk1Line,
      'Read receipts are off to start. Turn them on together whenever you like.',
    );
  });
}
