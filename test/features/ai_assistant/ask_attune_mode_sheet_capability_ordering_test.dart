// Guard test for the capability read in `_ConsentGatedModeChoice.build`.
//
// WHY THIS FILE EXISTS. Plan D's Task 9 shipped a real bug (fixed in
// `abb74a0b`): the capability was `ref.read` rather than `ref.watch`, so on
// a cold app session the first "Get ideas" tap started the FutureProvider's
// load, got `AsyncLoading`, and silently fell back to single-turn Assist —
// indistinguishable from the flag being off. The fix is one word, and
// nothing pinned it: substituting `read` back in leaves the whole
// ai_assistant suite green (measured: 401 passed).
//
// I had recorded that as an undistinguishable residual (Ruling 37). The
// final whole-branch review proved otherwise, and this is its test. The
// distinguishing property is not a neighbour's accidental timing but the
// resolution ORDER, which a test controls: complete consent FIRST so the
// tile becomes tappable, capabilities SECOND, then tap. That is also the
// realistic cold-start order, because `aiConsentStatusProvider` is
// `.autoDispose.family` (fresh per open) while the capability provider is a
// single app-wide read, so a slow capability RPC genuinely loses the race.
//
// If this test fails, do not relax it: a `read` here means the first tap of
// an app session opens the wrong sheet.
import 'dart:async';
import 'package:attune/features/ai_assistant/data/models/ai_session_model.dart';
import 'package:attune/features/ai_assistant/data/repositories/ai_assistant_repository.dart';
import 'package:attune/features/ai_assistant/data/repositories/ai_session_repository.dart';
import 'package:attune/features/ai_assistant/data/services/ai_session_capabilities.dart';
import 'package:attune/features/ai_assistant/presentation/providers/ai_assistant_providers.dart';
import 'package:attune/features/ai_assistant/presentation/providers/ai_session_provider.dart';
import 'package:attune/features/ai_assistant/presentation/screens/ai_session_sheet.dart';
import 'package:attune/features/ai_assistant/presentation/screens/ask_attune_mode_sheet.dart';
import 'package:attune/features/ai_assistant/presentation/screens/assist_sheet.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

User _u(String id) => User(id: id, appMetadata: const {},
    userMetadata: const {}, aud: 'authenticated',
    createdAt: DateTime.now().toIso8601String());

Message _partnerMessage() => Message.optimistic(
  id: 'msg-1', clientMessageId: 'c-1', relationshipId: 'rel-1',
  senderId: 'partner', content: 'dinner on friday?',
  createdAt: DateTime.now());

const _ideasSession = AiSessionCapabilities(assist: true,
  sessionsPrivate: true, sessionsShared: false,
  sessionsRecentWindow: false, sessionsNearby: false);

class _Unused implements AiAssistantGateway {
  Never _r(String w) => throw StateError('reached $w');
  @override
  Future<dynamic> invokeFunction(String f, {Map<String, dynamic>? body}) =>
      _r('invoke');
  @override
  Future<dynamic> rpc(String f, {Map<String, dynamic>? params}) => _r('rpc');
  @override
  Future<Map<String, dynamic>?> selectPlanningLink(String m) => _r('link');
}

void main() {
  testWidgets(
      'PROBE H: RULING 37 — capabilities resolving AFTER consent. '
      'Does the ON path still work?', (t) async {
    // The decisive timing: consent resolves FIRST (so _ModeChoiceList
    // builds and the tile becomes tappable), capabilities resolve
    // SECOND. With ref.watch this rebuilds and the ON path works.
    // With ref.read (M17) there would be no further rebuild and the
    // tile would fall back to single-turn Assist.
    final capsCompleter = Completer<AiSessionCapabilities>();
    final consentCompleter = Completer<AiConsentStatus>();
    var capsBuilds = 0;

    await t.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => _u('me')),
        currentRelationshipIdProvider
            .overrideWith((ref) => Future.value('rel-1')),
        aiConsentStatusProvider('rel-1')
            .overrideWith((ref) => consentCompleter.future),
        aiSessionCapabilitiesProvider.overrideWith((ref) {
          capsBuilds++;
          return capsCompleter.future;
        }),
        aiSessionRepositoryProvider
            .overrideWithValue(AiSessionRepository(_Unused())),
      ],
      child: MaterialApp(
        home: Builder(builder: (ctx) => Scaffold(
          body: Center(child: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: ctx,
              builder: (_) => AskAttuneModeSheet(message: _partnerMessage()),
            ),
            child: const Text('open'),
          )),
        )),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump();

    // STEP 1: resolve CONSENT only. The mode list should now build.
    consentCompleter.complete(const AiConsentStatus(
        callerGranted: true, bothGranted: true, policyVersion: 'v1'));
    await t.pumpAndSettle();
    // ignore: avoid_print
    print('PROBE H after consent: capsBuilds=$capsBuilds '
        'tiles=${find.byType(InkWell).evaluate().length}');
    final getIdeas = find.textContaining('ideas', findRichText: true);
    // ignore: avoid_print
    print('PROBE H "ideas" tile found: ${getIdeas.evaluate().length}');

    // STEP 2: resolve CAPABILITIES. With ref.watch the widget rebuilds.
    capsCompleter.complete(_ideasSession);
    await t.pumpAndSettle();

    // STEP 3: tap the Get ideas tile, then the Ideas kind in the picker,
    // and see WHICH sheet opens.
    if (getIdeas.evaluate().isEmpty) {
      // ignore: avoid_print
      print('PROBE H: could not find the tile; dumping texts');
      for (final w in t.widgetList<Text>(find.byType(Text))) {
        // ignore: avoid_print
        print('   TEXT: ${w.data}');
      }
      fail('tile not found');
    }
    await t.tap(getIdeas.first);
    await t.pumpAndSettle();
    // ignore: avoid_print
    print('PROBE H after tapping Get ideas, texts:');
    for (final w in t.widgetList<Text>(find.byType(Text))) {
      // ignore: avoid_print
      print('   TEXT: ${w.data}');
    }
    // The kind picker: pick Ideas.
    final ideasPick = find.text('Ideas');
    if (ideasPick.evaluate().isNotEmpty) {
      await t.tap(ideasPick.first);
      await t.pumpAndSettle();
    }
    final gotSession = find.byType(AiSessionSheet).evaluate().isNotEmpty;
    final gotAssist = find.byType(AssistSheet).evaluate().isNotEmpty;
    // ignore: avoid_print
    print('PROBE H RESULT: AiSessionSheet=$gotSession AssistSheet=$gotAssist '
        'capsBuilds=$capsBuilds');
    expect(gotSession, isTrue,
        reason: 'PROBE H: the ON path must open a SESSION when the '
            'capability is on, even though capabilities resolved AFTER '
            'consent. If this fails, M17 (ref.read) IS distinguishable.');
  });
}
