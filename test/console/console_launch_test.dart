// Spec 2 W10 (§8 W10, §6.4, §6.9, §5.9): the console's launch pages.
// Launch readiness lists every gate in words (Green or Red, never colour
// alone) with what is red, and says why development is never ready;
// Metrics reads 7, 28 or 90 days and names only counters of 50 or more;
// Fairness reads 4 or 12 weeks, flagged cohorts first and marked; a
// moderator's console asks nothing on these pages; a failed read offers
// Try again; a publish refused for the launch gates says to read Launch
// readiness.
//
// Fix round 1 (task-2-3-review.md): the top_decile row as a share (I-1);
// check codes in words (M-1); a refusal without Try again (M-2); a new
// window never shows the old window's rows, and a late answer never wins
// (M-3); the countries checked and open (M-4); development said once (M-5);
// rates as percentages (M-6).
//
// Final fix (final-review.md): open while a gate is red, in production
// (I-1); one country checked (M-1); a fairness figure rounded (M-8).
import 'dart:async';

import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:attune/console/screens/launch_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'console_fakes.dart';

const _ready = ConsoleAnswer(
  ok: true,
  data: {
    'ok': true,
    'ready': false,
    'environment': 'development',
    'countries': ['GH', 'GB'],
    'open': <String>[],
    'gates': [
      {'gate': 'environment', 'ok': false},
      {'gate': 'age_assurance_live', 'ok': true},
      {
        'gate': 'flag_evidence',
        'ok': false,
        'detail': ['dating_couple_link', 'csam_hash_matching'],
      },
      {'gate': 'no_test_verifications', 'ok': false, 'detail': 3},
      {'gate': 'checklist:GH', 'ok': true, 'detail': <String>[]},
      {
        'gate': 'checklist:GB',
        'ok': false,
        'detail': ['dev_reference', 'evidence_missing'],
      },
      {'gate': 'resources:GB', 'ok': false},
      {'gate': 'w11_something_new', 'ok': true},
    ],
  },
);

const _metrics = ConsoleAnswer(
  ok: true,
  data: {
    'ok': true,
    'days': 7,
    'from': '2026-11-17',
    'to': '2026-11-23',
    'min_count': 50,
    'metrics': [
      {'key': 'dating.activated', 'count': 75},
      {'key': 'dating.mutual', 'count': 50},
    ],
    'suppressed': 4,
  },
);

const _fairness = ConsoleAnswer(
  ok: true,
  data: {
    'ok': true,
    'weeks': 4,
    'flagged': 2,
    'reports': [
      {
        'week': '2026-11-16',
        'country': 'GH',
        'cohort': 'region:AA',
        'active': '100–499',
        'introductions_per_active': 1.4,
        'mutual_rate': 0.09,
        'flagged': true,
      },
      {
        'week': '2026-11-16',
        'country': 'GH',
        'cohort': 'top_decile',
        'active': '500+',
        'introductions_per_active': 0.31,
        'mutual_rate': null,
        'flagged': true,
      },
      {
        'week': '2026-11-16',
        'country': 'GB',
        'cohort': 'age:25_34',
        'active': '50–99',
        'introductions_per_active': 2.004,
        'mutual_rate': null,
        'flagged': false,
      },
    ],
  },
);

Future<void> _open(WidgetTester t, String page) async {
  await t.ensureVisible(find.text(page));
  await t.pumpAndSettle();
  await t.tap(find.text(page));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Launch readiness lists every gate in words, with what is red', (
    t,
  ) async {
    final api = await pumpHome(
      t,
      me: consoleOwner,
      answers: {'readiness': _ready},
    );
    await _open(t, 'Launch readiness');
    expect(api.of('readiness'), [<String, Object?>{}]);
    // Fix round 1 (M-5): development is said once, in the note.
    expect(find.text('Not ready: 5 of 8 gates are red.'), findsOneWidget);
    // Ruling (owner, 2026-11-23): development reads calm, every red gate kept.
    expect(find.text(kConsoleReadinessDevNote), findsOneWidget);
    // M-4: the countries from the answer, and where Dating is open.
    expect(
      find.text('Checked for GH, GB. Dating is not open in any of them yet.'),
      findsOneWidget,
    );
    // M-1: a check code reads in words; a flag name reads as itself.
    expect(
      find.text(
        'Red: a DEV- reference is still in the checklist, a checklist '
        'reference is missing or empty',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Production mode is set (only the owner sets it)'),
      findsOneWidget,
    );
    expect(find.text('Red: dating_couple_link, csam_hash_matching'), findsOne);
    expect(find.text('Red: 3'), findsOneWidget);
    expect(
      find.text('GH: the legal checklist is complete with real references'),
      findsOneWidget,
    );
    expect(
      find.text('GB: support resources verified within 90 days'),
      findsOneWidget,
    );
    // A gate the console doesn't know yet reads as its key.
    expect(find.text('w11_something_new'), findsOneWidget);
    expect(find.text('Green'), findsNWidgets(3));
    // Read again reads again.
    await t.tap(find.byKey(const ValueKey('console_refresh')));
    await t.pumpAndSettle();
    expect(api.of('readiness'), hasLength(2));
  });

  testWidgets('every gate green reads ready', (t) async {
    await pumpHome(
      t,
      me: consoleOwner,
      answers: {
        'readiness': const ConsoleAnswer(
          ok: true,
          data: {
            'ok': true,
            'ready': true,
            'environment': 'production',
            'countries': ['GH'],
            'open': ['GH'],
            'gates': [
              {'gate': 'environment', 'ok': true},
            ],
          },
        ),
      },
    );
    await _open(t, 'Launch readiness');
    expect(
      find.text('Every gate is green. Dating may be switched on.'),
      findsOneWidget,
    );
    expect(find.text(kConsoleReadinessDevNote), findsNothing);
    expect(find.text('Checked for GH. Dating is open now in GH.'), findsOne);
    expect(
      find.byKey(const ValueKey('console_readiness_open_red')),
      findsNothing,
    );
  });

  testWidgets('in production, Dating open while a gate is red says to close '
      'it (final fix I-1)', (t) async {
    ConsoleAnswer readiness(String environment) => ConsoleAnswer(
      ok: true,
      data: {
        'ok': true,
        'ready': false,
        'environment': environment,
        'countries': const ['GH', 'GB'],
        'open': const ['GB', 'GH'],
        'gates': const [
          {'gate': 'environment', 'ok': true},
          {'gate': 'age_assurance_live', 'ok': false},
        ],
      },
    );
    final api = await pumpHome(
      t,
      me: consoleOwner,
      answers: {'readiness': readiness('production')},
    );
    await _open(t, 'Launch readiness');
    expect(
      find.text(
        'Dating is open in GB, GH while a launch gate is red. Close it from '
        'Countries until every gate is green.',
      ),
      findsOneWidget,
    );
    // In red: the line is an error, never a neutral note.
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    // The demo project (development, open for advisors) stays calm.
    api.answers['readiness'] = readiness('development');
    await t.tap(find.byKey(const ValueKey('console_refresh')));
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('console_readiness_open_red')),
      findsNothing,
    );
    expect(find.text(kConsoleReadinessDevNote), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('any one country can be checked (final fix M-1)', (t) async {
    final api = await pumpHome(
      t,
      me: consoleOwner,
      answers: {'readiness': _ready},
    );
    await _open(t, 'Launch readiness');
    expect(api.of('readiness'), [<String, Object?>{}]);
    await t.enterText(
      find.byKey(const ValueKey('console_readiness_country')),
      ' zz ',
    );
    await t.tap(find.byKey(const ValueKey('console_readiness_check')));
    await t.pumpAndSettle();
    expect(api.of('readiness').last, {'country': 'ZZ'});
    // Empty goes back to the server's default list.
    await t.enterText(
      find.byKey(const ValueKey('console_readiness_country')),
      '',
    );
    await t.tap(find.byKey(const ValueKey('console_readiness_check')));
    await t.pumpAndSettle();
    expect(api.of('readiness').last, <String, Object?>{});
  });

  testWidgets("the server's ready decides, never the console's count", (
    t,
  ) async {
    await pumpHome(
      t,
      me: consoleOwner,
      answers: {
        'readiness': const ConsoleAnswer(
          ok: true,
          data: {
            'ok': true,
            'ready': false,
            'environment': 'production',
            'gates': [
              {'gate': 'environment', 'ok': true},
            ],
          },
        ),
      },
    );
    await _open(t, 'Launch readiness');
    expect(find.text('Not ready: 0 of 1 gates are red.'), findsOneWidget);
    expect(find.text(kConsoleReadinessDevNote), findsNothing);
  });

  testWidgets('Metrics names only counters of 50 or more, by window', (
    t,
  ) async {
    final api = await pumpHome(
      t,
      me: consoleOwner,
      answers: {'metrics': _metrics},
    );
    await _open(t, 'Metrics');
    expect(api.of('metrics'), [
      {'days': 7},
    ]);
    expect(
      find.text(
        '17 Nov 2026 to 23 Nov 2026 (UTC). Counters under 50 are not '
        'shown: 4.',
      ),
      findsOneWidget,
    );
    expect(find.text('dating.activated'), findsOneWidget);
    expect(find.text('75'), findsOneWidget);
    await t.tap(find.text('28 days'));
    await t.pumpAndSettle();
    expect(api.of('metrics').last, {'days': 28});
    await t.tap(find.text('90 days'));
    await t.pumpAndSettle();
    expect(api.of('metrics').last, {'days': 90});
  });

  testWidgets('Metrics with nothing at 50 says so', (t) async {
    await pumpHome(
      t,
      me: consoleOwner,
      answers: {
        'metrics': const ConsoleAnswer(
          ok: true,
          data: {'ok': true, 'metrics': <Object>[], 'suppressed': 9},
        ),
      },
    );
    await _open(t, 'Metrics');
    expect(find.text('No counter reached 50 in this window.'), findsOneWidget);
  });

  testWidgets('Fairness: flagged cohorts first and marked, by window', (
    t,
  ) async {
    final api = await pumpHome(
      t,
      me: consoleOwner,
      answers: {'fairness': _fairness},
    );
    await _open(t, 'Fairness');
    expect(api.of('fairness'), [
      {'weeks': 4},
    ]);
    expect(
      find.text('Flagged · GH · region:AA · week of 16 Nov 2026'),
      findsOneWidget,
    );
    expect(
      find.text(
        '2.0 introductions per active person · mutual rate - · 50–99 active',
      ),
      findsOneWidget,
    );
    // M-6: a rate as a percentage.
    expect(
      find.text(
        '1.4 introductions per active person · mutual rate 9% · 100–499 '
        'active',
      ),
      findsOneWidget,
    );
    // I-1: the top 10%'s share of introductions, never a per-person rate.
    expect(
      find.text(
        'The top 10% received 31% of introductions (flagged above 25%) · '
        '500+ active',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('0.31'), findsNothing);
    // Final fix M-8: a figure is rounded.
    expect(find.textContaining('2.004'), findsNothing);
    final first = t.getTopLeft(
      find.byKey(const ValueKey('console_fairness_0')),
    );
    final second = t.getTopLeft(
      find.byKey(const ValueKey('console_fairness_1')),
    );
    expect(first.dy, lessThan(second.dy));
    // M-3: a new window that fails never shows the old window's rows, and
    // the window stays choosable.
    api.answers['fairness'] = ConsoleAnswer.busy;
    await t.tap(find.text('12 weeks'));
    await t.pumpAndSettle();
    expect(api.of('fairness').last, {'weeks': 12});
    expect(
      find.text('Flagged · GH · region:AA · week of 16 Nov 2026'),
      findsNothing,
    );
    expect(
      find.text('The server is busy. Try again in a moment.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('console_retry')), findsOneWidget);
    expect(find.text('4 weeks'), findsOneWidget);
  });

  testWidgets("a late answer for an earlier window never wins (M-3)", (
    t,
  ) async {
    final api = _SlowApi();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FairnessScreen(
            api: api,
            me: const ConsoleMe(role: 'safety_owner', routing: true),
          ),
        ),
      ),
    );
    api.pending.single.complete(_fairness);
    await t.pumpAndSettle();
    // A read is pending (its spinner never settles): pump a while instead.
    await t.tap(find.text('12 weeks'));
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('4 weeks'));
    await t.pump(const Duration(milliseconds: 500));
    expect(api.params, [
      {'weeks': 4},
      {'weeks': 12},
      {'weeks': 4},
    ]);
    api.pending[2].complete(_fairness);
    await t.pumpAndSettle();
    // The 12-week answer arrives last; 4 weeks is what is selected.
    api.pending[1].complete(
      const ConsoleAnswer(
        ok: true,
        data: {
          'ok': true,
          'weeks': 12,
          'flagged': 0,
          'reports': [
            {'week': '2026-09-07', 'country': 'XX', 'cohort': 'late'},
          ],
        },
      ),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('XX'), findsNothing);
    expect(
      find.text('Flagged · GH · region:AA · week of 16 Nov 2026'),
      findsOneWidget,
    );
  });

  testWidgets("a moderator's console asks nothing on the launch pages", (
    t,
  ) async {
    final api = await pumpHome(t);
    for (final page in ['Launch readiness', 'Metrics', 'Fairness']) {
      await _open(t, page);
      expect(find.text(kConsoleLaunchOwnerOnly), findsOneWidget, reason: page);
    }
    expect(api.of('readiness'), isEmpty);
    expect(api.of('metrics'), isEmpty);
    expect(api.of('fairness'), isEmpty);
  });

  testWidgets('a failed read offers Try again, and a refusal reads as its '
      'line', (t) async {
    final api = await pumpHome(
      t,
      me: consoleOwner,
      answers: {
        'readiness': ConsoleAnswer.busy,
        'metrics': const ConsoleAnswer(ok: false, reason: 'safety_owner_only'),
      },
    );
    await _open(t, 'Launch readiness');
    expect(
      find.text('The server is busy. Try again in a moment.'),
      findsOneWidget,
    );
    await t.tap(find.byKey(const ValueKey('console_retry')));
    await t.pumpAndSettle();
    expect(api.of('readiness'), hasLength(2));
    await _open(t, 'Metrics');
    expect(find.text('Only the safety owner can do this.'), findsOneWidget);
    // M-2: a refusal is its line; trying again would change nothing.
    expect(find.byKey(const ValueKey('console_retry')), findsNothing);
  });

  testWidgets('a publish refused for the launch gates says to read Launch '
      'readiness', (t) async {
    await pumpHome(
      t,
      me: consoleOwner,
      answers: {
        'countries': const ConsoleAnswer(
          ok: true,
          data: {'ok': true, 'countries': <Object>[]},
        ),
        'publish_country': const ConsoleAnswer(
          ok: false,
          reason: 'config:launch_not_ready',
        ),
      },
    );
    await _open(t, 'Countries');
    await t.enterText(find.byKey(const ValueKey('console_country_code')), 'GH');
    await t.enterText(
      find.byKey(const ValueKey('console_country_values')),
      '{"dating_enabled": true}',
    );
    await t.tap(find.byKey(const ValueKey('console_publish')));
    await t.pumpAndSettle();
    await tapConfirm(t);
    expect(
      find.text(
        'This would open Dating somewhere while a launch gate is red, so '
        'nothing was published. Launch readiness shows which.',
      ),
      findsOneWidget,
    );
  });
}

/// Answers only when a test completes each call, in any order.
class _SlowApi implements ConsoleApi {
  final pending = <Completer<ConsoleAnswer>>[];
  final params = <Map<String, Object?>>[];

  @override
  Future<ConsoleAnswer> call(
    String action, [
    Map<String, Object?> params = const {},
  ]) {
    this.params.add(params);
    final c = Completer<ConsoleAnswer>();
    pending.add(c);
    return c.future;
  }
}
