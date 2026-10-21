import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/config/chat_config.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// A download the cache refused to keep: not chat media, cut short, too
/// big, stalled, or its message went away while it downloaded. The caller
/// falls back to streaming the URL.
class ChatMediaRejected implements Exception {
  const ChatMediaRejected(this.reason);
  final String reason;

  @override
  String toString() => 'ChatMediaRejected: $reason';
}

/// The HTTP fetch behind ChatMediaCache, checked BEFORE the cache commits
/// anything. flutter_cache_manager writes a download to a fresh file name
/// and records it in its database only once every byte arrived, so the
/// database row is the atomic commit; this service makes sure what reaches
/// that commit is real chat media, whole, and that a dead link fails:
/// - no response within [timeout], or a body that goes quiet for
///   [timeout], ends in an error (a tunnel or a lift never resets the
///   connection; without this the download — and everyone waiting on it,
///   since the cache manager shares one download per key — waited forever);
/// - any status but 200 is handed back for the cache manager to raise
///   (it writes nothing for those; an expired token's 400/403 is then
///   re-signed by ChatMediaCache.fetch), except 202/304, which it would
///   treat as success — refused here;
/// - a 200 that is not audio/video (a captive portal's HTML, a JSON error
///   body) is refused unread;
/// - a body larger than [maxBytes], empty, or shorter/longer than its
///   Content-Length ends in an error, so the cache manager never records it.
class ChatMediaFileService extends FileService {
  ChatMediaFileService({
    http.Client? client,
    this.maxBytes = defaultMaxBytes,
    Duration? timeout,
  }) : _client = client ?? http.Client(),
       timeout = timeout ?? const ChatConfig().networkTimeout;

  /// Comfortably above any chat media (videos are capped well below this).
  static const int defaultMaxBytes = 64 * 1024 * 1024;

  final http.Client _client;
  final int maxBytes;

  /// The longest wait for the response headers, and the longest silence
  /// while the body arrives (a slow but moving download is never cut).
  final Duration timeout;

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    if (headers != null) request.headers.addAll(headers);
    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(timeout);
    } on TimeoutException {
      throw ChatMediaRejected('no response within ${timeout.inSeconds} s');
    }
    final status = response.statusCode;
    final type =
        response.headers['content-type']?.split(';').first.trim().toLowerCase();

    if (status != HttpStatus.ok) {
      unawaited(_drain(response));
      if (status == HttpStatus.accepted || status == HttpStatus.notModified) {
        throw ChatMediaRejected('unexpected status $status');
      }
      return _CheckedResponse(
        statusCode: status,
        content: const Stream<List<int>>.empty(),
        contentLength: 0,
        fileExtension: '',
        validTill: DateTime.now(),
      );
    }
    if (!_isMediaType(type)) {
      unawaited(_drain(response));
      throw ChatMediaRejected('not chat media ($type)');
    }
    final expected = response.contentLength;
    if (expected != null && (expected <= 0 || expected > maxBytes)) {
      unawaited(_drain(response));
      throw ChatMediaRejected('unexpected size $expected');
    }

    var received = 0;
    var failed = false;
    final checked = response.stream
        .timeout(
          timeout,
          onTimeout: (sink) {
            sink.addError(const ChatMediaRejected('stalled'));
            sink.close();
          },
        )
        .transform(
          StreamTransformer<List<int>, List<int>>.fromHandlers(
            handleData: (chunk, sink) {
              if (failed) return;
              received += chunk.length;
              if (received > maxBytes) {
                failed = true;
                sink.addError(
                  const ChatMediaRejected('larger than chat media'),
                );
                return;
              }
              sink.add(chunk);
            },
            handleError: (error, stack, sink) {
              failed = true;
              sink.addError(error, stack);
            },
            handleDone: (sink) {
              if (!failed &&
                  (received == 0 ||
                      (expected != null && received != expected))) {
                sink.addError(
                  ChatMediaRejected(
                    'incomplete ($received of $expected bytes)',
                  ),
                );
              }
              sink.close();
            },
          ),
        );

    return _CheckedResponse(
      statusCode: status,
      content: checked,
      contentLength: expected,
      fileExtension: _extensionFor(url, type),
      eTag: response.headers['etag'],
      // A storage key's bytes never change; ChatMediaCache reads entries
      // regardless of this, and evicts by age/count/bytes instead.
      validTill: DateTime.now().add(const Duration(days: 180)),
    );
  }

  static bool _isMediaType(String? type) =>
      type == null ||
      type.isEmpty ||
      type.startsWith('audio/') ||
      type.startsWith('video/') ||
      type == 'application/octet-stream' ||
      type == 'binary/octet-stream';

  /// The storage key's own extension ('.m4a', '.mp4'): AVPlayer and
  /// ExoPlayer pick a local file's decoder from it.
  static String _extensionFor(String url, String? type) {
    final fromPath = p.extension(Uri.parse(url).path).toLowerCase();
    if (RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(fromPath)) return fromPath;
    return switch (type) {
      'audio/mp4' || 'audio/m4a' || 'audio/x-m4a' => '.m4a',
      'audio/aac' => '.aac',
      'audio/mpeg' => '.mp3',
      'video/mp4' => '.mp4',
      'video/quicktime' => '.mov',
      _ => '',
    };
  }

  static Future<void> _drain(http.StreamedResponse response) async {
    try {
      await response.stream.drain<void>().timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}

class _CheckedResponse implements FileServiceResponse {
  _CheckedResponse({
    required this.statusCode,
    required this.content,
    required this.contentLength,
    required this.fileExtension,
    required this.validTill,
    this.eTag,
  });

  @override
  final int statusCode;
  @override
  final Stream<List<int>> content;
  @override
  final int? contentLength;
  @override
  final String fileExtension;
  @override
  final DateTime validTill;
  @override
  final String? eTag;
}
