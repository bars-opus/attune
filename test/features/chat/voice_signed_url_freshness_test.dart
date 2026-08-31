import 'dart:io';

import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/resolved_media_url.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  test('playback re-signs rather than trusting a stored URL', () {
    // signedMediaUrl is baked onto the message when its row is fetched,
    // and the token lives 10 minutes. The resolver returned it
    // unconditionally, so opening a chat, waiting, then pressing play
    // handed AVPlayer an expired URL:
    //
    //   AVPlayerItem.Status.failed on setSourceUrl:
    //   error("Failed to set playerItem")
    //
    // Worse for a cached row, whose stored URL can be arbitrarily old.
    //
    // createSignedMediaUrl already caches with a 60s safety margin and
    // re-signs past it, so going through it is both correct and cheap.
    final bubble =
        File(
          'lib/features/chat/presentation/widgets/message_bubble.dart',
        ).readAsStringSync();

    final resolver = bubble.substring(
      bubble.indexOf('resolveAudioUrl: () async {'),
      bubble.indexOf('},', bubble.indexOf('resolveAudioUrl: () async {')),
    );

    expect(
      resolver.contains('if (signedUrl != null) return signedUrl;'),
      isFalse,
      reason:
          'a stored signed URL may already have expired; the media key must '
          'be re-signed instead',
    );
    expect(
      resolver,
      contains('signedMediaUrlProvider'),
      reason: 'playback resolves through the caching re-signer',
    );
  });

  testWidgets('ResolvedMediaUrl re-signs from the key, ignoring a stale URL', (
    tester,
  ) async {
    // The stored URL and the freshly signed one are given DIFFERENT values,
    // so a widget that trusts the stored one is distinguishable from one
    // that re-signs. With both returning the same string, the two are
    // indistinguishable and the assertion proves nothing.
    final repo = FakeChatRepository(currentUserId: 'u1')..signMediaUrls = true;
    String? built;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: ResolvedMediaUrl(
            signedMediaUrl: 'https://stale.example/expired-token',
            mediaKey: 'chat-media/fresh.jpg',
            builder: (context, url) {
              built = url;
              return const SizedBox();
            },
            loading: const SizedBox(),
            error: const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      built,
      'https://signed.test/chat-media/fresh.jpg?token=abc',
      reason:
          'built with "\$built" — a stored URL whose token has expired must '
          'not win over the media key',
    );
  });
}
