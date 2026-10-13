import 'package:attune/core/services/location_service.dart';
import 'package:attune/core/utils/location/location_search_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each search mode sends its own Places types filter; place sends none, so venues come back too', () {
    expect(LocationService.autocompleteParams('Accra', key: 'k', mode: LocationSearchMode.city)['types'], '(cities)');
    expect(LocationService.autocompleteParams('Osu', key: 'k', mode: LocationSearchMode.address)['types'], 'geocode');
    final place = LocationService.autocompleteParams('Labadi Beach', key: 'k', mode: LocationSearchMode.place);
    expect(place.containsKey('types'), isFalse, reason: 'beaches, restaurants, hotels and addresses alike');
    expect(place['input'], 'Labadi Beach');
    expect(place['key'], 'k');
  });

  test('proximity biases the search only when both coordinates are known', () {
    final near = LocationService.autocompleteParams('cafe', key: 'k', mode: LocationSearchMode.place, lat: 5.6, lng: -0.18);
    expect(near['location'], '5.6,-0.18');
    expect(near['radius'], '50000');
    expect(LocationService.autocompleteParams('cafe', key: 'k', mode: LocationSearchMode.place, lat: 5.6).containsKey('location'),
        isFalse);
  });

  test('with no API key, a caller that asks is told search is unavailable instead of getting "no results"', () async {
    // Tests run without dart-defines, so there is no key: exactly the broken setup.
    final service = LocationService();
    await expectLater(
      service.getLocationSuggestions('Labadi Beach', mode: LocationSearchMode.place, throwOnFailure: true),
      throwsA(isA<LocationSearchUnavailable>()),
    );
    expect(await service.getLocationSuggestions('Labadi Beach'), isEmpty, reason: 'other screens keep their behaviour');
  });
}
