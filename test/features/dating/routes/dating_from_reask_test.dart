// Spec 2 W3 final fix (client I-3, M-8, M-9): R-40's `?from=` return, on
// the real routes. A save that clears answers the server needs again is
// never a silent pop: save_dating_location erases gender and who-to-meet
// on any change of Dating country; save_dating_identity erases who-to-meet
// on an identity change where same-gender is off. The step is replaced by
// D5 (then D6) with the same `from`, and D6 goes back. M-8: the kill-switch
// "Choose again" goes D5, D6, then back to Me. M-9: a `from` step with no
// stack (re-opened through the unlock) goes to its place, never forward.
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/features/dating/card/dating_card.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/setup/dating_preview_providers.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/me/presentation/widgets/dating_slot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_photos_fakes.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';

DatingMyProfile _profile({
  String? country = 'GH',
  String? region = 'AA',
  String? identity = 'woman',
  List<String> seeking = const ['man'],
}) => DatingMyProfile(
  intention: 'marriage',
  countryCode: country,
  regionCode: region,
  regionScope: 'region',
  identity: identity,
  seeking: seeking,
  minAge: 25,
  maxAge: 35,
  displayName: 'Ama',
);

/// The setup fake, clearing what the live writers clear.
class _Server extends FakeDatingSetupGateway {
  _Server(DatingMyProfile p) : super(profile: p);

  /// After the next write, the profile read fails (the fallback rule).
  bool readFailsAfterWrite = false;
  bool _wrote = false;

  @override
  Future<DatingMyProfile> myProfile() async {
    if (_wrote && readFailsAfterWrite) {
      calls.add(('myProfile', const {}));
      throw StateError('read');
    }
    return super.myProfile();
  }

  @override
  Future<DatingWrite> saveLocation(
    String key, {
    required String country,
    required String region,
    String? side,
    required String scope,
  }) async {
    final w = await super.saveLocation(
      key,
      country: country,
      region: region,
      side: side,
      scope: scope,
    );
    final old = profile.countryCode;
    final moved = old != null && old != country;
    profile = _profile(
      country: country,
      region: region,
      identity: moved ? null : profile.identity,
      seeking: moved ? const [] : profile.seeking,
    );
    _wrote = true;
    return w;
  }

  @override
  Future<DatingWrite> saveIdentity(
    String key, {
    required String identity,
    String? specific,
    String? pronouns,
    List<String> extraPools = const [],
    required bool visible,
  }) async {
    final w = await super.saveIdentity(
      key,
      identity: identity,
      specific: specific,
      pronouns: pronouns,
      extraPools: extraPools,
      visible: visible,
    );
    final sameGender = listsValue.country(profile.countryCode)?.sameGender;
    final cleared = sameGender != true && profile.identity != identity;
    profile = _profile(
      country: profile.countryCode,
      region: profile.regionCode,
      identity: identity,
      seeking: cleared ? const [] : profile.seeking,
    );
    _wrote = true;
    return w;
  }

  @override
  Future<DatingWrite> saveWhoToMeet(
    String key, {
    required List<String> seeking,
    required int minAge,
    required int maxAge,
  }) async {
    final w = await super.saveWhoToMeet(
      key,
      seeking: seeking,
      minAge: minAge,
      maxAge: maxAge,
    );
    profile = _profile(
      country: profile.countryCode,
      region: profile.regionCode,
      identity: profile.identity,
      seeking: seeking,
    );
    _wrote = true;
    return w;
  }
}

final _card = DatingCard.fromJson({
  'display_name': 'Ama',
  'age': 29,
  'region_name_key': 'dating_region_gh_aa',
  'intention': 'marriage',
  'marriage_timeline': null,
  'children_have': false,
  'children_want': 'yes',
  'gender': null,
  'pronouns': null,
  'faith': null,
  'marital': null,
  'prompts': const [],
  'photos_after_mutual': false,
  'photos': const [],
});

final _slotRoute = GoRoute(
  path: '/slot',
  builder:
      (_, __) => Scaffold(
        body: SingleChildScrollView(
          child: DatingSlot(home: snapshotOf(homeJson(path: 'dating'))),
        ),
      ),
);

Future<DatingShell> _shell(
  WidgetTester t,
  _Server setup, {
  String initial = '/home',
  DatingHome home = const DatingHome(
    state: DatingHomeState.active,
    hasData: true,
  ),
}) => pumpDatingShell(
  t,
  initial: initial,
  home: FakeDatingHomeGateway(home: home),
  extraRoutes: [_slotRoute],
  overrides: [
    datingSetupGatewayProvider.overrideWithValue(setup),
    datingPreviewGatewayProvider.overrideWithValue(
      FakeDatingPreviewGateway(_card),
    ),
    datingPhotosGatewayProvider.overrideWithValue(FakeDatingPhotosGateway()),
    pushAskerProvider.overrideWithValue(FakePushAsker()),
    deviceCountryProvider.overrideWith(
      (ref) async => (sim: null, region: null),
    ),
  ],
);

Future<void> _moveToLondon(WidgetTester t) async {
  await tapInReach(t, find.text('Country'));
  await t.pumpAndSettle();
  await tapInReach(t, find.text('the United Kingdom').last);
  await t.pumpAndSettle();
  await tapInReach(t, find.text('Region'));
  await t.pumpAndSettle();
  await tapInReach(t, find.text('London').last);
  await t.pumpAndSettle();
}

Future<void> _continue(WidgetTester t) async {
  await tapInReach(t, find.text('Continue'));
  await t.pumpAndSettle();
}

const _d3 = 'Where are you?';
const _d5 = 'Which best describes you?';
const _d6 = 'Who would you like to meet?';
const _d7 = 'Children';
const _d12 = 'This is what others see';
const _settings = 'Dating settings';

void main() {
  group('I-3: a save that clears answers asks for them again', () {
    testWidgets('Settings -> How far -> a new country: D5, D6, then back', (
      t,
    ) async {
      final setup = _Server(_profile());
      final s = await _shell(t, setup);
      s.router.push(DatingPaths.settings);
      await t.pumpAndSettle();
      await tapInReach(t, find.text('How far'));
      await t.pumpAndSettle();
      expect(find.text(_d3), findsOneWidget);
      await _moveToLondon(t);
      await _continue(t);
      expect(find.text(_settings), findsNothing);
      expect(find.text(_d5), findsOneWidget);
      await tapInReach(t, find.text('Woman'));
      await t.pumpAndSettle();
      await _continue(t);
      expect(find.text(_d6), findsOneWidget);
      await tapInReach(t, find.text('Men'));
      await t.pumpAndSettle();
      await _continue(t);
      expect(find.text(_settings), findsOneWidget);
      expect(find.text(_d7), findsNothing);
      expect(setup.writes, ['saveLocation', 'saveIdentity', 'saveWhoToMeet']);
      expect(setup.profile.identity, 'woman');
      expect(setup.profile.seeking, ['man']);
      // The steps replaced each other: Back from settings leaves Dating.
      await tapInReach(t, find.byTooltip('Back'));
      await t.pumpAndSettle();
      expect(find.text(_d3), findsNothing);
      expect(find.text(_d5), findsNothing);
      expect(find.textContaining('ME '), findsOneWidget);
    });

    testWidgets('Settings -> How far, same country: straight back', (t) async {
      final setup = _Server(_profile());
      final s = await _shell(t, setup);
      s.router.push(DatingPaths.settings);
      await t.pumpAndSettle();
      await tapInReach(t, find.text('How far'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Region'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Ashanti').last);
      await t.pumpAndSettle();
      await _continue(t);
      expect(find.text(_settings), findsOneWidget);
      expect(setup.writes, ['saveLocation']);
    });

    testWidgets('D12 "Edit where you are" -> a new country: D5, D6, D12', (
      t,
    ) async {
      final setup = _Server(_profile());
      final s = await _shell(t, setup);
      s.router.push(DatingPaths.step('preview'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Edit where you are'));
      await t.pumpAndSettle();
      await _moveToLondon(t);
      await _continue(t);
      expect(find.text(_d5), findsOneWidget);
      expect(find.text(_d12), findsNothing);
      await tapInReach(t, find.text('Woman'));
      await t.pumpAndSettle();
      await _continue(t);
      expect(find.text(_d6), findsOneWidget);
      await tapInReach(t, find.text('Men'));
      await t.pumpAndSettle();
      await _continue(t);
      expect(find.text(_d12), findsOneWidget);
      expect(find.text(_d7), findsNothing);
    });

    testWidgets('D12 off-country gender change: D6 is asked again, then D12', (
      t,
    ) async {
      final setup = _Server(_profile());
      final s = await _shell(t, setup);
      s.router.push(DatingPaths.step('preview'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Edit what you show about yourself'));
      await t.pumpAndSettle();
      expect(find.text(_d5), findsOneWidget);
      await tapInReach(t, find.text('Man'));
      await t.pumpAndSettle();
      await _continue(t);
      expect(setup.profile.seeking, isEmpty);
      expect(find.text(_d6), findsOneWidget);
      expect(find.text(_d12), findsNothing);
      expect(find.text("You'll be introduced to women."), findsOneWidget);
      await _continue(t);
      expect(find.text(_d12), findsOneWidget);
      expect(setup.profile.seeking, ['woman']);
    });

    testWidgets('D12 off-country, the same gender again: straight back', (
      t,
    ) async {
      final setup = _Server(_profile());
      final s = await _shell(t, setup);
      s.router.push(DatingPaths.step('preview'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Edit what you show about yourself'));
      await t.pumpAndSettle();
      await _continue(t);
      expect(find.text(_d12), findsOneWidget);
      expect(setup.writes, ['saveIdentity']);
    });

    testWidgets('on-country gender change keeps who-to-meet: straight back', (
      t,
    ) async {
      final setup = _Server(_profile(country: 'GB', region: 'TLI'));
      final s = await _shell(t, setup);
      s.router.push(DatingPaths.step('preview'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Edit what you show about yourself'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Man'));
      await t.pumpAndSettle();
      await _continue(t);
      expect(find.text(_d12), findsOneWidget);
      expect(setup.writes, ['saveIdentity']);
    });

    testWidgets('the re-read fails: the server rule decides (a new country '
        'asks D5)', (t) async {
      final setup = _Server(_profile())..readFailsAfterWrite = true;
      final s = await _shell(t, setup);
      s.router.push(DatingPaths.settings);
      await t.pumpAndSettle();
      await tapInReach(t, find.text('How far'));
      await t.pumpAndSettle();
      await _moveToLondon(t);
      await _continue(t);
      expect(find.text(_settings), findsNothing);
      expect(find.text(_d5), findsOneWidget);
    });
  });

  testWidgets('M-8: the kill-switch "Choose again": D5, D6, then Me', (
    t,
  ) async {
    final setup = _Server(_profile(identity: 'non_binary', seeking: const []));
    final s = await _shell(
      t,
      setup,
      initial: '/slot',
      home: const DatingHome(
        state: DatingHomeState.paused,
        pauseReason: DatingPauseReason.sameGenderSwitch,
        country: 'GH',
        hasData: true,
      ),
    );
    final reads = s.home.reads;
    await tapInReach(t, find.text('Choose again'));
    await t.pumpAndSettle();
    expect(find.text(_d5), findsOneWidget);
    await tapInReach(t, find.text('Woman'));
    await t.pumpAndSettle();
    await _continue(t);
    expect(find.text(_d6), findsOneWidget);
    await _continue(t);
    expect(find.text(_d7), findsNothing);
    expect(find.text('Choose again'), findsOneWidget);
    expect(setup.writes, ['saveIdentity', 'saveWhoToMeet']);
    // Back on Me, the home is read again (for Resume).
    expect(s.home.reads, greaterThan(reads));
  });

  testWidgets('M-8: "Choose again" with the same gender still asks D6 '
      '(who-to-meet must be plain too)', (t) async {
    final setup = _Server(_profile(seeking: const ['man', 'woman']));
    await _shell(
      t,
      setup,
      initial: '/slot',
      home: const DatingHome(
        state: DatingHomeState.paused,
        pauseReason: DatingPauseReason.sameGenderSwitch,
        country: 'GH',
        hasData: true,
      ),
    );
    await tapInReach(t, find.text('Choose again'));
    await t.pumpAndSettle();
    await _continue(t);
    // The server kept who-to-meet (same identity), but it isn't plain.
    expect(setup.profile.seeking, ['man', 'woman']);
    expect(find.text(_d6), findsOneWidget);
    await _continue(t);
    expect(setup.profile.seeking, ['man']);
    expect(find.text('Choose again'), findsOneWidget);
  });

  testWidgets('M-9: a from=settings step with no stack goes to settings', (
    t,
  ) async {
    final setup = _Server(_profile());
    final s = await _shell(t, setup);
    s.router.go('${DatingPaths.step('where')}?from=settings');
    await t.pumpAndSettle();
    expect(find.text(_d3), findsOneWidget);
    await _continue(t);
    expect(find.text(_settings), findsOneWidget);
    expect(find.text('Your answers stay private'), findsNothing);
  });
}
