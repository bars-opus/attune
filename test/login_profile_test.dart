import 'package:attune/features/auth/log_in/presentation/screens/login_profile.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('phone CTA opens legal sheet without widget errors', (
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
    expect(find.text('End User License Agreement'), findsOneWidget);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      builder:
          (_, __) => MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: child),
          ),
    );
  }
}
