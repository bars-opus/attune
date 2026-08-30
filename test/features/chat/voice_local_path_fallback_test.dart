import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a stale localMediaPath does not win over the uploaded copy', () {
    // localMediaPath was preferred unconditionally. That path is a cache
    // file: the OS reclaims app caches under storage pressure, and the
    // recording is cleaned up after upload. Once it is gone,
    // DeviceFileSource fails with
    //
    //   PlatformException(DarwinAudioError, ... AVPlayerItem.Status.failed
    //   on setSourceUrl: error("Failed to set playerItem"))
    //
    // even though the message uploaded fine and has a perfectly good
    // signed URL sitting beside it.
    final bubble =
        File(
          'lib/features/chat/presentation/widgets/message_bubble.dart',
        ).readAsStringSync();

    final audioBranch = bubble.substring(
      bubble.indexOf('if (message.hasAudio) {'),
      bubble.indexOf('if (message.isStreak) {'),
    );

    expect(
      audioBranch.contains('playableLocalAudioPath'),
      isTrue,
      reason:
          'the local file must be checked for existence before it is '
          'preferred over the uploaded copy',
    );
  });

  test('the ephemeral video path is existence-checked too', () {
    // Same `localMediaPath ?? signedMediaUrl` shape, same failure: a
    // reclaimed cache file shadowed the uploaded copy.
    final bubble =
        File(
          'lib/features/chat/presentation/widgets/message_bubble.dart',
        ).readAsStringSync();

    expect(
      bubble,
      isNot(contains('message.localMediaPath ?? message.signedMediaUrl')),
      reason:
          'a bare ?? prefers a path that may no longer exist over a good '
          'signed URL',
    );
  });

  test('the helper actually probes the filesystem', () {
    // A helper that just returned its argument would satisfy both checks
    // above while changing nothing.
    final bubble =
        File(
          'lib/features/chat/presentation/widgets/message_bubble.dart',
        ).readAsStringSync();

    final helper = bubble.substring(
      bubble.indexOf('String? _playableLocalPath('),
      bubble.indexOf('class MessageBubble'),
    );
    expect(helper, contains('existsSync()'));
  });
}
