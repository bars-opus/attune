import 'package:attune/core/providers/location_provider.dart';
import 'package:attune/core/services/location_service.dart';
import 'package:attune/core/utils/location/location_search_mode.dart';
import 'package:attune/core/utils/location/models/parsed_address.dart';
import 'package:attune/features/planning/presentation/widgets/place_block_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/chat_test_harness.dart' show withScreenUtil;

class _FakeLocations extends LocationService {
  _FakeLocations(this.answer);
  final Future<List<ParsedAddress>> Function() answer;
  final calls = <(String, LocationSearchMode, bool)>[];

  @override
  Future<List<ParsedAddress>> getLocationSuggestions(
    String query, {
    LocationSearchMode mode = LocationSearchMode.city,
    double? proximityLng,
    double? proximityLat,
    bool throwOnFailure = false,
  }) {
    calls.add((query, mode, throwOnFailure));
    return answer();
  }
}

Future<void> _open(WidgetTester tester, LocationService service) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [locationServiceProvider.overrideWithValue(service)],
    child: withScreenUtil(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(onPressed: () => showPlanningPlacePicker(context), child: const Text('open')),
      ),
    )),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('typing searches every kind of place and shows the suggestions', (tester) async {
    final service = _FakeLocations(() async => [
          const ParsedAddress(fullAddress: 'Labadi Beach, Accra, Ghana', placeId: 'p1'),
          const ParsedAddress(fullAddress: 'Labadi Beach Hotel, La Bypass, Accra, Ghana', placeId: 'p2'),
        ]);
    await _open(tester, service);
    await tester.enterText(find.byType(TextField), 'Labadi');
    await tester.pump(const Duration(milliseconds: 450)); // the search waits for a pause in typing
    await tester.pumpAndSettle();
    expect(service.calls.single, ('Labadi', LocationSearchMode.place, true));
    expect(find.text('Labadi Beach'), findsOneWidget);
    expect(find.text('Labadi Beach Hotel'), findsOneWidget);
  });

  testWidgets('when search is unavailable it says so, and the typed name can still be used', (tester) async {
    await _open(tester, _FakeLocations(() async => throw const LocationSearchUnavailable('REQUEST_DENIED')));
    await tester.enterText(find.byType(TextField), 'Labadi');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text("Search isn't available right now. You can still save the name."), findsOneWidget);
    expect(find.text('Use "Labadi"'), findsOneWidget);
  });
}
