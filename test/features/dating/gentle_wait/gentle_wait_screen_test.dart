// Spec 2 W2: D0, the gentle wait (§3.2 D0, §3.0, §3.15; D8, D20).
// The copy with both dates in full words, three labelled answers kept in
// memory and saved only when asked, the offline rule, Healing offered,
// setup going ahead, another account on the same phone never seeing the
// last one's answers, nothing on disk, and the goldens at 1.0, 1.3, 2.0
// and right-to-left.
//   flutter test --update-goldens test/features/dating/gentle_wait/gentle_wait_screen_test.dart
import 'dart:async';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/services/app_privacy_cover.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/providers/auth_provider.dart'
    show currentUserProvider;
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_screen.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/widgets/quick_exit_zone.dart';
import 'package:attune/features/stories/data/story_device_wipe.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';

const _body =
    'Your relationship on Attune ended on Sunday, November 1, 2026. Dating opens for you on Tuesday, December 1, 2026, when your shared space closes. If you both close it sooner, Dating opens then.';
const _q1 = 'What do you want to carry into your next relationship?';
const _q2 = 'What are you hoping for now?';
const _q3 = 'How will you know if you need more time?';

// Noon UTC, so the dates are the same day in any test machine's zone.
final _ama = GentleWait(
  endedAt: DateTime.utc(2026, 11, 1, 12),
  opensAt: DateTime.utc(2026, 12, 1, 12),
  canShorten: true,
  answers: const {'q1': 'Patience with myself'},
);
final _kofi = GentleWait(
  endedAt: DateTime.utc(2026, 11, 1, 12),
  opensAt: DateTime.utc(2026, 12, 1, 12),
  canShorten: true,
  answers: const {'q2': 'Someone kind'},
);
const _bodyNoShortcut =
    'Your relationship on Attune ended on Sunday, November 1, 2026. Dating opens for you on Tuesday, December 1, 2026.';

FlowSecondaryButton _saveButton(WidgetTester t) =>
    t.widget<FlowSecondaryButton>(find.byType(FlowSecondaryButton));

/// Answers each account's read from [data]; [hold] keeps the next
/// account's read open ([holdAny] any read); [saves] records what was sent,
/// [clears] how often the clear was called.
class _FakeGateway implements GentleWaitGateway {
  _FakeGateway(this.signedIn);

  final String? Function() signedIn;
  final data = <String, GentleWait>{'ama': _ama, 'kofi': _kofi};
  final saves = <Map<String, String>>[];
  Completer<void>? hold;
  Object? readError;
  GentleWaitSave saveResult = GentleWaitSave.saved;
  Completer<void>? saveHold;
  Completer<void>? holdAny;
  int reads = 0;
  int clears = 0;

  @override
  Future<GentleWait> read() async {
    reads++;
    final who = signedIn();
    if (who != 'ama') await hold?.future;
    await holdAny?.future;
    final error = readError;
    if (error != null) throw error;
    return data[who]!;
  }

  @override
  Future<GentleWaitSave> save(Map<String, String> answers) async {
    saves.add(answers);
    await saveHold?.future;
    return saveResult;
  }

  @override
  Future<GentleWaitSave> clear() async {
    clears++;
    await saveHold?.future;
    return saveResult;
  }
}

final _signedIn = StateProvider<String?>((ref) => 'ama');

class _Pumped {
  _Pumped(this.harness, this.gateway, this.setUps);

  final FlowHarness harness;
  final _FakeGateway gateway;
  final List<int> setUps;
}

/// What D0's three fields hold, shown or not.
List<String> _answerTexts(WidgetTester t) =>
    (t.state(find.byType(GentleWaitScreen)) as dynamic).debugAnswerTexts
        as List<String>;

ProviderContainer _container(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(GentleWaitScreen)));

Future<_Pumped> _open(
  WidgetTester t, {
  bool online = true,
  bool reduceMotion = false,
}) async {
  late _FakeGateway gateway;
  final setUps = <int>[];
  final harness = await pumpFlowScreen(
    t,
    () => GentleWaitScreen(onSetUp: () => setUps.add(1)),
    reduceMotion: reduceMotion,
    overrides: [
      gentleWaitAccountProvider.overrideWith((ref) => ref.watch(_signedIn)),
      gentleWaitGatewayProvider.overrideWith((ref) {
        return gateway = _FakeGateway(() => ref.read(_signedIn));
      }),
      datingOnlineProvider.overrideWith((ref) => Stream.value(online)),
    ],
  );
  await t.pumpAndSettle();
  return _Pumped(harness, gateway, setUps);
}

void main() {
  testWidgets('D0 reads the wait in full words, with three labelled answers', (
    t,
  ) async {
    await _open(t);
    expect(find.text('Before you begin'), findsOneWidget);
    expect(find.text(_body), findsOneWidget);
    expect(
      find.text(
        "This pause is because your relationship ended here. It isn't a judgement about you.",
      ),
      findsOneWidget,
    );
    expect(find.text('Three questions, just for you'), findsOneWidget);
    expect(
      find.text('Only you can see these, and nothing is scored.'),
      findsOneWidget,
    );
    for (final question in [_q1, _q2, _q3]) {
      expect(find.bySemanticsLabel(question), findsOneWidget);
    }
    // Saved answers are back in their fields.
    expect(find.text('Patience with myself'), findsOneWidget);
    expect(find.text('Save my answers'), findsOneWidget);
    expect(find.text('Set up Dating now'), findsOneWidget);
    expect(
      find.text(
        "Healing is here if you want it. It's there to help, and it's never required.",
      ),
      findsOneWidget,
    );
    expect(
      find.text("You're offline. Dating needs a connection."),
      findsNothing,
    );
  });

  testWidgets('Save sends what was typed, says so, and writes nothing to the '
      'phone (D20)', (t) async {
    final p = await _open(t);
    await t.enterText(
      find.byKey(const ValueKey('gentle_wait_q3')),
      'When I feel rushed',
    );
    await tapInReach(t, find.text('Save my answers'));
    await t.pumpAndSettle();
    expect(p.gateway.saves, [
      {'q1': 'Patience with myself', 'q2': '', 'q3': 'When I feel rushed'},
    ]);
    expect(find.text('Your answers are saved.'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().where((k) => k.toLowerCase().contains('dating')),
      isEmpty,
    );
    expect(
      prefs
          .getKeys()
          .map((k) => '${prefs.get(k)}')
          .where((v) => v.contains('rushed')),
      isEmpty,
    );
  });

  testWidgets('a failed save says so and keeps the answers on screen', (
    t,
  ) async {
    final p = await _open(t);
    p.gateway.saveResult = GentleWaitSave.failed;
    await t.enterText(find.byKey(const ValueKey('gentle_wait_q2')), 'Kindness');
    await tapInReach(t, find.text('Save my answers'));
    await t.pumpAndSettle();
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    expect(find.text('Your answers are saved.'), findsNothing);
    expect(find.text('Kindness'), findsOneWidget);
  });

  testWidgets('offline: the banner, Save off with its hint, typed text kept', (
    t,
  ) async {
    final p = await _open(t, online: false);
    expect(
      find.text("You're offline. Dating needs a connection."),
      findsOneWidget,
    );
    expect(find.text('Connect to save this answer.'), findsOneWidget);
    await t.enterText(
      find.byKey(const ValueKey('gentle_wait_q1')),
      'Still here',
    );
    await bringIntoReach(t, find.text('Save my answers'));
    await t.tap(find.text('Save my answers'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(p.gateway.saves, isEmpty);
    expect(find.text('Still here'), findsOneWidget);
  });

  testWidgets('Healing is offered: the card opens Healing', (t) async {
    await _open(t);
    await tapInReach(
      t,
      find.text(
        "Healing is here if you want it. It's there to help, and it's never required.",
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('at /healingJourney'), findsOneWidget);
  });

  testWidgets('Set up Dating now goes ahead with setup', (t) async {
    final p = await _open(t);
    await tapInReach(t, find.text('Set up Dating now'));
    await t.pumpAndSettle();
    expect(p.setUps, [1]);
  });

  testWidgets('a wait closing the space together can no longer shorten: no '
      '"If you both close it sooner" (final review M-4)', (t) async {
    final p = await _open(t);
    expect(find.text(_body), findsOneWidget);
    p.gateway.data['ama'] = GentleWait(
      endedAt: DateTime.utc(2026, 11, 1, 12),
      opensAt: DateTime.utc(2026, 12, 1, 12),
      answers: const {'q1': 'Patience with myself'},
    );
    _container(t).invalidate(gentleWaitProvider);
    await t.pumpAndSettle();
    expect(find.text(_bodyNoShortcut), findsOneWidget);
    expect(find.textContaining('close it sooner'), findsNothing);
    expect(find.textContaining('when your shared space closes'), findsNothing);
  });

  testWidgets('after the wait (no dates) D0 shows no date sentence', (t) async {
    final p = await _open(t);
    p.gateway.data['ama'] = const GentleWait(
      answers: {'q1': 'Patience with myself'},
    );
    _container(t).invalidate(gentleWaitProvider);
    await t.pumpAndSettle();
    expect(find.textContaining('Dating opens for you on'), findsNothing);
    expect(find.bySemanticsLabel(_q1), findsOneWidget);
  });

  testWidgets('a failed read says so, and Retry reads again', (t) async {
    final p = await _open(t);
    p.gateway.readError = Exception('offline');
    _container(t).invalidate(gentleWaitProvider);
    await t.pumpAndSettle();
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    expect(find.text('Patience with myself'), findsNothing);
    p.gateway.readError = null;
    final before = p.gateway.reads;
    await tapInReach(t, find.text('Retry'));
    await t.pumpAndSettle();
    expect(p.gateway.reads, before + 1);
    expect(find.text('Patience with myself'), findsOneWidget);
  });

  testWidgets('an answer holds at most 500 code points (the server counts '
      'code points, so a family emoji counts as several)', (t) async {
    await _open(t);
    final field = find.byKey(const ValueKey('gentle_wait_q2'));
    await t.enterText(field, 'é' * 501);
    await t.pump();
    final text =
        t
            .widget<TextField>(
              find.descendant(of: field, matching: find.byType(TextField)),
            )
            .controller!
            .text;
    expect(text.runes.length, 500);
    expect(find.text('500 of 500 characters'), findsOneWidget);
    final family = '\u{1F468}‍\u{1F469}‍\u{1F467}'; // 5 code points
    await t.enterText(field, family * 101);
    await t.pump();
    expect(
      t
          .widget<TextField>(
            find.descendant(of: field, matching: find.byType(TextField)),
          )
          .controller!
          .text
          .runes
          .length,
      lessThanOrEqualTo(500),
    );
  });

  testWidgets('D8: the next account never sees the last one\'s answers or '
      'typing, not even while its read is out', (t) async {
    final p = await _open(t);
    await t.enterText(
      find.byKey(const ValueKey('gentle_wait_q3')),
      'Ama typed this',
    );
    p.gateway.hold = Completer<void>();
    _container(t).read(_signedIn.notifier).state = 'kofi';
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
      expect(
        find.text('Patience with myself'),
        findsNothing,
        reason: 'frame $i',
      );
      expect(find.text('Ama typed this'), findsNothing, reason: 'frame $i');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Not even in memory (Task 6 addition).
      expect(_answerTexts(t), ['', '', ''], reason: 'frame $i');
      _expectNoCarryOver(t, 'frame $i', lastGone: i > 0);
    }
    p.gateway.hold!.complete();
    await t.pumpAndSettle();
    expect(find.text('Someone kind'), findsOneWidget);
    expect(find.text('Patience with myself'), findsNothing);
    expect(find.text('Ama typed this'), findsNothing);
  });

  testWidgets('D8: the next account\'s read fails: an error, never the last '
      'account\'s answers', (t) async {
    final p = await _open(t);
    p.gateway
      ..hold = Completer<void>()
      ..readError = Exception('offline');
    _container(t).read(_signedIn.notifier).state = 'kofi';
    await t.pump();
    p.gateway.hold!.complete();
    await t.pumpAndSettle();
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    expect(find.text('Patience with myself'), findsNothing);
    // Fix round 1 (I-2, M-4.1): the error holds nothing of the last account.
    _expectNoCarryOver(t, 'after the failure');
    expect(_answerTexts(t), ['', '', '']);
  });

  testWidgets('accessibility: tap targets, labels, contrast', (t) async {
    await _open(t);
    await expectFlowGuidelines(t);
  });

  testWidgets('goldens: D0', (t) async {
    await expectFlowGoldens(
      t,
      'gentle_wait',
      () => GentleWaitScreen(onSetUp: () {}),
      overrides: [
        gentleWaitAccountProvider.overrideWith((ref) => ref.watch(_signedIn)),
        gentleWaitGatewayProvider.overrideWith(
          (ref) => _FakeGateway(() => ref.read(_signedIn)),
        ),
        datingOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
    );
  });

  // Its own test: a new ProviderScope in the same test keeps the first
  // scope's connection.
  testWidgets('goldens: D0 offline', (t) async {
    await expectFlowGoldens(
      t,
      'gentle_wait_offline',
      () => GentleWaitScreen(onSetUp: () {}),
      overrides: [
        gentleWaitAccountProvider.overrideWith((ref) => ref.watch(_signedIn)),
        gentleWaitGatewayProvider.overrideWith(
          (ref) => _FakeGateway(() => ref.read(_signedIn)),
        ),
        datingOnlineProvider.overrideWith((ref) => Stream.value(false)),
      ],
      // The connection is known a frame after the first read.
      before: (t) async {
        await t.pumpAndSettle();
        expect(
          find.text("You're offline. Dating needs a connection."),
          findsOneWidget,
        );
      },
    );
  });

  // ---- Task 6 additions (batch 5): B3 carries, D8 edges, quick exit,
  // the privacy cover, reduce motion.

  testWidgets('D8: the next account\'s read fails, then Retry: its own '
      'answers, never the last account\'s', (t) async {
    final p = await _open(t);
    p.gateway
      ..hold = Completer<void>()
      ..readError = Exception('offline');
    _container(t).read(_signedIn.notifier).state = 'kofi';
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Patience with myself'), findsNothing);
      expect(_answerTexts(t), ['', '', ''], reason: 'frame $i');
      _expectNoCarryOver(t, 'frame $i', lastGone: i > 0);
    }
    p.gateway.hold!.complete();
    await t.pumpAndSettle();
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    _expectNoCarryOver(t, 'failed');
    p.gateway
      ..readError = null
      ..hold = Completer<void>();
    await tapInReach(t, find.text('Retry'));
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Patience with myself'), findsNothing);
      expect(_answerTexts(t), ['', '', ''], reason: 'retry frame $i');
      _expectNoCarryOver(t, 'retry frame $i');
    }
    p.gateway.hold!.complete();
    await t.pumpAndSettle();
    expect(find.text('Someone kind'), findsOneWidget);
    expect(find.text('Patience with myself'), findsNothing);
  });

  testWidgets('D8: "saved" never carries over to the next account', (t) async {
    await _open(t);
    await tapInReach(t, find.text('Save my answers'));
    await t.pumpAndSettle();
    expect(find.text('Your answers are saved.'), findsOneWidget);
    _container(t).read(_signedIn.notifier).state = 'kofi';
    await t.pumpAndSettle();
    expect(find.text('Someone kind'), findsOneWidget);
    expect(find.text('Your answers are saved.'), findsNothing);
  });

  testWidgets('D8: a save still out when the account changes says nothing '
      'to the next account', (t) async {
    final p = await _open(t);
    p.gateway.saveHold = Completer<void>();
    await tapInReach(t, find.text('Save my answers'));
    await t.pump();
    _container(t).read(_signedIn.notifier).state = 'kofi';
    await t.pumpAndSettle();
    p.gateway.saveHold!.complete();
    await t.pumpAndSettle();
    expect(find.text('Someone kind'), findsOneWidget);
    expect(find.text('Your answers are saved.'), findsNothing);
    expect(find.text('Something went wrong. Try again.'), findsNothing);
    // The next account's Save is its own: not stuck behind the last one's.
    p.gateway.saveHold = null;
    await tapInReach(t, find.text('Save my answers'));
    await t.pumpAndSettle();
    expect(p.gateway.saves.last, {'q1': '', 'q2': 'Someone kind', 'q3': ''});
    expect(find.text('Your answers are saved.'), findsOneWidget);
  });

  testWidgets('D8: signing out empties the fields; the next account starts '
      'from its own', (t) async {
    final p = await _open(t);
    await t.enterText(
      find.byKey(const ValueKey('gentle_wait_q3')),
      'Ama typed this',
    );
    _container(t).read(_signedIn.notifier).state = null;
    await t.pumpAndSettle();
    expect(find.text('Patience with myself'), findsNothing);
    expect(find.text('Ama typed this'), findsNothing);
    p.gateway.hold = Completer<void>();
    _container(t).read(_signedIn.notifier).state = 'kofi';
    await t.pump();
    expect(find.text('Ama typed this'), findsNothing);
    p.gateway.hold!.complete();
    await t.pumpAndSettle();
    expect(find.text('Someone kind'), findsOneWidget);
    expect(find.text('Ama typed this'), findsNothing);
  });

  testWidgets('D8: signed out and back in, the same account gets its own '
      'answers again (never blank fields that would save as a clear)', (
    t,
  ) async {
    await _open(t);
    _container(t).read(_signedIn.notifier).state = null;
    await t.pumpAndSettle();
    expect(find.text('Patience with myself'), findsNothing);
    _container(t).read(_signedIn.notifier).state = 'ama';
    await t.pumpAndSettle();
    expect(find.text('Patience with myself'), findsOneWidget);
    expect(find.text('Clear my answers'), findsNothing);
  });

  testWidgets('busy save: a calm line, no error wording, the text kept, and '
      'Save tries again', (t) async {
    final p = await _open(t);
    p.gateway.saveResult = GentleWaitSave.busy;
    await t.enterText(find.byKey(const ValueKey('gentle_wait_q2')), 'Kindness');
    await tapInReach(t, find.text('Save my answers'));
    await t.pumpAndSettle();
    expect(
      find.text(
        'This is taking a little longer than usual. Your answers are still '
        'here, so try again in a moment.',
      ),
      findsOneWidget,
    );
    expect(find.text('Something went wrong. Try again.'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.text('Kindness'), findsOneWidget);
    p.gateway.saveResult = GentleWaitSave.saved;
    await tapInReach(t, find.text('Save my answers'));
    await t.pumpAndSettle();
    expect(p.gateway.saves, hasLength(2));
    expect(p.gateway.saves.last['q2'], 'Kindness');
    expect(find.text('Your answers are saved.'), findsOneWidget);
    expect(find.textContaining('taking a little longer'), findsNothing);
  });

  testWidgets('all blank with answers saved: the button is the clear, and '
      'says so when done', (t) async {
    final p = await _open(t);
    await t.enterText(find.byKey(const ValueKey('gentle_wait_q1')), '');
    await t.pump();
    expect(find.text('Save my answers'), findsNothing);
    await tapInReach(t, find.text('Clear my answers'));
    await t.pumpAndSettle();
    // Fix round 1 (I-1): the never-gated clear, not the gated save.
    expect(p.gateway.clears, 1);
    expect(p.gateway.saves, isEmpty);
    expect(find.text('Your answers are cleared.'), findsOneWidget);
    expect(find.text('Your answers are saved.'), findsNothing);
    // Nothing is saved now, so blank fields are a plain save again.
    expect(find.text('Save my answers'), findsOneWidget);
  });

  for (final (name, blank) in [
    ('spaces', '   '),
    ('a newline', '\n'),
    ('a tab', '\t'),
    ('a mix', ' \n\t\r '),
  ]) {
    testWidgets('$name only counts as blank: the clear, sent as the clear '
        '(fix round 1, I-1)', (t) async {
      final p = await _open(t);
      await t.enterText(find.byKey(const ValueKey('gentle_wait_q1')), blank);
      await t.pump();
      await tapInReach(t, find.text('Clear my answers'));
      await t.pumpAndSettle();
      expect(p.gateway.clears, 1);
      expect(p.gateway.saves, isEmpty);
      expect(find.text('Your answers are cleared.'), findsOneWidget);
    });
  }

  testWidgets('a save sends blank for a field of whitespace, and trims the '
      'rest (fix round 1, I-1)', (t) async {
    final p = await _open(t);
    await t.enterText(find.byKey(const ValueKey('gentle_wait_q2')), '\n\t ');
    await t.enterText(
      find.byKey(const ValueKey('gentle_wait_q3')),
      '  When I feel rushed\n',
    );
    await tapInReach(t, find.text('Save my answers'));
    await t.pumpAndSettle();
    expect(p.gateway.clears, 0);
    expect(p.gateway.saves, [
      {'q1': 'Patience with myself', 'q2': '', 'q3': 'When I feel rushed'},
    ]);
  });

  testWidgets('nothing saved and nothing typed: a plain save, never "clear"', (
    t,
  ) async {
    final p = await _open(t);
    p.gateway.data['ama'] = GentleWait(
      endedAt: DateTime.utc(2026, 11, 1, 12),
      opensAt: DateTime.utc(2026, 12, 1, 12),
    );
    _container(t).read(_signedIn.notifier).state = 'kofi';
    await t.pumpAndSettle();
    _container(t).read(_signedIn.notifier).state = 'ama';
    await t.pumpAndSettle();
    expect(find.text('Clear my answers'), findsNothing);
    expect(find.text('Save my answers'), findsOneWidget);
    // Final review M-6: nothing to save, so Save is off; a tap says nothing.
    expect(_saveButton(t).onPressed, isNull);
    await bringIntoReach(t, find.text('Save my answers'));
    await t.tap(find.text('Save my answers'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(p.gateway.saves, isEmpty);
    expect(p.gateway.clears, 0);
    expect(find.text('Your answers are saved.'), findsNothing);
    // Typing something turns it on; whitespace alone does not.
    await t.enterText(find.byKey(const ValueKey('gentle_wait_q2')), ' \n');
    await t.pump();
    expect(_saveButton(t).onPressed, isNull);
    await t.enterText(find.byKey(const ValueKey('gentle_wait_q2')), 'Hope');
    await t.pump();
    expect(_saveButton(t).onPressed, isNotNull);
  });

  testWidgets('busy clear: the calm line, never an error', (t) async {
    final p = await _open(t);
    p.gateway.saveResult = GentleWaitSave.busy;
    await t.enterText(find.byKey(const ValueKey('gentle_wait_q1')), '');
    await t.pump();
    await tapInReach(t, find.text('Clear my answers'));
    await t.pumpAndSettle();
    // Fix round 1 (M-5): its own line, never "your answers are still here".
    expect(
      find.text(
        'This is taking a little longer than usual. Try clearing again in a '
        'moment.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('still here'), findsNothing);
    expect(find.text('Something went wrong. Try again.'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.text('Your answers are cleared.'), findsNothing);
    // Still the clear: the server kept the answers. Trying again clears.
    expect(find.text('Clear my answers'), findsOneWidget);
    expect(p.gateway.clears, 1);
    expect(p.gateway.saves, isEmpty);
    p.gateway.saveResult = GentleWaitSave.saved;
    await tapInReach(t, find.text('Clear my answers'));
    await t.pumpAndSettle();
    expect(p.gateway.clears, 2);
    expect(find.text('Your answers are cleared.'), findsOneWidget);
  });

  testWidgets('busy read: a calm line and Retry, never an error', (t) async {
    final p = await _open(t);
    p.gateway.readError = const GentleWaitBusy();
    _container(t).invalidate(gentleWaitProvider);
    await t.pumpAndSettle();
    expect(
      find.text(
        'This is taking a little longer than usual. Try again in a moment.',
      ),
      findsOneWidget,
    );
    expect(find.text('Something went wrong. Try again.'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    p.gateway.readError = null;
    await tapInReach(t, find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.text('Patience with myself'), findsOneWidget);
  });

  for (final reduceMotion in [true, false]) {
    testWidgets('the loading ring never moves and reads no percentage '
        '(reduce motion $reduceMotion; fix round 1, M-2)', (t) async {
      final semantics = t.ensureSemantics();
      final p = await _open(t, reduceMotion: reduceMotion);
      p.gateway.hold = Completer<void>();
      _container(t).read(_signedIn.notifier).state = 'kofi';
      await t.pump();
      final ring = find.byType(CircularProgressIndicator);
      expect(t.widget<CircularProgressIndicator>(ring).value, isNotNull);
      final node = t.getSemantics(ring);
      expect(node.value, isEmpty);
      expect(node.label, 'Loading...');
      // Nothing is animating: it settles while the read is still out (an
      // indeterminate ring would never settle).
      await t.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      p.gateway.hold!.complete();
      await t.pumpAndSettle();
      semantics.dispose();
    });
  }

  testWidgets('Retry is busy while it reads, and a second failure is read '
      'out again (fix round 1, M-1)', (t) async {
    final p = await _open(t);
    p.gateway.readError = Exception('offline');
    _container(t).invalidate(gentleWaitProvider);
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('gentle_wait_read_failed_0')),
      findsOneWidget,
    );
    p.gateway.holdAny = Completer<void>();
    await tapInReach(t, find.text('Retry'));
    await t.pump();
    expect(
      t.widget<FlowSecondaryButton>(find.byType(FlowSecondaryButton)).busy,
      isTrue,
    );
    p.gateway.holdAny!.complete();
    await t.pumpAndSettle();
    // Failed again: a new live region, so it is announced again.
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gentle_wait_read_failed_1')),
      findsOneWidget,
    );
    expect(
      t.widget<FlowSecondaryButton>(find.byType(FlowSecondaryButton)).busy,
      isFalse,
    );
  });

  testWidgets('the real account provider: another signed-in user reads its '
      'own (fix round 1, M-4.2)', (t) async {
    late _FakeGateway gateway;
    await pumpFlowScreen(
      t,
      () => GentleWaitScreen(onSetUp: () {}),
      overrides: [
        currentUserProvider.overrideWith((ref) => ref.watch(_userNow)),
        gentleWaitGatewayProvider.overrideWith(
          (ref) => gateway = _FakeGateway(() => ref.read(_userNow)?.id),
        ),
        datingOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
    );
    await t.pumpAndSettle();
    expect(find.text('Patience with myself'), findsOneWidget);
    gateway.hold = Completer<void>();
    ProviderScope.containerOf(t.element(find.byType(GentleWaitScreen)))
        .read(_userNow.notifier)
        .state = _userKofi;
    await t.pump();
    expect(find.text('Patience with myself'), findsNothing);
    expect(_answerTexts(t), ['', '', '']);
    gateway.hold!.complete();
    await t.pumpAndSettle();
    expect(find.text('Someone kind'), findsOneWidget);
  });

  group('the root shell', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      QuickExitService.clearStories = () async {};
      addTearDown(() => QuickExitService.clearStories = clearStoryDeviceCaches);
    });

    testWidgets('quick exit works on D0 and takes the answers with it', (
      t,
    ) async {
      final shell = await _pumpShell(
        t,
        (router, child) => QuickExitZone(router: router, child: child),
      );
      await t.enterText(
        find.byKey(const ValueKey('gentle_wait_q3')),
        'Ama typed this',
      );
      final readsBefore = shell.gateway().reads;
      for (var i = 0; i < 3; i++) {
        await t.tap(
          find.byKey(const Key('quick_exit_zone')),
          warnIfMissed: false,
        );
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('DECOY'), findsOneWidget);
      expect(find.byType(GentleWaitScreen), findsNothing);
      // Back on D0: a new read, and nothing typed before is left.
      shell.router.go('/d0');
      await t.pumpAndSettle();
      expect(shell.gateway().reads, readsBefore + 1);
      expect(find.text('Ama typed this'), findsNothing);
      expect(find.text('Patience with myself'), findsOneWidget);
    });

    testWidgets('a quick exit started but not finished (two taps) keeps '
        'what was typed (fix round 1, M-4.3)', (t) async {
      await _pumpShell(
        t,
        (router, child) => QuickExitZone(router: router, child: child),
      );
      await t.enterText(
        find.byKey(const ValueKey('gentle_wait_q3')),
        'Ama typed this',
      );
      for (var i = 0; i < 2; i++) {
        await t.tap(
          find.byKey(const Key('quick_exit_zone')),
          warnIfMissed: false,
        );
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();
      expect(find.text('DECOY'), findsNothing);
      expect(find.text('Ama typed this'), findsOneWidget);
    });

    for (final online in [true, false]) {
      testWidgets(
        'accessibility in dark mode (${online ? 'online' : 'offline'})'
        ': tap targets, labels, contrast',
        (t) async {
          await _pumpShell(
            t,
            (router, child) => child,
            online: online,
            theme: AppTheme.darkTheme,
          );
          await t.pumpAndSettle();
          expect(
            find.text("You're offline. Dating needs a connection."),
            online ? findsNothing : findsOneWidget,
          );
          await expectFlowGuidelines(t);
        },
      );
    }

    testWidgets('accessibility with the calm busy line and the clear', (
      t,
    ) async {
      final p = await _open(t);
      p.gateway.saveResult = GentleWaitSave.busy;
      await t.enterText(find.byKey(const ValueKey('gentle_wait_q1')), '');
      await t.pump();
      await tapInReach(t, find.text('Clear my answers'));
      await t.pumpAndSettle();
      expect(find.textContaining('taking a little longer'), findsOneWidget);
      // The busy line mid-screen: no field half under the top edge (the
      // tap-target guideline measures only the part on screen).
      await Scrollable.ensureVisible(
        t.element(find.textContaining('taking a little longer')),
        alignment: 0.5,
      );
      await t.pumpAndSettle();
      await expectFlowGuidelines(t);
    });

    testWidgets('the privacy cover hides D0 and keeps what was typed', (
      t,
    ) async {
      await _pumpShell(t, (router, child) => AppPrivacyCover(child: child));
      await t.enterText(
        find.byKey(const ValueKey('gentle_wait_q3')),
        'Ama typed this',
      );
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      expect(
        find.byKey(const Key('app_privacy_cover_overlay')),
        findsOneWidget,
      );
      expect(find.text('Ama typed this'), findsNothing);
      expect(find.text('Before you begin'), findsNothing);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(find.byKey(const Key('app_privacy_cover_overlay')), findsNothing);
      expect(find.text('Ama typed this'), findsOneWidget);
    });
  });
}

final _user = User(
  id: 'ama',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'a',
  createdAt: '2026-01-01T00:00:00Z',
);

final _userKofi = User(
  id: 'kofi',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'a',
  createdAt: '2026-01-01T00:00:00Z',
);

/// The signed-in user, for the test that keeps the real account provider.
final _userNow = StateProvider<User?>((ref) => _user);

/// Fix round 1 (I-2): the next account's entry never holds the last one's
/// answers (no previous value), and the last account's entry is gone.
/// The last account's entry is disposed on Riverpod's next frame, so
/// [lastGone] is checked from the second frame after the change.
void _expectNoCarryOver(WidgetTester t, String reason, {bool lastGone = true}) {
  final container = _container(t);
  final kofi = container.read(gentleWaitProvider('kofi'));
  expect(kofi.hasValue, isFalse, reason: reason);
  if (lastGone) {
    expect(
      container.exists(gentleWaitProvider('ama')),
      isFalse,
      reason: reason,
    );
  }
}

class _Shell {
  _Shell(this.router, this.gateway);

  final GoRouter router;
  final _FakeGateway Function() gateway;
}

/// D0 as the app shows it under the root shell's [wrap] (the quick-exit
/// zone or the privacy cover), with a decoy at the neutral screen.
Future<_Shell> _pumpShell(
  WidgetTester t,
  Widget Function(GoRouter router, Widget child) wrap, {
  bool online = true,
  ThemeData? theme,
}) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  _FakeGateway? gateway;
  final router = GoRouter(
    initialLocation: '/d0',
    routes: [
      GoRoute(
        path: '/d0',
        builder: (_, __) => GentleWaitScreen(onSetUp: () {}),
      ),
      GoRoute(
        path: RouteNames.neutralScreen,
        name: 'neutralScreen',
        builder: (_, __) => const Scaffold(body: Text('DECOY')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(_user),
        gentleWaitAccountProvider.overrideWith((ref) => ref.watch(_signedIn)),
        gentleWaitGatewayProvider.overrideWith(
          (ref) => gateway = _FakeGateway(() => ref.read(_signedIn)),
        ),
        datingOnlineProvider.overrideWith((ref) => Stream.value(online)),
      ],
      child: ScreenUtilConfig.builder(
        builder:
            (_) => MaterialApp.router(
              theme: theme ?? AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
              builder: (context, child) => wrap(router, child!),
            ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return _Shell(router, () => gateway!);
}
