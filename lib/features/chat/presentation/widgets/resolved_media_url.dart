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
    if (signedMediaUrl != null) {
      return builder(context, signedMediaUrl!);
    }
    final key = mediaKey;
    if (key == null) return error;

    final resolved = ref.watch(signedMediaUrlProvider(key));
    return resolved.when(
      data: (url) => url == null ? error : builder(context, url),
      loading: () => loading,
      error: (_, _) => error,
    );
  }
}
