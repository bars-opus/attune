// Spec 2 W3b: an in-memory setup gateway; every call is recorded, and a
// test can make any call fail the test (the off-country no-call proof).
import 'dart:async';

import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_repository.dart';

const ghanaLists = DatingSetupLists(
  countries: [
    DatingCountryLists(
      code: 'GB',
      sameGender: true,
      regions: [
        DatingRegion(code: 'TLI', nameKey: 'dating_region_gb_tli', open: true),
        DatingRegion(code: 'TLM', nameKey: 'dating_region_gb_tlm', open: true),
      ],
      faiths: [
        DatingFaith(
          code: 'christian',
          nameKey: 'dating_faith_christian',
          denominations: [
            DatingOption(
              code: 'catholic',
              nameKey: 'dating_denomination_catholic',
            ),
          ],
        ),
        DatingFaith(code: 'none', nameKey: 'dating_faith_none'),
      ],
    ),
    DatingCountryLists(
      code: 'GH',
      sameGender: false,
      regions: [
        DatingRegion(
          code: 'AA',
          nameKey: 'dating_region_gh_aa',
          open: true,
          sides: [
            DatingOption(code: 'accra', nameKey: 'dating_side_gh_accra'),
            DatingOption(code: 'tema', nameKey: 'dating_side_gh_tema'),
          ],
        ),
        DatingRegion(code: 'AH', nameKey: 'dating_region_gh_ah', open: true),
        DatingRegion(code: 'TV', nameKey: 'dating_region_gh_tv', open: false),
      ],
      faiths: [
        DatingFaith(
          code: 'christian',
          nameKey: 'dating_faith_christian',
          denominations: [
            DatingOption(
              code: 'catholic',
              nameKey: 'dating_denomination_catholic',
            ),
            DatingOption(
              code: 'methodist',
              nameKey: 'dating_denomination_methodist',
            ),
          ],
        ),
        DatingFaith(code: 'muslim', nameKey: 'dating_faith_muslim'),
      ],
    ),
  ],
  phoneCountry: 'GH',
  defaultAges: (25, 35),
);

class FakeDatingSetupGateway implements DatingSetupGateway {
  FakeDatingSetupGateway({
    this.profile = const DatingMyProfile(),
    this.listsValue = ghanaLists,
  });

  DatingMyProfile profile;
  DatingSetupLists listsValue;
  final calls = <(String, Map<String, Object?>)>[];
  DatingWrite answer = const DatingWrite(ok: true);
  Completer<DatingMyProfile>? holdProfile;

  /// Called before every write; throw (or fail) to forbid a call.
  void Function(String name, Map<String, Object?> args)? guard;

  Future<DatingWrite> _w(
    String name,
    Map<String, Object?> args,
    String next,
  ) async {
    guard?.call(name, args);
    calls.add((name, args));
    return answer.ok ? DatingWrite(ok: true, nextStep: next) : answer;
  }

  @override
  Future<DatingSetupLists> lists() async {
    calls.add(('lists', const {}));
    return listsValue;
  }

  @override
  Future<DatingMyProfile> myProfile() async {
    calls.add(('myProfile', const {}));
    final hold = holdProfile;
    if (hold != null) return hold.future;
    return profile;
  }

  @override
  Future<DatingWrite> saveIntention(
    String key, {
    required String intention,
    String? timeline,
    required bool timelineVisible,
    String? marital,
    required bool maritalVisible,
  }) => _w('saveIntention', {
    'key': key,
    'intention': intention,
    'timeline': timeline,
    'timelineVisible': timelineVisible,
    'marital': marital,
    'maritalVisible': maritalVisible,
  }, 'where');

  @override
  Future<DatingWrite> saveLocation(
    String key, {
    required String country,
    required String region,
    String? side,
    required String scope,
  }) => _w('saveLocation', {
    'key': key,
    'country': country,
    'region': region,
    'side': side,
    'scope': scope,
  }, 'privacy');

  @override
  Future<DatingWrite> agreeAndBegin(String key) =>
      _w('agreeAndBegin', {'key': key}, 'you');

  @override
  Future<DatingWrite> saveIdentity(
    String key, {
    required String identity,
    String? specific,
    String? pronouns,
    List<String> extraPools = const [],
    required bool visible,
  }) => _w('saveIdentity', {
    'key': key,
    'identity': identity,
    'specific': specific,
    'pronouns': pronouns,
    'extraPools': extraPools,
    'visible': visible,
  }, 'meet');

  @override
  Future<DatingWrite> saveWhoToMeet(
    String key, {
    required List<String> seeking,
    required int minAge,
    required int maxAge,
  }) => _w('saveWhoToMeet', {
    'key': key,
    'seeking': seeking,
    'minAge': minAge,
    'maxAge': maxAge,
  }, 'children');

  @override
  Future<DatingWrite> saveChildren(
    String key, {
    required bool have,
    required String want,
    required bool mustMatch,
    required bool excludeParents,
  }) => _w('saveChildren', {
    'key': key,
    'have': have,
    'want': want,
    'mustMatch': mustMatch,
    'excludeParents': excludeParents,
  }, 'faith');

  @override
  Future<DatingWrite> saveFaith(
    String key, {
    required String faith,
    String? denomination,
    required String importance,
    required bool visible,
  }) => _w('saveFaith', {
    'key': key,
    'faith': faith,
    'denomination': denomination,
    'importance': importance,
    'visible': visible,
  }, 'photos');

  @override
  Future<DatingWrite> clearFaith(String key) =>
      _w('clearFaith', {'key': key}, 'photos');

  @override
  Future<DatingWrite> savePrompts(String key, List<(String, String)> items) =>
      _w('savePrompts', {'key': key, 'items': items}, 'verify');

  @override
  Future<DatingWrite> saveDisplayName(String key, String name) =>
      _w('saveDisplayName', {'key': key, 'name': name}, 'preview');

  @override
  Future<DatingWrite> saveSettings(String key, Map<String, Object> values) =>
      _w('saveSettings', {'key': key, 'values': values}, '');

  /// The last write (a re-read of the profile after a save is no write).
  (String, Map<String, Object?>) get lastWrite =>
      calls.lastWhere((c) => c.$1 != 'lists' && c.$1 != 'myProfile');

  Iterable<String> get writes =>
      calls.map((c) => c.$1).where((n) => n != 'lists' && n != 'myProfile');
}

/// The UK row alone (for a Tier 1 phone on a UK profile).
const ghanaListsUk = DatingCountryLists(
  code: 'GB',
  sameGender: true,
  regions: [
    DatingRegion(code: 'TLI', nameKey: 'dating_region_gb_tli', open: true),
  ],
);
