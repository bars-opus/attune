// Spec 2 W8 final client fix round 2 (server M-1; R-T7-14 extended): the
// home names a trip while Dating is paused too. Me's paused card says the
// same neutral line as the active and gentle-wait cards and links to
// /dating/away ("What this means"); the note's words, the place and the
// choices stay on that page. There, Dating is paused already, so "Pause
// Dating" isn't offered; "Show it on this phone anyway" still lifts the
// hiding for a paused person's reads (the conversations stay open).
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/device/trip_phone.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';
import '../support/dating_trip_fakes.dart';

final loc = AppLocalizationsEn();

const _me = '/w8-me';

DatingHome _paused({
  DatingTrip? trip,
  DatingPauseReason reason = DatingPauseReason.user,
}) => DatingHome(
  state: DatingHomeState.paused,
  hasData: true,
  pauseReason: reason,
  canResume: true,
  trip: trip,
);

const _sameGender = DatingTrip(kind: DatingTripKind.sameGender);
const _away = DatingTrip(kind: DatingTripKind.away, note: true);

Future<DatingShell> _shell(WidgetTester t, DatingHome home, {String? at}) =>
    pumpDatingShell(
      t,
      initial: at ?? _me,
      home: FakeDatingHomeGateway(home: home),
      extraRoutes: [
        GoRoute(
          path: _me,
          builder:
              (_, __) => const Scaffold(
                body: SingleChildScrollView(child: DatingSection()),
              ),
        ),
      ],
      overrides: [
        ...datingTripOverrides(FakeDatingTrip()),
        homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
        homeStateServiceProvider.overrideWithValue(
          HomeStateService(
            FakeHomeStateGateway(state: homeJson(path: 'dating')),
          ),
        ),
      ],
    );

final _more = find.byKey(const ValueKey('dating_trip_more'));

void main() {
  setUp(DatingTripPhone.reset);

  group('Me\'s paused card', () {
    testWidgets('a same-gender trip: the neutral title and "What this '
        'means", which opens /dating/away; no words of the note', (t) async {
      await _shell(t, _paused(trip: _sameGender));
      expect(find.text(loc.dating_sectionPaused), findsOneWidget);
      expect(find.text(loc.dating_tripSameGenderTitle), findsOneWidget);
      expect(_more, findsOneWidget);
      expect(find.text(loc.dating_tripSameGenderBodyNoPlace), findsNothing);
      expect(find.text(loc.dating_tripShowAnyway), findsNothing);
      await tapInReach(t, _more);
      await t.pumpAndSettle();
      expect(find.text(loc.dating_tripShowAnyway), findsOneWidget);
    });

    testWidgets('an away trip: the away line and the link', (t) async {
      await _shell(t, _paused(trip: _away));
      expect(find.text(loc.dating_sectionAway), findsOneWidget);
      expect(_more, findsOneWidget);
      expect(find.text(loc.dating_tripSameGenderTitle), findsNothing);
    });

    testWidgets('a travel pause on an away trip says the away line once', (
      t,
    ) async {
      await _shell(t, _paused(trip: _away, reason: DatingPauseReason.away));
      expect(find.text(loc.dating_sectionAway), findsOneWidget);
      expect(_more, findsOneWidget);
    });

    testWidgets('no trip: nothing of one', (t) async {
      await _shell(t, _paused());
      expect(find.text(loc.dating_sectionPaused), findsOneWidget);
      expect(_more, findsNothing);
      expect(find.text(loc.dating_tripSameGenderTitle), findsNothing);
      expect(find.text(loc.dating_sectionAway), findsNothing);
    });
  });

  group('/dating/away while paused', () {
    testWidgets('a same-gender trip: no Pause Dating; "Show it on this phone '
        'anyway" lifts the hiding for this account\'s reads', (t) async {
      final s = await _shell(
        t,
        _paused(trip: _sameGender),
        at: DatingPaths.away,
      );
      expect(find.text(loc.dating_tripSameGenderTitle), findsOneWidget);
      expect(find.byKey(const ValueKey('dating_trip_pause')), findsNothing);
      expect(find.byKey(const ValueKey('dating_trip_hide')), findsOneWidget);
      final reads = s.home.reads;
      await tapInReach(t, find.byKey(const ValueKey('dating_trip_show')));
      await t.pumpAndSettle();
      // The reads (the conversations stay open while paused) ask for it.
      expect(await DatingTripPhone.showFor('ama'), isTrue);
      expect(s.home.reads, greaterThan(reads));
    });

    testWidgets('an active home still offers Pause Dating', (t) async {
      await _shell(
        t,
        const DatingHome(
          state: DatingHomeState.active,
          hasData: true,
          trip: _sameGender,
        ),
        at: DatingPaths.away,
      );
      expect(find.byKey(const ValueKey('dating_trip_pause')), findsOneWidget);
    });
  });
}
