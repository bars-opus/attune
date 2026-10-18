// Spec 8 (P7, P8, M5; F15 (2)): the sheet offers NVC or plain words,
// remembered on this device; a writer card replaces the rewrite; the
// seventh need reads naturally.
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/conflict_translator/data/models/translator_request.dart';
import 'package:attune/features/conflict_translator/data/models/translator_response.dart';
import 'package:attune/features/conflict_translator/presentation/providers/translator_providers.dart';
import 'package:attune/features/conflict_translator/presentation/screens/translator_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FixedNotifier extends TranslatorNotifier {
  _FixedNotifier(super.ref, TranslatorResponse response, {String? limit}) {
    state = TranslatorState(
      response: limit == null ? response : null,
      limitMessage: limit,
      isSheetOpen: true,
    );
  }
}

Future<SharedPreferences> _pump(
  WidgetTester tester,
  TranslatorResponse response, {
  ValueChanged<TranslatorRegister>? onRegisterChanged,
  String? limit,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        translatorNotifierProvider.overrideWith(
          (ref) => _FixedNotifier(ref, response, limit: limit),
        ),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: TranslatorSheet(
                    originalMessage: 'you never listen',
                    onSendOriginal: () {},
                    onSendRewrite: (_) {},
                    onEditRewrite: (_) {},
                    onRegisterChanged: onRegisterChanged,
                  ),
                ),
              ),
            ),
      ),
    ),
  );
  await tester.pump();
  return prefs;
}

const _rewrite = TranslatorResponse(
  rewrite: 'I want us to make time for my family.',
  coreNeedIdentified: 'communal_obligation',
  framingNote: 'Family matters a lot to you here.',
  rewriteConfidence: 'high',
);

void main() {
  testWidgets('choosing plain words is remembered and asks again', (
    tester,
  ) async {
    TranslatorRegister? asked;
    final prefs = await _pump(
      tester,
      _rewrite,
      onRegisterChanged: (r) => asked = r,
    );
    expect(find.text('Gentle (NVC)'), findsOneWidget);
    await tester.tap(find.text('Plain words'));
    await tester.pump();
    expect(prefs.getString('translator_register'), 'plain');
    expect(asked, TranslatorRegister.plain);
  });

  testWidgets('the seventh need reads naturally', (tester) async {
    await _pump(tester, _rewrite);
    expect(
      find.text('Underlying need: to honour family and community'),
      findsOneWidget,
    );
    expect(find.text('Family matters a lot to you here.'), findsOneWidget);
  });

  testWidgets('a writer card replaces the rewrite and its send buttons', (
    tester,
  ) async {
    await _pump(
      tester,
      TranslatorResponse.fromJson({'status': 'writer_resources'}),
    );
    expect(find.text('One way to say this'), findsNothing);
    expect(find.text('Send this'), findsNothing);
    expect(find.byKey(const Key('translator-writer-card')), findsOneWidget);
  });

  testWidgets('the daily limit shows the server\'s words, no retry', (
    tester,
  ) async {
    await _pump(tester, _rewrite, limit: 'Try again tomorrow.');
    expect(find.text('Try again tomorrow.'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(find.text('One way to say this'), findsNothing);
  });
}
