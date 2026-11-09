// Spec 2 W3b Task 5 fix round 1 (M-1): the person's own answers compare by
// every field and never print a value (special category data).
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _full = DatingMyProfile(
  intention: 'long_term',
  marriageTimeline: 'few_years',
  marital: 'divorced',
  countryCode: 'GH',
  regionCode: 'AA',
  sideCode: 'tema',
  regionScope: 'region',
  identity: 'non_binary',
  specific: 'genderqueer',
  specificText: 'my own words',
  pronouns: 'they_them',
  pools: ['women'],
  seeking: ['nonbinary_seeker'],
  minAge: 27,
  maxAge: 41,
  childrenHave: true,
  childrenWant: 'open',
  faith: 'muslim',
  denomination: 'sufi_branch',
  importance: 'must_share',
  displayName: 'Abena',
  prompts: [('p_sunday', 'a quiet walk by Labadi')],
  dropTime: '19:30',
);

void main() {
  test('toString is one fixed text: no value, no field name', () {
    final text = _full.toString();
    expect(text, datingMyProfileText);
    expect(text, 'DatingMyProfile(…)');
    expect(const DatingMyProfile().toString(), text);
    expect('$_full', text);
    for (final name in [
      'intention',
      'marriageTimeline',
      'marital',
      'countryCode',
      'regionCode',
      'sideCode',
      'regionScope',
      'identity',
      'specific',
      'specificText',
      'pronouns',
      'pools',
      'seeking',
      'minAge',
      'maxAge',
      'childrenHave',
      'childrenWant',
      'faith',
      'denomination',
      'importance',
      'displayName',
      'prompts',
      'dropTime',
      'answered',
    ]) {
      expect(text, isNot(contains(name)), reason: name);
    }
    for (final value in [
      'long_term',
      'few_years',
      'divorced',
      'GH',
      'AA',
      'tema',
      'non_binary',
      'genderqueer',
      'my own words',
      'they_them',
      'women',
      'nonbinary_seeker',
      '27',
      '41',
      'open',
      'muslim',
      'sufi_branch',
      'must_share',
      'Abena',
      'p_sunday',
      'Labadi',
      '19:30',
    ]) {
      expect(text, isNot(contains(value)), reason: value);
    }
  });

  test('equal only when every field is equal', () {
    const copy = DatingMyProfile(
      intention: 'long_term',
      marriageTimeline: 'few_years',
      marital: 'divorced',
      countryCode: 'GH',
      regionCode: 'AA',
      sideCode: 'tema',
      regionScope: 'region',
      identity: 'non_binary',
      specific: 'genderqueer',
      specificText: 'my own words',
      pronouns: 'they_them',
      pools: ['women'],
      seeking: ['nonbinary_seeker'],
      minAge: 27,
      maxAge: 41,
      childrenHave: true,
      childrenWant: 'open',
      faith: 'muslim',
      denomination: 'sufi_branch',
      importance: 'must_share',
      displayName: 'Abena',
      prompts: [('p_sunday', 'a quiet walk by Labadi')],
      dropTime: '19:30',
    );
    expect(copy, _full);
    expect(copy.hashCode, _full.hashCode);
    expect(const DatingMyProfile(), const DatingMyProfile());
    // Lists by value, not identity (two reads build two lists).
    DatingMyProfile fresh() => DatingMyProfile(
      pools: List.of(['women']),
      seeking: List.of(['man']),
      prompts: List.of([('p1', 'a')]),
    );
    expect(fresh(), fresh());
    expect(fresh().hashCode, fresh().hashCode);
    // Fields the old toString-based equality never saw.
    expect(
      const DatingMyProfile(childrenWant: 'yes'),
      isNot(const DatingMyProfile(childrenWant: 'no')),
    );
    expect(
      const DatingMyProfile(minAge: 25),
      isNot(const DatingMyProfile(minAge: 26)),
    );
    expect(
      const DatingMyProfile(faithVisible: true),
      isNot(const DatingMyProfile()),
    );
    expect(
      const DatingMyProfile(chatPush: false),
      isNot(const DatingMyProfile()),
    );
    expect(
      const DatingMyProfile(prompts: [('p1', 'a')]),
      isNot(const DatingMyProfile(prompts: [('p1', 'b')])),
    );
    expect(
      const DatingMyProfile(seeking: ['man']),
      isNot(const DatingMyProfile(seeking: ['woman'])),
    );
  });

  // T5 fix round 2: the lists models print nothing of their content either
  // (the setup lists carry the person's own phone country).
  test('the lists models print no code, key or country', () {
    const option = DatingOption(code: 'tema', nameKey: 'dating_side_gh_tema');
    const region = DatingRegion(
      code: 'AA',
      nameKey: 'dating_region_gh_aa',
      open: true,
      sides: [option],
    );
    const faith = DatingFaith(code: 'muslim', nameKey: 'dating_faith_muslim');
    const country = DatingCountryLists(
      code: 'GH',
      sameGender: false,
      regions: [region],
      faiths: [faith],
    );
    const lists = DatingSetupLists(
      countries: [country],
      phoneCountry: 'GH',
      noteCountry: 'GH',
      defaultAges: (27, 41),
    );
    for (final model in <Object>[option, region, faith, country, lists]) {
      final text = model.toString();
      for (final value in ['tema', 'AA', 'muslim', 'GH', 'dating_', '27']) {
        expect(text, isNot(contains(value)), reason: '$text: $value');
      }
    }
  });
}
