// Entry gates fix round (review M-3): Planning refused by the server's
// account gate (account_not_ready / RLS 42501) leaves Planning and opens
// the onboarding gate, with copy that says what to do. Never "sign in
// again", which is what a bare 42501 used to read as.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/features/planning/presentation/planning_ui.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _refusal = PostgrestException(message: 'account_not_ready', code: '42501');

Future<GoRouter> _pump(WidgetTester t, Widget Function(BuildContext) page) async {
  final router = GoRouter(
    initialLocation: '/planning',
    routes: [
      GoRoute(
        path: '/planning',
        builder: (context, _) => Scaffold(body: Builder(builder: page)),
      ),
      GoRoute(
        path: RouteNames.onboarding,
        builder: (_, __) => const Scaffold(body: Text('GATE')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder:
          (_, __) => MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
    ),
  );
  await t.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('a refused save says to finish setting up and opens the gate', (
    t,
  ) async {
    await _pump(
      t,
      (context) => TextButton(
        onPressed: () => showPlanningError(context, _refusal),
        child: const Text('save'),
      ),
    );
    await t.tap(find.text('save'));
    await t.pump();
    expect(find.text('Finish setting up your account first.'), findsOneWidget);
    await t.pumpAndSettle();
    expect(find.text('GATE'), findsOneWidget);
  });

  testWidgets('a refused load offers "Finish setting up", which opens the '
      'gate', (t) async {
    await _pump(
      t,
      (_) => PlanningErrorState(error: _refusal, onRetry: () {}),
    );
    expect(find.text('Finish setting up your account first.'), findsOneWidget);
    expect(find.text('Please sign in again to keep planning.'), findsNothing);
    await t.tap(find.text('Finish setting up'));
    await t.pumpAndSettle();
    expect(find.text('GATE'), findsOneWidget);
  });
}
