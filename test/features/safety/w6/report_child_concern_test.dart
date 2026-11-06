// Spec 1 W6c (§3.15, §2.3): "Report a concern about a child". The words and
// an optional place go to report_child_safety_concern and nowhere else;
// "Dating" only for someone who uses it; the limit and a failure are said,
// with the words kept; the thanks after sending; goldens at 1.0, 1.3, 2.0
// and right to left.
//   flutter test --update-goldens test/features/safety/w6/report_child_concern_test.dart
import 'package:attune/core/utils/constants.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/safety/data/child_report_service.dart';
import 'package:attune/features/safety/presentation/screens/report_child_concern_screen.dart';
import 'package:attune/features/safety/presentation/screens/safety_resources_screen.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';

class _Server {
  final sent = <Map<String, dynamic>>[];
  Object? fail;

  Future<Object?> rpc(String fn, Map<String, dynamic> params) async {
    expect(fn, 'report_child_safety_concern');
    final error = fail;
    if (error != null) throw error;
    sent.add(params);
    return null;
  }
}

List<Override> _overrides(
  _Server server, {
  String path = 'just_me',
  bool enrolled = false,
}) => [
  childReportServiceProvider.overrideWithValue(ChildReportService(server.rpc)),
  homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-report'))),
  homeStateProvider.overrideWith(
    () => _Home(homeJson(path: path, datingEnrolled: enrolled)),
  ),
];

class _Home extends HomeStateNotifier {
  _Home(this.json);

  final Map<String, dynamic> json;

  @override
  HomeSnapshot build(String userId) =>
      HomeSnapshot.fromServer(HomeState.fromJson(json));
}

Future<FlowHarness> _pump(
  WidgetTester tester,
  _Server server, {
  String path = 'just_me',
  bool enrolled = false,
}) => pumpFlowScreen(
  tester,
  () => const ReportChildConcernScreen(),
  overrides: _overrides(server, path: path, enrolled: enrolled),
);

void main() {
  testWidgets('the words and the place go to the RPC; then the thanks', (
    tester,
  ) async {
    final server = _Server();
    await _pump(tester, server);
    expect(find.text('Report a concern about a child'), findsOneWidget);
    expect(
      find.textContaining('A person on our team reads every report.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('call your local emergency number'),
      findsOneWidget,
    );
    final send = find.widgetWithText(FilledButton, 'Send report');
    expect(
      tester.widget<FilledButton>(send).onPressed,
      isNull,
      reason: 'nothing to send yet',
    );
    await tapInReach(tester, find.text('Stories'));
    await tester.enterText(
      find.byType(TextField),
      '  A grown-up asked a child to message privately.  ',
    );
    await tester.pump();
    expect(find.text('50 of 2000'), findsOneWidget);
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();
    expect(server.sent.single, {
      'p_where': 'stories',
      'p_details': 'A grown-up asked a child to message privately.',
    });
    expect(find.text("Thank you. We've received your report."), findsOneWidget);
  });

  testWidgets('no place is fine', (tester) async {
    final server = _Server();
    await _pump(tester, server);
    await tester.enterText(find.byType(TextField), 'Saw it');
    await tester.pump();
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();
    expect(server.sent.single['p_where'], isNull);
  });

  testWidgets('no "Dating" on the Relationship path (D20)', (tester) async {
    await _pump(tester, _Server(), path: 'relationship');
    expect(find.text('Dating'), findsNothing);
    expect(find.text('Somewhere else'), findsOneWidget);
  });

  testWidgets('"Dating" on the Dating path', (tester) async {
    await _pump(tester, _Server(), path: 'dating');
    expect(find.text('Dating'), findsOneWidget);
  });

  testWidgets('"Dating" for someone enrolled in it', (tester) async {
    await _pump(tester, _Server(), path: 'just_me', enrolled: true);
    expect(find.text('Dating'), findsOneWidget);
  });

  testWidgets('the daily limit and a failure are said, and the words kept', (
    tester,
  ) async {
    final server =
        _Server()
          ..fail = const PostgrestException(
            message: 'child_report:limit',
            code: 'P0001',
          );
    await _pump(tester, server);
    await tester.enterText(find.byType(TextField), 'More to say');
    await tester.pump();
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        "You've sent 5 reports today. To tell us more, email ${AppConstants.childSafetyEmail}.",
      ),
      findsOneWidget,
    );
    expect(find.text('More to say'), findsOneWidget);
    server.fail = Exception('offline');
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();
    expect(
      find.text("We couldn't send this. Check your connection and try again."),
      findsOneWidget,
    );
    expect(find.text('More to say'), findsOneWidget);
  });

  testWidgets('guidelines and goldens', (tester) async {
    await _pump(tester, _Server());
    await expectFlowGuidelines(tester);
    await expectFlowGoldens(
      tester,
      'report_child_concern',
      () => const ReportChildConcernScreen(),
      overrides: _overrides(_Server()),
    );
  });
  // Fix round 1 (review I-1): the server's 2,000 is char_length, a count of
  // code points; a skin-toned emoji is one character on screen but two
  // code points. The phone counts the same way and stops before sending.
  testWidgets(
    '1001 skin-toned thumbs are too long: blocked on the phone, said',
    (tester) async {
      final server = _Server();
      await _pump(tester, server);
      const thumb = '\u{1F44D}\u{1F3FD}';
      await tester.enterText(find.byType(TextField), thumb * 1001);
      await tester.pump();
      expect(find.text('2002 of 2000'), findsOneWidget);
      expect(
        find.text('This is too long. Keep it to 2,000 characters or fewer.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Send report'),
            )
            .onPressed,
        isNull,
        reason: 'the server would refuse 2002 code points',
      );
      await tester.enterText(find.byType(TextField), thumb * 1000);
      await tester.pump();
      expect(find.text('2000 of 2000'), findsOneWidget);
      expect(
        find.text('This is too long. Keep it to 2,000 characters or fewer.'),
        findsNothing,
      );
      await tester.tap(find.text('Send report'));
      await tester.pumpAndSettle();
      expect((server.sent.single['p_details'] as String).runes.length, 2000);
    },
  );

  test(
    'the server refusing the words is never read as a connection failure',
    () async {
      final service = ChildReportService(
        (fn, params) async =>
            throw const PostgrestException(
              message: 'child_report:invalid',
              code: 'P0001',
            ),
      );
      expect(
        await service.send(place: null, details: 'words'),
        isNot(ChildReportOutcome.failed),
      );
    },
  );

  testWidgets('a server "invalid" says its own words, and keeps the report', (
    tester,
  ) async {
    final server =
        _Server()
          ..fail = const PostgrestException(
            message: 'child_report:invalid',
            code: 'P0001',
          );
    await _pump(tester, server);
    await tester.enterText(find.byType(TextField), 'Some words');
    await tester.pump();
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();
    expect(
      find.text("We couldn't send this. Check your connection and try again."),
      findsNothing,
    );
    expect(
      find.text(
        "We couldn't send this as written. Make it shorter and try again, or email ${AppConstants.childSafetyEmail}.",
      ),
      findsOneWidget,
    );
    expect(find.text('Some words'), findsOneWidget);
  });

  // Fix round 1 (review M-6): the next person on a shared phone never sees
  // the keyboard suggest words from a report.
  testWidgets('the keyboard learns nothing from the report', (tester) async {
    await _pump(tester, _Server());
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enableSuggestions, isFalse);
    expect(field.autocorrect, isFalse);
    expect(field.enableIMEPersonalizedLearning, isFalse);
  });

  // Fix round 1 (review M-7): the address in the limit message opens the
  // mail app (UrlLauncherUtils).
  testWidgets('after the limit, the address opens the mail app', (
    tester,
  ) async {
    final launched = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    messenger.setMockMethodCallHandler(channel, (call) async {
      final url = (call.arguments as Map)['url'] as String;
      if (call.method == 'launch') launched.add(url);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final server =
        _Server()
          ..fail = const PostgrestException(
            message: 'child_report:limit',
            code: 'P0001',
          );
    await _pump(tester, server);
    await tester.enterText(find.byType(TextField), 'More to say');
    await tester.pump();
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();
    final link = find.widgetWithText(TextButton, AppConstants.childSafetyEmail);
    expect(link, findsOneWidget);
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();
    // UrlLauncherUtils.launchEmail writes `mailto:<address>` (with an empty
    // query when there's no subject).
    final uri = Uri.parse(launched.single);
    expect(uri.scheme, 'mailto');
    expect(uri.path, AppConstants.childSafetyEmail);
  });

  // Fix round 1 (review M-4, P-28): §3.15 "also linked from the Support
  // screen", which §5.4 names as Support resources.
  testWidgets('Support resources links to the report, signed in only', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      () => const Scaffold(body: ReportChildConcernLink()),
      overrides: _overrides(_Server()),
    );
    expect(find.text('Report a concern about a child'), findsOneWidget);
    expect(SafetyResourcesScreen.routeName, '/safety-resources');
    final source =
        File(
          'lib/features/safety/presentation/screens/safety_resources_screen.dart',
        ).readAsStringSync();
    expect(source, contains('const ReportChildConcernLink()'));
  });

  testWidgets('no link to the report when signed out', (tester) async {
    await pumpFlowScreen(
      tester,
      () => const Scaffold(body: ReportChildConcernLink()),
      overrides: [homeAuthProvider.overrideWithValue(FakeHomeAuth(null))],
    );
    expect(find.text('Report a concern about a child'), findsNothing);
  });
}
