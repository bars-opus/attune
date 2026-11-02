// Spec 1 W3a (§3.11, §5.6 R1, review N-2): the home shell under
// flow_paths_v2. The latch block is not edited: v2 changes only what
// `isComplete` means. Tab 2 is Chat or Me by the home state's layout and
// opens first; a layout change rebuilds the keyed shell, a link change or
// Dating <-> Just for me does not; /home?tab= opens Tab 2; a guest's Tab 2
// is "Sign in" under flow_signin_v2.
import 'package:attune/features/onboarding/data/home_state_store.dart';
import 'package:attune/home/home_location.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_home_state.dart';
import '../helpers/home_harness.dart';

String _cache({
  String tab = 'me',
  String link = 'none',
  List<String> needs = const [],
}) =>
    '{"tab":"$tab","link":"$link","needs":[${needs.map((n) => '"$n"').join(',')}],'
    '"hold":false,"at":"2026-10-26T08:00:00.000Z"}';

bool _onTab2(WidgetTester tester) =>
    !tester
        .widget<Offstage>(
          find
              .ancestor(
                of: find.textContaining('TAB2', skipOffstage: false),
                matching: find.byType(Offstage),
              )
              .first,
        )
        .offstage;

void main() {
  testWidgets(
    'a guest sees today\'s "Chat" with sign-in v2 off, "Sign in" with it on',
    (tester) async {
      await pumpHome(tester, userId: null, signInV2: false);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);

      await pumpHome(tester, userId: null, signInV2: true);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Chat'), findsNothing);
    },
  );

  testWidgets("a guest's /home?tab=chat opens Tab 2 (back from Join Attune)", (
    tester,
  ) async {
    final h = await pumpHome(
      tester,
      userId: null,
      initialLocation: homeLocation(tab: AppTab.chat),
    );
    expect(h.location, startsWith('/home?tab=chat'));
    final tab2 = tester.widget<Offstage>(
      find
          .ancestor(
            of: find.text('Join Attune'),
            matching: find.byType(Offstage),
          )
          .first,
    );
    expect(tab2.offstage, isFalse);
  });

  testWidgets('Relationship: Tab 2 is Chat and opens first', (tester) async {
    await pumpHome(
      tester,
      prefsValues: {
        HomeStateStore.keyFor('u-home'): _cache(tab: 'chat', link: 'pending'),
      },
      server: homeJson(path: 'relationship', link: 'pending'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('TAB2 chat pending'), findsOneWidget);
    expect(_onTab2(tester), isTrue);
  });

  testWidgets('Just for me: Tab 2 is Me', (tester) async {
    await pumpHome(
      tester,
      prefsValues: {HomeStateStore.keyFor('u-home'): _cache()},
      server: homeJson(path: 'just_me'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Me'), findsOneWidget);
    expect(find.text('Chat'), findsNothing);
    expect(find.text('TAB2 me none'), findsOneWidget);
  });

  testWidgets(
    'the latch fires once for needs [birth_date], not again after the date (N-2)',
    (tester) async {
      final h = await pumpHome(
        tester,
        prefsValues: {
          HomeStateStore.keyFor('u-home'): _cache(needs: ['birth_date']),
        },
        server: homeJson(needs: ['birth_date']),
      );
      // Rebuilds while still incomplete never add a redirect.
      await h.answer('u-home', homeJson(needs: ['birth_date']));
      await h.answer('u-home', homeJson(needs: ['birth_date']));
      await tester.pumpAndSettle();
      expect(h.onboardingVisits, ['onboarding']);
      expect(find.text('ONBOARDING'), findsOneWidget);

      // The interstitial took the date; the gate goes home.
      h.gateway.state = homeJson();
      await h.answer('u-home', homeJson());
      h.router.go('/home');
      await tester.pumpAndSettle();
      expect(find.text('TAB2 me none'), findsOneWidget);
      expect(h.onboardingVisits, ['onboarding']);
    },
  );

  testWidgets('an unknown need keeps the home closed (W2 P-15, review M-5)', (
    tester,
  ) async {
    final h = await pumpHome(
      tester,
      prefsValues: {
        HomeStateStore.keyFor('u-home'): _cache(needs: ['from_a_later_wave']),
      },
      server: homeJson(needs: ['from_a_later_wave']),
    );
    await tester.pumpAndSettle();
    expect(h.onboardingVisits, ['onboarding']);
  });

  testWidgets('a layout change rebuilds the shell; a link change does not', (
    tester,
  ) async {
    final h = await pumpHome(
      tester,
      prefsValues: {
        HomeStateStore.keyFor('u-home'): _cache(tab: 'chat', link: 'pending'),
      },
      server: homeJson(path: 'relationship', link: 'pending'),
    );
    await tester.pumpAndSettle();
    final created = TabTwoProbe.created;
    await tester.tap(find.text('Opinions'));
    await tester.pumpAndSettle();

    // pending -> linked: Tab 2's child changes in place; Opinions stays up.
    await h.answer('u-home', homeJson(path: 'relationship', link: 'linked'));
    await tester.pumpAndSettle();
    expect(find.text('TAB2 chat linked', skipOffstage: false), findsOneWidget);
    expect(TabTwoProbe.created, created);
    expect(_onTab2(tester), isFalse);

    // Relationship -> Just for me: a new layout, so a new shell on Tab 2.
    await h.answer('u-home', homeJson(path: 'just_me'));
    await tester.pumpAndSettle();
    expect(find.text('TAB2 me none'), findsOneWidget);
    expect(TabTwoProbe.created, created + 1);
    expect(_onTab2(tester), isTrue);
  });

  testWidgets('Dating <-> Just for me keeps the shell (both Me)', (
    tester,
  ) async {
    final h = await pumpHome(
      tester,
      prefsValues: {HomeStateStore.keyFor('u-home'): _cache()},
      server: homeJson(path: 'just_me'),
    );
    await tester.pumpAndSettle();
    final created = TabTwoProbe.created;
    await h.answer('u-home', homeJson(path: 'dating', datingEnabled: true));
    await tester.pumpAndSettle();
    await h.answer('u-home', homeJson(path: 'just_me'));
    await tester.pumpAndSettle();
    expect(TabTwoProbe.created, created);
  });

  testWidgets('/home?tab=me while the shell is up opens Tab 2, every time', (
    tester,
  ) async {
    final h = await pumpHome(
      tester,
      prefsValues: {HomeStateStore.keyFor('u-home'): _cache()},
      server: homeJson(path: 'just_me'),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Opinions'));
      await tester.pumpAndSettle();
      expect(_onTab2(tester), isFalse);
      h.router.go(homeLocation(tab: AppTab.me));
      await tester.pumpAndSettle();
      expect(_onTab2(tester), isTrue, reason: 'request ${i + 1}');
    }
  });

  testWidgets('flow_paths_v2 off: the v2 home state is not read', (
    tester,
  ) async {
    final h = await pumpHome(
      tester,
      pathsV2: false,
      prefsValues: {
        HomeStateStore.keyFor('u-home'): _cache(),
        'attune.onboarding.user.u-home.completed': true,
        'attune.onboarding.user.u-home.mode': 'personal',
      },
    );
    await tester.pumpAndSettle();
    expect(h.gateway.count('get_my_home_state'), 0);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Me'), findsNothing);
  });

  testWidgets('signing out forgets the account\'s live answer (D20)', (
    tester,
  ) async {
    final h = await pumpHome(
      tester,
      prefsValues: {HomeStateStore.keyFor('u-home'): _cache()},
      server: homeJson(path: 'dating', datingEnabled: true),
    );
    await tester.pumpAndSettle();
    expect(h.gateway.count('get_my_home_state'), greaterThanOrEqualTo(1));
    h.auth.signOut();
    await tester.pumpAndSettle();
    // A fresh read of the provider has no live answer: path unknown.
    final probe = h.container.read(homeStateProvider('u-home'));
    expect(probe.path, isNull);
    expect(find.text('Sign in'), findsOneWidget, reason: 'the guest shell');
  });

  // Fix round 1 (review I#1): the kill switch. apply() removed the legacy
  // mode (spec 5.5), so turning flow_paths_v2 off must run today's mode
  // sync at once, or a linked couple sits on the locked Chat screen.
  testWidgets('flow_paths_v2 switched off re-syncs the legacy mode (I#1)', (
    tester,
  ) async {
    final h = await pumpHome(
      tester,
      prefsValues: {
        HomeStateStore.keyFor('u-home'): _cache(tab: 'chat', link: 'linked'),
        'attune.onboarding.user.u-home.completed': true,
        'attune.onboarding.user.u-home.mode': 'couples',
      },
      server: homeJson(path: 'relationship', link: 'linked'),
    );
    await tester.pumpAndSettle();
    expect(h.prefs.getString('attune.onboarding.user.u-home.mode'), isNull);

    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) logs.add(message);
    };
    try {
      h.pathsV2.state = false;
      await tester.pumpAndSettle();
    } finally {
      debugPrint = original;
    }
    // Today's sync ran (it reaches its Supabase-less catch in this host).
    expect(
      logs.where((line) => line.startsWith('[home] relationship mode sync')),
      isNotEmpty,
    );
    expect(find.textContaining('TAB2'), findsNothing);
  });

  testWidgets('flow_paths_v2 switched on reads the home state (I#1)', (
    tester,
  ) async {
    final h = await pumpHome(
      tester,
      pathsV2: false,
      prefsValues: {
        HomeStateStore.keyFor('u-home'): _cache(),
        'attune.onboarding.user.u-home.completed': true,
        'attune.onboarding.user.u-home.mode': 'personal',
      },
      server: homeJson(path: 'just_me'),
    );
    await tester.pumpAndSettle();
    expect(h.gateway.count('get_my_home_state'), 0);
    h.pathsV2.state = true;
    await tester.pumpAndSettle();
    expect(h.gateway.count('get_my_home_state'), greaterThanOrEqualTo(1));
    expect(find.text('Me'), findsOneWidget);
    expect(find.text('TAB2 me none'), findsOneWidget);
  });

  // Fix round 1 (ruling): until this phone has any v2 answer, the couple
  // link comes from the legacy mode, so an active couple never sees the
  // locked Chat screen, online or off.
  for (final (mode, link) in [
    ('couples', 'linked'),
    ('couplesPending', 'pending'),
  ]) {
    testWidgets('unknown home state, offline: legacy $mode reads $link', (
      tester,
    ) async {
      await pumpHome(
        tester,
        prefsValues: {
          'attune.onboarding.user.u-home.completed': true,
          'attune.onboarding.user.u-home.mode': mode,
        },
        serverError: Exception('offline'),
      );
      await tester.pumpAndSettle();
      expect(find.text('TAB2 chat $link'), findsOneWidget);
      expect(_onTab2(tester), isTrue);
    });
  }

  // Fix round 1 (review I#3): the shared tab bar.
  for (final guest in [false, true]) {
    testWidgets(
      'the tab bar meets tap-target and label guidelines (I#3, guest: $guest)',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpHome(
          tester,
          userId: guest ? null : 'u-home',
          prefsValues: {HomeStateStore.keyFor('u-home'): _cache()},
          server: homeJson(path: 'just_me'),
        );
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        final second = guest ? 'Sign in' : 'Me';
        expect(
          tester.getSemantics(find.text(second)),
          containsSemantics(
            label: second,
            isButton: true,
            isSelected: !guest,
            hasTapAction: true,
          ),
        );
        expect(
          tester.getSemantics(find.text('Opinions')),
          containsSemantics(
            label: 'Opinions',
            isButton: true,
            isSelected: guest,
            hasTapAction: true,
          ),
        );
        semantics.dispose();
      },
    );
  }

  // Fix round 1 (review minor #4): a nav bar hidden by scrolling comes
  // back when the layout rebuilds the shell.
  testWidgets('the nav bar is shown again after a layout rebuild', (
    tester,
  ) async {
    final h = await pumpHome(
      tester,
      prefsValues: {
        HomeStateStore.keyFor('u-home'): _cache(tab: 'chat', link: 'pending'),
      },
      server: homeJson(path: 'relationship', link: 'pending'),
    );
    await tester.pumpAndSettle();
    h.container.read(navVisibilityProvider.notifier).state = false;
    await tester.pump();
    await h.answer('u-home', homeJson(path: 'just_me'));
    await tester.pumpAndSettle();
    expect(find.text('TAB2 me none'), findsOneWidget);
    expect(h.container.read(navVisibilityProvider), isTrue);
  });

  // Fix round 1 (review minor #5): /home?tab= selects Tab 2 in place; it
  // no longer rebuilds the whole shell (Opinions keeps its feed).
  testWidgets('/home?tab= opens Tab 2 without rebuilding the shell', (
    tester,
  ) async {
    final h = await pumpHome(
      tester,
      prefsValues: {HomeStateStore.keyFor('u-home'): _cache()},
      server: homeJson(path: 'just_me'),
    );
    await tester.pumpAndSettle();
    final created = TabTwoProbe.created;
    await tester.tap(find.text('Opinions'));
    await tester.pumpAndSettle();
    h.container.read(navVisibilityProvider.notifier).state = false;
    h.router.go(homeLocation(tab: AppTab.me));
    await tester.pumpAndSettle();
    expect(_onTab2(tester), isTrue);
    expect(TabTwoProbe.created, created);
    expect(h.container.read(navVisibilityProvider), isTrue);
  });
}
