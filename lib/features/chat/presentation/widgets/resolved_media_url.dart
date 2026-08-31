import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Resolves a signed URL for chat media on demand and builds [child] once
/// ready — the fix for the "Unsupported message" flash a cached (locally
/// restored) message showed before ChatController's hydration pass had a
/// chance to re-sign its URL. [signedMediaUrl] is used immediately when
/// already present (the common case once hydration has run); otherwise
/// this fetches one itself via [signedMediaUrlProvider], keyed on
/// [mediaKey] so it reuses SupabaseChatRepository's own signed-URL cache
/// rather than re-requesting on every rebuild. Shared between MessageBubble
/// and ImageViewerScreen — both need the identical resolve-or-fetch
/// behavior for a message's media.
class ResolvedMediaUrl extends ConsumerWidget {
  const ResolvedMediaUrl({
    super.key,
    required this.signedMediaUrl,
    required this.mediaKey,
    required this.builder,
    required this.loading,
    required this.error,
  });

  final String? signedMediaUrl;
  final String? mediaKey;
  final Widget Function(BuildContext context, String url) builder;
  final Widget loading;
  final Widget error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = mediaKey;

    // The KEY wins over a stored signedMediaUrl. That URL is baked onto
    // the message at row-fetch time and its token lives 10 minutes, so a
    // chat left open — or a row restored from the disk cache — carries one
    // that has already expired. signedMediaUrlProvider goes through
    // SupabaseChatRepository's cache, which re-signs past a 60s safety
    // margin, so this is a memory hit in the common case rather than a
    // round-trip.
    //
    // The stored URL remains the fallback for a row that carries one
    // without a key.
    if (key == null) {
      return signedMediaUrl != null ? builder(context, signedMediaUrl!) : error;
    }

    final resolved = ref.watch(signedMediaUrlProvider(key));
    return resolved.when(
      data: (url) => url == null ? error : builder(context, url),
      loading: () => loading,
      error: (_, _) => error,
    );
  }
}
