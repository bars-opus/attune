// The screens on a 13" iPad: content in a centred column (lists 960, forms
// and onboarding 600, sheets 640) with the background still filling the
// screen; on a phone each is exactly as before.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/features/auth/intro/intro_screen.dart';
import 'package:attune/features/auth/log_in/presentation/screens/login_profile.dart';
import 'package:attune/features/settings/screens/settings_screen.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phone = Size(375, 812);
const _iPad = Size(1032, 1376);

Future<void> _pump(WidgetTester t, Size size, Widget home) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await t.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: ScreenUtilConfig.builder(
        builder:
            (_) => MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: home,
            ),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  group('Settings', () {
    testWidgets('cards sit 52pt in from the edges of an iPad, like Health', (
      t,
    ) async {
      await _pump(t, _iPad, const SettingsScreen(currentUserId: 'me'));
      final card = t.getRect(find.byType(CardInkWell).first);
      expect(card.left, 52);
      expect(card.right, 1032 - 52);
    });

    testWidgets('on a phone the cards are where they were', (t) async {
      await _pump(t, _phone, const SettingsScreen(currentUserId: 'me'));
      final card = t.getRect(find.byType(CardInkWell).first);
      expect(card.left, Spacing.md);
      expect(card.right, 375 - Spacing.md);
    });
  });

  group('the guest landing', () {
    testWidgets('sits in a 600pt column, buttons included', (t) async {
      await _pump(t, _iPad, const Scaffold(body: LoginProfile()));
      final button = t.getRect(
        find.widgetWithText(AppButton, 'Continue with phone number'),
      );
      expect(button.width, lessThanOrEqualTo(ContentWidth.form));
      expect(button.center.dx, closeTo(1032 / 2, 0.5));
    });

    testWidgets('talks about Attune, not a shop', (t) async {
      await _pump(t, _phone, const Scaffold(body: LoginProfile()));
      final overview = find.textContaining('browsing Attune as a guest');
      expect(overview, findsOneWidget);
      final text = t.widget<Text>(overview).data!;
      expect(text, isNot(contains('shop')));
      expect(text, isNot(contains('business')));
      expect(text, contains('partner'));
    });
  });

  testWidgets('the welcome screen sits in a 600pt column on its green', (
    t,
  ) async {
    await _pump(t, _iPad, const IntroScreen());
    final carousel = t.getRect(
      find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.horizontal,
      ),
    );
    expect(carousel.width, lessThanOrEqualTo(ContentWidth.form));
    expect(carousel.center.dx, closeTo(1032 / 2, 0.5));
    expect(
      t.getSize(find.byType(Scaffold)).width,
      1032,
      reason: 'the green still fills the screen',
    );
  });

  Future<Rect> openSheet(WidgetTester t, Size size) async {
    await _pump(
      t,
      size,
      Builder(
        builder:
            (context) => Scaffold(
              body: TextButton(
                onPressed:
                    () => BottomSheetUtils.showDocumentationBottomSheet(
                      context: context,
                      widget: const SizedBox(
                        key: ValueKey('sheet-body'),
                        height: 100,
                      ),
                    ),
                child: const Text('open'),
              ),
            ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pump(const Duration(milliseconds: 600));
    return t.getRect(find.byType(DraggableScrollableSheet));
  }

  testWidgets(
    'a sheet is at most 640pt wide on an iPad, as Material sheets are',
    (t) async {
      final sheet = await openSheet(t, _iPad);
      expect(sheet.width, ContentWidth.sheet);
      expect(sheet.center.dx, closeTo(1032 / 2, 0.5));
    },
  );

  testWidgets('a phone on its side keeps full-width sheets, as before', (
    t,
  ) async {
    final sheet = await openSheet(t, const Size(932, 430));
    expect(sheet.width, 932);
  });
}
