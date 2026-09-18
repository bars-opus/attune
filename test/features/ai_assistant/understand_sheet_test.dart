// Widget tests for UnderstandSheet (AI Assistant spec §6): the private,
// ephemeral interpretation-help sheet.
//
// This is the single most privacy-sensitive screen in the whole feature
// (spec §6.3): no Copy, Share, Add to Planning, Send, or composer-prefill
// affordance anywhere in this widget's tree. Beyond the usual widget-tree
// assertions, this file also does static source inspection of
// understand_sheet.dart itself (matching the brief's own suggested
// pattern for proving an ABSENCE, not a presence, since a widget-tree
// search only proves "not built for this particular result," not "the
// capability does not exist in the file at all").
//
// Design decisions this test file locks in (spec leaves the exact
// widget shape open):
//  - the uncertainty-forward framing ("Attune cannot know what your
//    partner meant") is rendered for EVERY `ok` result regardless of
//    confidence (spec §6.1: shown before the result, not gated on low
//    confidence) — this is one of the two guarantees mutation-tested in
//    the task report.
//  - a discreet "Safety Resources" link renders identically across every
//    result/error state, `unsafe_to_infer` included, so its presence can
//    never be used as a side channel revealing that the deterministic
//    safety pipeline separately fired (spec §6.2) — the other
//    mutation-tested guarantee.
import 'dart:io';

import 'package:attune/core/services/app_privacy_cover.dart';
import 'package:attune/features/ai_assistant/data/repositories/ai_assistant_repository.dart';
import 'package:attune/features/ai_assistant/presentation/providers/ai_assistant_providers.dart';
import 'package:attune/features/ai_assistant/presentation/screens/understand_sheet.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAiAssistantGateway implements AiAssistantGateway {
  Object? nextInvokeError;
  dynamic nextInvokeResult;
  int invokeCallCount = 0;

  @override
  Future<dynamic> invokeFunction(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    invokeCallCount++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (nextInvokeError != null) {
      final error = nextInvokeError!;
      nextInvokeError = null;
      throw error;
    }
    return nextInvokeResult;
  }

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async {
    throw UnsupportedError('UnderstandSheet must never call an RPC');
  }
}

Map<String, dynamic> _okResponse({
  List<String> possibleReadings = const [
    'They might be tired.',
    'They might be distracted.',
  ],
  List<String> responseOptions = const [
    'Want to talk about it?',
    'No worries either way.',
  ],
  String confidence = 'low',
}) => {
  'status': 'ok',
  'possible_readings': possibleReadings,
  'response_options': responseOptions,
  'confidence': confidence,
};

Map<String, dynamic> _cannotHelpResponse({
  String reason = 'unsafe_to_infer',
}) => {'status': 'cannot_help', 'reason': reason};

Message _message({String senderId = 'partner', String id = 'm1'}) {
  return Message(
    id: id,
    clientMessageId: 'c-$id',
    relationshipId: 'rel-1',
    senderId: senderId,
    content: 'fine.',
    createdAt: DateTime(2026, 9, 18),
    status: MessageStatus.sent,
    isMine: false,
  );
}

Future<ProviderContainer> _pumpSheet(
  WidgetTester tester, {
  required _FakeAiAssistantGateway gateway,
}) async {
  final container = ProviderContainer(
    overrides: [
      aiAssistantRepositoryProvider.overrideWithValue(
        AiAssistantRepository(gateway),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: AppPrivacyCover(
          child: UnderstandSheet(message: _message()),
        ),
      ),
    ),
  );
  // Understand auto-requests on open (there is nothing else the user
  // could do to trigger the private read — the sheet's whole purpose is
  // this one result), so give it time to resolve.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 30));
  return container;
}

/// Reads understand_sheet.dart's own source once per test run and asserts
/// it contains none of the forbidden affordances anywhere in the file —
/// not merely "not built for this result." Matches the brief's own
/// suggested static-inspection pattern for proving an absence.
String _readSheetSource() {
  final file = File(
    'lib/features/ai_assistant/presentation/screens/understand_sheet.dart',
  );
  return file.readAsStringSync();
}

void main() {
  group('static source guarantees (spec §6.3)', () {
    test(
      'the sheet file contains no Copy/Share/Planning/composer/Send '
      'affordance anywhere in its source, not just absent from one built '
      'tree — matched as an identifier-ish token (word boundaries) so an '
      'unrelated Flutter SDK member like copyWith, or the word appearing '
      'only inside this very test file\'s own reasoning, cannot produce '
      'a false positive',
      () {
        final source = _readSheetSource();

        // Word-boundary regexes: reject the forbidden term as a whole
        // word/identifier fragment (case-insensitive), but allow it as
        // a substring of an unrelated, longer SDK identifier such as
        // `copyWith` (a getter every StatelessWidget's TextStyle uses,
        // not an affordance) by requiring a non-letter on both sides.
        final forbiddenPatterns = <String, RegExp>{
          'Clipboard': RegExp(r'\bClipboard\b'),
          'Share/share (as an action, e.g. Share.share/onShare/ShareButton/Icons.share)':
              RegExp(
                r'\bshare[A-Z_]|\bonShare\b|Share\.\w|ShareButton\b|Icons\.share\b',
              ),
          'Add to Planning / Planning (feature reference)': RegExp(
            r'[Pp]lanning',
          ),
          'composer (chat composer/prefill reference)': RegExp(
            r'[Cc]omposer',
          ),
          'a literal "Copy" affordance (Icons.copy / a Copy button)':
              RegExp(r'Icons\.copy\b|\bCopy\b'),
          'a literal Send affordance (Icons.send / a Send button/callback)':
              RegExp(r'Icons\.send\b|\bSend\b|\bonSend\b'),
        };

        for (final entry in forbiddenPatterns.entries) {
          expect(
            entry.value.hasMatch(source),
            isFalse,
            reason:
                'understand_sheet.dart must never reference '
                '${entry.key} — spec §6.3 forbids Copy, Share, Add to '
                'Planning, Send, or composer-prefill anywhere in this '
                "widget's tree",
          );
        }
      },
    );
  });

  group('ok result', () {
    testWidgets(
      'renders 2-3 possibleReadings and 2-3 responseOptions',
      (tester) async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _okResponse(
            possibleReadings: const [
              'They might be tired.',
              'They might be distracted.',
              'They might be short on words today.',
            ],
            responseOptions: const [
              'Want to talk about it?',
              'No worries either way.',
            ],
          );
        await _pumpSheet(tester, gateway: gateway);

        expect(find.text('They might be tired.'), findsOneWidget);
        expect(find.text('They might be distracted.'), findsOneWidget);
        expect(
          find.text('They might be short on words today.'),
          findsOneWidget,
        );
        expect(find.text('Want to talk about it?'), findsOneWidget);
        expect(find.text('No worries either way.'), findsOneWidget);
      },
    );

    testWidgets(
      'no interactive affordance beyond dismissing exists in the built '
      'tree for an ok result: no widget/button/icon labeled Copy, Share, '
      'Add to Planning, Send, or any composer-prefill trigger',
      (tester) async {
        final gateway = _FakeAiAssistantGateway()..nextInvokeResult = _okResponse();
        await _pumpSheet(tester, gateway: gateway);

        for (final label in [
          'Copy',
          'Share',
          'Add to Planning',
          'Send',
          'Use this',
          'Insert',
        ]) {
          expect(
            find.text(label),
            findsNothing,
            reason: '"$label" must not appear anywhere in the built tree',
          );
        }
        expect(find.byIcon(Icons.copy), findsNothing);
        expect(find.byIcon(Icons.share), findsNothing);
        expect(find.byIcon(Icons.send), findsNothing);
      },
    );
  });

  group('confidence framing (spec §6.1)', () {
    testWidgets(
      'the "Attune cannot know what your partner meant" framing (or '
      'equivalent uncertainty-forward copy) shows for a LOW-confidence '
      'result',
      (tester) async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _okResponse(confidence: 'low');
        await _pumpSheet(tester, gateway: gateway);

        expect(
          find.textContaining('Attune cannot know what your partner meant'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the SAME uncertainty-forward framing shows for a MEDIUM-confidence '
      'result too — this is not gated on low confidence alone',
      (tester) async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _okResponse(confidence: 'medium');
        await _pumpSheet(tester, gateway: gateway);

        expect(
          find.textContaining('Attune cannot know what your partner meant'),
          findsOneWidget,
          reason:
              'spec §6.1: the UI says this before the result, not only '
              'when model confidence is low',
        );
      },
    );
  });

  group('Safety Resources link parity (spec §6.2 anti-side-channel)', () {
    testWidgets(
      'unsafe_to_infer shows a Safety Resources link',
      (tester) async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _cannotHelpResponse(reason: 'unsafe_to_infer');
        await _pumpSheet(tester, gateway: gateway);

        expect(find.text('Safety Resources'), findsOneWidget);
      },
    );

    testWidgets(
      'an ordinary ok result shows the IDENTICAL Safety Resources link — '
      'same widget, same visibility — as unsafe_to_infer, so its presence '
      'cannot be used to infer whether the deterministic safety pipeline '
      'separately fired',
      (tester) async {
        final okGateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _okResponse();
        await _pumpSheet(tester, gateway: okGateway);
        expect(find.text('Safety Resources'), findsOneWidget);
      },
    );

    testWidgets(
      'insufficient_context (a different cannot_help reason) ALSO shows '
      'the identical Safety Resources link, proving parity is not merely '
      'coincidental between one ok case and one cannot_help case',
      (tester) async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _cannotHelpResponse(
            reason: 'insufficient_context',
          );
        await _pumpSheet(tester, gateway: gateway);
        expect(find.text('Safety Resources'), findsOneWidget);
      },
    );
  });

  group('dismiss (spec §6.3)', () {
    testWidgets(
      'dismissing the sheet clears understandResultProvider back to its '
      'initial/empty state, not merely unmounting the widget',
      (tester) async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _okResponse();
        final container = await _pumpSheet(tester, gateway: gateway);

        expect(container.read(understandResultProvider).value, isNotNull);

        await tester.tap(find.byTooltip('Back'));
        await tester.pump(const Duration(milliseconds: 30));

        expect(
          container.read(understandResultProvider).value,
          isNull,
          reason:
              'dismissing must clear the provider back to idle, re-read '
              'directly from the provider rather than just checking the '
              'widget unmounted',
        );
      },
    );
  });

  group('backgrounding while open (spec §6.3 + Task 1 privacy cover)', () {
    testWidgets(
      'backgrounding the app clears understandResultProvider AND the '
      'app privacy cover is simultaneously active — both guarantees fire '
      'together on the same simulated lifecycle transition',
      (tester) async {
        final gateway = _FakeAiAssistantGateway()
          ..nextInvokeResult = _okResponse();
        final container = await _pumpSheet(tester, gateway: gateway);

        expect(container.read(understandResultProvider).value, isNotNull);
        expect(
          find.byKey(const Key('app_privacy_cover_overlay')),
          findsNothing,
        );

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();

        expect(
          find.byKey(const Key('app_privacy_cover_overlay')),
          findsOneWidget,
          reason: 'the global privacy cover (Task 1) must be active',
        );
        expect(
          container.read(understandResultProvider).value,
          isNull,
          reason:
              "backgrounding must clear the Understand result via the "
              "same AppLifecycleListener mechanism Task 1's own test uses",
        );

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        // Settle any timer the fake gateway's artificial network delay
        // left pending (harmless here — the request was already
        // superseded by the background-clear above) so the test
        // binding's own "no pending timers" invariant check at teardown
        // doesn't flag it as if it were a real leak.
        await tester.pump(const Duration(milliseconds: 30));
      },
    );
  });
}
