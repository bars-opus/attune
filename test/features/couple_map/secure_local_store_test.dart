import 'package:attune/features/couple_map/data/couple_map_local_store.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the secure store reads, writes and deletes (device only)', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final s = SecureCoupleMapLocalStore();
    expect(await s.read(CoupleMapLocalKeys.homeArea), isNull);
    await writeHomeArea(s, const HomeArea(lat: 5.556, lng: -0.197));
    expect((await readHomeArea(s))!.lat, 5.556);
    await writePinLastChoice(s, true);
    expect(await readPinLastChoice(s), isTrue);
    for (final k in CoupleMapLocalKeys.all) {
      await s.delete(k);
    }
    expect(await readHomeArea(s), isNull);
    expect(await readPinLastChoice(s), isFalse);
  });
}
