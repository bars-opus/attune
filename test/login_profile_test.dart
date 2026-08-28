import 'package:attune/features/auth/log_in/presentation/screens/login_profile.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('phone CTA opens the login sheet without widget errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _TestApp(child: LoginProfile()));
    await tester.pumpAndSettle();

    final phoneButton = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Continue with phone number'),
    );
    phoneButton.onPressed!();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The EULA is deliberately NOT here: 5930082c moved acceptance to
    // once-per-user after OTP verification, because whether someone is
    // new or returning is unknowable before it. The CTA opens the login
    // sheet instead.
    expect(find.text('End User License Agreement'), findsNothing);
    expect(
      find.textContaining('browsing Attune as a guest'),
      findsOneWidget,
      reason: 'the phone CTA must open the login sheet',
    );
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // LoginScreen, opened by the phone CTA, reads providers.
    return ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder:
            (_, __) => MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(body: child),
            ),
      ),
    );
  }
}
