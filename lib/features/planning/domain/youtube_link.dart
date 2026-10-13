/// The video id in a YouTube link, or null when [url] is not a YouTube
/// video: `youtu.be/ID`, `watch?v=ID`, `/shorts/`, `/embed/`, `/live/`, on
/// youtube.com and its m./music./www. hosts and youtube-nocookie.com.
String? planningYouTubeId(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || (u.scheme != 'https' && u.scheme != 'http')) return null;
  final host = u.host.toLowerCase();
  bool on(String domain) => host == domain || host.endsWith('.$domain');

  String? candidate;
  if (host == 'youtu.be' || host == 'www.youtu.be') {
    candidate = u.pathSegments.isEmpty ? null : u.pathSegments.first;
  } else if (on('youtube.com') || on('youtube-nocookie.com')) {
    final segments = u.pathSegments;
    if (segments.isNotEmpty && segments.first == 'watch') {
      candidate = u.queryParameters['v'];
    } else if (segments.length >= 2 && const {'shorts', 'embed', 'live', 'v'}.contains(segments.first)) {
      candidate = segments[1];
    }
  }
  return candidate != null && _videoId.hasMatch(candidate) ? candidate : null;
}

final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
