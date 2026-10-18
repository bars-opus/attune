// Spec 8 (F15 (1), P10; ATTUNE_RISK_SOLUTIONS §2.3 item 2): every shared
// conflict-adjacent insight carries the co-framing line, verbatim, on the
// Verdict's watch areas.
import 'package:attune/features/verdict/data/models/services/verdict_service.dart';
import 'package:attune/features/verdict/data/models/verdict.dart';
import 'package:attune/features/verdict/presentation/providers/verdict_providers.dart';
import 'package:attune/features/verdict/presentation/screens/verdict_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Service extends VerdictService {
  _Service()
    : super(
        SupabaseClient(
          'http://localhost',
          'anon',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  @override
  Future<void> markViewed(String verdictId) async {}
}

Map<String, dynamic> _item(String title) => {
  'title': title,
  'body': '$title body',
  'evidence_ids': ['pulse:p1:connection'],
};

void main() {
  test('the line, verbatim', () {
    expect(
      kCoFramingLine,
      'This is a pattern, not a verdict on either of you. Citing it as '
      'evidence in an argument usually backfires — if you want to talk about '
      "it, ask, don't quote.",
    );
  });

  testWidgets('the watch areas carry the co-framing line', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final verdict = Verdict.fromJson({
      'id': 'v1',
      'relationship_id': 'r1',
      'period_start': '2026-09-01',
      'period_end': '2026-10-01',
      'snapshot_at': '2026-10-01T00:00:00Z',
      'generated_at': '2026-10-01T00:00:00Z',
      'status': 'published',
      'data_confidence': 'medium',
      'confidence_label': 'Based on 9 weeks of data',
      'headline': 'A steady month',
      'strengths': [_item('Connection')],
      'watch_areas': [_item('A dip')],
      'one_action': 'Plan an evening.',
      'one_action_evidence_ids': ['pulse:p1:connection'],
      'patterns_referenced': <String>[],
      'disclaimer': 'x',
      'input_schema_version': '1.1.0',
      'prompt_version': '1.1.0',
      'model_provider': 'x',
      'model_name': 'x',
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          verdictServiceProvider.overrideWithValue(_Service()),
          verdictLoadProvider.overrideWith(
            (ref) async => VerdictLoadState(
              status: VerdictLoadStatus.available,
              periodStart: DateTime.utc(2026, 9),
              periodEnd: DateTime.utc(2026, 10),
              verdict: verdict,
            ),
          ),
        ],
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, __) => MaterialApp(
                builder:
                    (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(disableAnimations: true),
                      child: child!,
                    ),
                home: const VerdictScreen(),
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Watch areas'), findsOneWidget);
    expect(find.text(kCoFramingLine), findsOneWidget);
  });
}
