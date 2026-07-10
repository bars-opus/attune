import 'package:attune/features/auth/presentation/passwordless_auth_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows local configuration guidance when Supabase is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder:
            (_, __) => MaterialApp(
              home: Scaffold(body: PasswordlessAuthStep(onVerified: () {})),
            ),
      ),
    );

    expect(find.text('Verify one contact method'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsNothing);
    expect(find.text('Continue with Google'), findsNothing);
    expect(find.textContaining('Supabase is not configured'), findsOneWidget);
  });
}
