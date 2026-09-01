import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('conversation state alerts animate in a compact card surface', () {
    final source =
        File(
          'lib/features/chat/presentation/screens/chat_screen.dart',
        ).readAsStringSync();

    final start = source.indexOf('class _ConversationStateBanner');
    final end = source.indexOf('class _ConversationHeaderCard');
    final bannerSource = source.substring(start, end);

    expect(source, isNot(contains('_showConversationBannerPreview')));
    expect(bannerSource, contains('Could not sync'));
    expect(bannerSource, contains('Conversation archived'));
    expect(bannerSource, contains('Offline'));
    expect(bannerSource, contains('Read-only'));
    expect(bannerSource, contains('Retry'));
    expect(bannerSource, isNot(contains('Needs attention')));
    expect(bannerSource, isNot(contains('failedCount')));
    expect(bannerSource, contains('AnimatedSize'));
    expect(bannerSource, contains('AnimatedSwitcher'));
    expect(bannerSource, contains('SlideTransition'));
    expect(bannerSource, contains('SizeTransition'));
    expect(bannerSource, isNot(contains('Reconnecting')));
    expect(bannerSource, isNot(contains('LinearProgressIndicator')));
    expect(bannerSource, isNot(contains('MaterialBanner')));
  });
}
