// Spec 8 (research 06 F15 (2)-(3), B10; plan review C3, I17): the fixed
// cards the deterministic pre-check returns, the always-on Understand
// footer and the handoff to "a trained outside perspective".
import 'package:attune/core/services/app_privacy_cover.dart';
import 'package:attune/features/ai_assistant/data/models/understand_result_model.dart';
import 'package:attune/features/ai_assistant/data/repositories/ai_assistant_repository.dart';
import 'package:attune/features/ai_assistant/data/repositories/assistant_error.dart';
import 'package:attune/features/ai_assistant/presentation/providers/ai_assistant_providers.dart';
import 'package:attune/features/ai_assistant/presentation/screens/understand_sheet.dart';
import 'package:attune/features/ai_assistant/presentation/widgets/assistant_notice_card.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/safety/self_check/safety_self_check_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _footer =
    'These are guesses from the words alone. Only they know what they meant. '
    'If this is about trust, a trained outside perspective helps more than a reading.';

class _Gateway implements AiAssistantGateway {
  _Gateway(this.result);
  final dynamic result;

  @override
  Future<dynamic> invokeFunction(String functionName, {Map<String, dynamic>? body}) async => result;

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) => throw UnsupportedError('no rpc');

  @override
  Future<Map<String, dynamic>?> selectPlanningLink(String messageId) => throw UnsupportedError('no link');
}

Future<void> _pump(WidgetTester t, dynamic result, {bool b10 = true}) async {
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(ProviderScope(
    overrides: [
      aiAssistantRepositoryProvider.overrideWithValue(AiAssistantRepository(_Gateway(result))),
      safetySelfCheckEnabledProvider.overrideWith((ref) async => b10),
    ],
    child: MaterialApp(
      home: AppPrivacyCover(
        child: UnderstandSheet(
          message: Message(
            id: 'm1', clientMessageId: 'c1', relationshipId: 'r1', senderId: 'partner', content: 'Not tonight.',
            createdAt: DateTime(2026, 10, 18), status: MessageStatus.sent, isMine: false,
          ),
        ),
      ),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 30));
}

void main() {
  test('Understand parses the two fixed outcomes', () {
    expect(UnderstandResultModel.fromJson({'status': 'boundary'}), isA<UnderstandResultBoundary>());
    expect(UnderstandResultModel.fromJson({'status': 'supporter'}), isA<UnderstandResultSupporter>());
  });

  testWidgets('a "no": the fixed line, no readings; the footer and handoff always show', (t) async {
    await _pump(t, {'status': 'boundary'});
    expect(find.text(kBoundaryLine), findsOneWidget);
    expect(kBoundaryLine, "A no is complete on its own. If you want to understand more, ask them when you're both calm.");
    expect(find.text('Possible readings'), findsNothing);
    expect(find.text(_footer), findsOneWidget);
    expect(find.text('A trained outside perspective'), findsOneWidget);
  });

  testWidgets('B10 off: the footer still shows, without the link to placeholder content', (t) async {
    await _pump(t, {'status': 'boundary'}, b10: false);
    expect(find.text(_footer), findsOneWidget);
    expect(find.text('A trained outside perspective'), findsNothing);
  });

  // Final review I-6: the supporter and writer cards' own words await
  // clinician review; with the flag off they show only the Safety
  // resources line that already ships, and its link.
  testWidgets('flag off: the supporter card shows only shipped copy', (t) async {
    await _pump(t, {'status': 'supporter'}, b10: false);
    expect(find.text(kShippedSafetyLine), findsOneWidget);
    expect(find.textContaining('[DRAFT]'), findsNothing);
    expect(find.text('When your partner is struggling'), findsNothing);
    expect(find.text('See support options'), findsOneWidget);
  });

  testWidgets('flag on: the drafts show, marked', (t) async {
    await _pump(t, {'status': 'supporter'}, b10: true);
    expect(find.textContaining('[DRAFT] If they might be in danger'), findsOneWidget);
    expect(find.text(kShippedSafetyLine), findsNothing);
  });

  testWidgets('the footer shows with an ordinary reading too', (t) async {
    await _pump(t, {
      'status': 'ok', 'possible_readings': ['They might be tired.'], 'response_options': ['Want to talk?'],
      'confidence': 'low',
    });
    expect(find.text(_footer), findsOneWidget);
  });

  testWidgets('self-harm in the partner\'s message: the supporter card, crisis line first', (t) async {
    await _pump(t, {'status': 'supporter'});
    expect(find.textContaining('emergency'), findsOneWidget);
    expect(find.text('Possible readings'), findsNothing);
  });

  test('Assist returns its notices as a typed error, never a parse failure', () async {
    for (final (status, notice) in [
      ('boundary', AssistantNotice.boundary),
      ('supporter', AssistantNotice.supporter),
      ('writer_resources', AssistantNotice.writerResources),
    ]) {
      final repo = AiAssistantRepository(_Gateway({'status': status}));
      await expectLater(
        repo.requestAssist(requestId: 'r', messageId: 'm1', assistKind: 'ideas'),
        throwsA(isA<AssistantNoticeError>().having((e) => e.notice, 'notice', notice)),
      );
    }
  });
}
