// Widget tests for AskAttuneModeSheet (AI Assistant spec §3): the
// mode-choice screen shown from the chat long-press menu's "Ask Attune"
// action.
//
// Covers:
//  - both mode tiles render with the spec's exact copy;
//  - "Possible ways to read this" (Understand) is hidden when the
//    message is the caller's own (spec §3's UX gate — the server
//    independently enforces the same rule, but the client must not
//    even offer the option);
//  - the consent disclosure gates both modes until the caller grants;
//  - a caller-granted/partner-pending state shows "waiting for your
//    partner" and makes tapping a mode a no-op (no edge function call —
//    modeled here as no draft/understand request being issued, since
//    this sheet's own tiles are the only place such a call could start
//    from).
import 'package:attune/features/ai_assistant/data/repositories/ai_assistant_repository.dart';
import 'package:attune/features/ai_assistant/presentation/providers/ai_assistant_providers.dart';
import 'package:attune/features/ai_assistant/presentation/screens/ask_attune_mode_sheet.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Message _message({
  required String senderId,
  String id = 'm1',
  String content = 'want to grab dinner this weekend?',
}) {
  return Message(
    id: id,
    clientMessageId: 'c-$id',
    relationshipId: 'rel-1',
    senderId: senderId,
    content: content,
    createdAt: DateTime(2026, 9, 18),
    status: MessageStatus.sent,
    isMine: senderId == 'user-a',
  );
}

User _testUser(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime.now().toIso8601String(),
);

Future<ProviderContainer> _pumpSheet(
  WidgetTester tester, {
  required Message message,
  required String currentUserId,
  required AiConsentStatus Function() consentStatus,
}) async {
  final container = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWithValue(_testUser(currentUserId)),
      currentRelationshipIdProvider.overrideWith((ref) async => 'rel-1'),
      aiConsentStatusProvider(
        'rel-1',
      ).overrideWith((ref) async => consentStatus()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: AskAttuneModeSheet(message: message)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump(const Duration(milliseconds: 60));
  return container;
}

void main() {
  group('mode tiles', () {
    testWidgets(
      'both mode options render with the spec §3 exact copy for a '
      "partner's message when consent is fully granted",
      (tester) async {
        await _pumpSheet(
          tester,
          message: _message(senderId: 'partner'),
          currentUserId: 'user-a',
          consentStatus:
              () => const AiConsentStatus(
                callerGranted: true,
                bothGranted: true,
                policyVersion: 'v1',
              ),
        );

        expect(find.text('Get ideas'), findsOneWidget);
        expect(
          find.text(
            'Create suggestions you can preview and choose to share.',
          ),
          findsOneWidget,
        );
        expect(find.text('Possible ways to read this'), findsOneWidget);
        expect(
          find.text(
            "Private to you. Attune cannot know what your partner meant.",
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Understand is hidden when the message is the caller\'s own',
      (tester) async {
        await _pumpSheet(
          tester,
          message: _message(senderId: 'user-a'),
          currentUserId: 'user-a',
          consentStatus:
              () => const AiConsentStatus(
                callerGranted: true,
                bothGranted: true,
                policyVersion: 'v1',
              ),
        );

        expect(find.text('Get ideas'), findsOneWidget);
        expect(find.text('Possible ways to read this'), findsNothing);
      },
    );

    testWidgets(
      'Understand is offered for a partner message (sender_id != '
      'auth.uid())',
      (tester) async {
        await _pumpSheet(
          tester,
          message: _message(senderId: 'partner'),
          currentUserId: 'user-a',
          consentStatus:
              () => const AiConsentStatus(
                callerGranted: true,
                bothGranted: true,
                policyVersion: 'v1',
              ),
        );

        expect(find.text('Possible ways to read this'), findsOneWidget);
      },
    );
  });

  group('consent gate', () {
    testWidgets(
      'shows the disclosure/consent prompt first when the caller has '
      'not yet granted, and neither mode is offered',
      (tester) async {
        await _pumpSheet(
          tester,
          message: _message(senderId: 'partner'),
          currentUserId: 'user-a',
          consentStatus:
              () => const AiConsentStatus(
                callerGranted: false,
                bothGranted: false,
                policyVersion: 'v1',
              ),
        );

        expect(find.text('Before you use Ask Attune'), findsOneWidget);
        expect(find.text('Get ideas'), findsNothing);
        expect(find.text('Possible ways to read this'), findsNothing);
      },
    );

    testWidgets(
      'caller granted but partner has not: shows "waiting for your '
      "partner's consent\" and selecting a mode is a no-op",
      (tester) async {
        await _pumpSheet(
          tester,
          message: _message(senderId: 'partner'),
          currentUserId: 'user-a',
          consentStatus:
              () => const AiConsentStatus(
                callerGranted: true,
                bothGranted: false,
                policyVersion: 'v1',
              ),
        );

        expect(
          find.text("Waiting for your partner's consent"),
          findsOneWidget,
        );
        // Both tiles are still visible (so the boundary is legible) but
        // disabled — tapping must not call either edge function. There
        // is no request-tracking seam wired into this sheet yet
        // (Tasks 5/6 own that), so the absence of any navigation/
        // request side effect after the tap is what this asserts:
        // the tile's onTap is null while waiting.
        final getIdeasTile = tester.widget<InkWell>(
          find.descendant(
            of: find.byKey(const ValueKey('ask-attune-mode-assist')),
            matching: find.byType(InkWell),
          ),
        );
        expect(getIdeasTile.onTap, isNull);

        final understandTile = tester.widget<InkWell>(
          find.descendant(
            of: find.byKey(const ValueKey('ask-attune-mode-understand')),
            matching: find.byType(InkWell),
          ),
        );
        expect(understandTile.onTap, isNull);
      },
    );
  });
}
