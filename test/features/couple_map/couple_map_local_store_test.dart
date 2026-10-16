// test/features/couple_map/couple_map_local_store_test.dart
import 'package:attune/features/couple_map/data/couple_map_local_store.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test('pin choice: off until chosen, then remembered', () async {
    final s = MemoryCoupleMapLocalStore();
    expect(await readPinLastChoice(s), isFalse);
    await writePinLastChoice(s, true);
    expect(await readPinLastChoice(s), isTrue);
  });

  test('home area round-trips and clears', () async {
    final s = MemoryCoupleMapLocalStore();
    expect(await readHomeArea(s), isNull);
    await writeHomeArea(s, const HomeArea(lat: 5.556, lng: -0.197));
    final h = await readHomeArea(s);
    expect((h!.lat, h.lng), (5.556, -0.197));
    await writeHomeArea(s, null);
    expect(await readHomeArea(s), isNull);
  });

  test('a corrupt home area reads as none', () async {
    final s =
        MemoryCoupleMapLocalStore()
          ..values[CoupleMapLocalKeys.homeArea] = 'not json';
    expect(await readHomeArea(s), isNull);
  });
}
