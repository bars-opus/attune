import 'package:attune/app/app.dart' show appLocalizationsDelegates;
import 'package:attune/core/widgets/feedback/empty_state.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/chat/support/chat_test_harness.dart' show withScreenUtil;

Widget _app(EmptyStateType type, {Locale locale = const Locale('en')}) => withScreenUtil(MaterialApp(
      locale: locale,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: EmptyStateWidget(type: type, onAction: () {})),
    ));

void main() {
  test("only Attune's kinds of empty state remain (no shops, workers or favourites)", () {
    expect(EmptyStateType.values,
        [EmptyStateType.noData, EmptyStateType.noResults, EmptyStateType.noInternet, EmptyStateType.noMessages, EmptyStateType.custom]);
  });

  for (final (type, title, subtitle, action) in [
    (EmptyStateType.noData, 'Nothing here yet', "When there's something to show, it'll appear here.", 'Refresh'),
    (EmptyStateType.noResults, 'No matches', 'Try a different word or filter.', 'Clear filters'),
    (EmptyStateType.noInternet, "You're offline", 'Check your connection and try again.', 'Try again'),
    (EmptyStateType.noMessages, 'No messages yet', 'Say hello to start your conversation.', 'Say hello'),
  ]) {
    testWidgets('$type reads in Attune\'s voice', (tester) async {
      await tester.pumpWidget(_app(type));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(find.text(subtitle), findsOneWidget);
      expect(find.text(action), findsOneWidget);
    });
  }

  testWidgets('the new wording is translated too, not left to English', (tester) async {
    await tester.pumpWidget(_app(EmptyStateType.noData, locale: const Locale('de')));
    await tester.pumpAndSettle();
    expect(find.text('Noch nichts hier'), findsOneWidget);
  });
}
