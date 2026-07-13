import 'dart:async';
import 'dart:io';

import 'package:attune/core/widgets/feedback/error_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('classifyErrorState', () {
    test('network failures map to networkError', () {
      expect(
        classifyErrorState(TimeoutException('slow')),
        ErrorStateType.networkError,
      );
      expect(
        classifyErrorState(const SocketException('no route')),
        ErrorStateType.networkError,
      );
      // Untyped errors are classified by text as a last resort.
      expect(
        classifyErrorState('Connection closed'),
        ErrorStateType.networkError,
      );
    });

    test('auth failures map to permissionError', () {
      expect(
        classifyErrorState(const AuthException('bad jwt')),
        ErrorStateType.permissionError,
      );
    });

    test('postgrest RLS denial maps to permissionError', () {
      expect(
        classifyErrorState(
          const PostgrestException(message: 'denied', code: '42501'),
        ),
        ErrorStateType.permissionError,
      );
      expect(
        classifyErrorState(
          const PostgrestException(message: 'jwt', code: 'PGRST301'),
        ),
        ErrorStateType.permissionError,
      );
    });

    test('postgrest constraint/data errors map to clientError', () {
      expect(
        classifyErrorState(
          const PostgrestException(message: 'bad value', code: '22023'),
        ),
        ErrorStateType.clientError,
      );
      expect(
        classifyErrorState(
          const PostgrestException(message: 'unique', code: '23505'),
        ),
        ErrorStateType.clientError,
      );
    });

    test('other postgrest failures map to serverError', () {
      expect(
        classifyErrorState(
          const PostgrestException(message: 'boom', code: 'PGRST205'),
        ),
        // PGRST2xx (e.g. missing table) is our backend being wrong, not the user.
        ErrorStateType.serverError,
      );
    });

    test('unknown errors fall back to genericError', () {
      expect(classifyErrorState(Exception('???')), ErrorStateType.genericError);
      expect(classifyErrorState(null), ErrorStateType.genericError);
    });
  });

  testWidgets('ErrorStateWidget.from never renders the raw exception text', (
    tester,
  ) async {
    // A Postgrest error stringifies to internal table/SQL detail — exactly what
    // must never reach a user's screen.
    final leaky = const PostgrestException(
      message: 'relation "public.secret_table" does not exist',
      code: 'PGRST205',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => Scaffold(body: ErrorStateWidget.from(leaky)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The internal detail must NOT be rendered: the collapsed "Show details"
    // panel keeps it off-screen in debug, and it is omitted entirely in
    // release. This is the property that matters — a Postgrest error
    // stringifies to internal table names and SQL detail.
    expect(find.textContaining('secret_table'), findsNothing);
    expect(find.textContaining('does not exist'), findsNothing);

    // ...and the user still gets a friendly, actionable state instead.
    expect(find.byType(ErrorStateWidget), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
  });
}
