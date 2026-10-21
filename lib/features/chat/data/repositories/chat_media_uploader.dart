import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attune/features/chat/utils/chat_error.dart'
    show ChatImageRejectedSignal;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException;

/// How long an upload may go without the socket taking a byte, and how long
/// the server may take to answer once the body is sent. Matches
/// ChatConfig.networkTimeout, the bound every other chat request uses.
const chatUploadStallTimeout = Duration(seconds: 20);

/// How long the server may take to answer once the last chunk is handed to
/// the socket. Longer than [chatUploadStallTimeout]: the OS send buffer
/// still has to drain on a slow uplink and Storage then writes a file of up
/// to 25 MB; too short a bound turns a slow link into an endless loop of
/// timeouts restarting from byte 0 (timeouts are retried without a cap).
const chatUploadResponseTimeout = Duration(seconds: 60);

/// The rejection code for a local media file that is missing or unreadable
/// at upload (the preparers use the same code before upload).
const chatMediaMissingCode = 'media_missing';

/// Lets the person stop an upload. Cancelling closes the HTTP client, which
/// aborts the in-flight request.
class ChatUploadCancelToken {
  bool _cancelled = false;
  final List<VoidCallback> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  void onCancel(VoidCallback listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void _removeListener(VoidCallback listener) => _listeners.remove(listener);

  @visibleForTesting
  int get debugListenerCount => _listeners.length;
}

/// [work], or [ChatUploadCancelled] the moment [token] is cancelled —
/// whichever comes first. For the steps before the request exists (the
/// session refresh, the upload-intent RPC), which no client close can
/// abort: a tap on the ring settles at once instead of when they return.
/// The abandoned [work]'s late result or error is absorbed.
Future<T> raceUploadCancel<T>(Future<T> work, ChatUploadCancelToken? token) {
  if (token == null) return work;
  if (token.isCancelled) {
    work.ignore();
    return Future<T>.error(const ChatUploadCancelled());
  }
  final result = Completer<T>();
  void onCancelled() {
    if (!result.isCompleted) result.completeError(const ChatUploadCancelled());
  }

  token.onCancel(onCancelled);
  work.then(
    (value) {
      if (!result.isCompleted) result.complete(value);
    },
    onError: (Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    },
  );
  return result.future.whenComplete(() => token._removeListener(onCancelled));
}

class ChatUploadCancelled implements Exception {
  const ChatUploadCancelled();
  @override
  String toString() => 'ChatUploadCancelled';
}

/// Streams a file to Supabase Storage with byte progress, cancel, and stall
/// bounds.
///
/// storage_client 2.5.5 reads the whole file into memory and offers neither
/// progress nor an abort (its StorageRetryController only skips retries), so
/// a 25 MB video showed an indeterminate spinner with a stop glyph that did
/// nothing (chat review #25). This sends the same request the SDK sends —
/// POST /object/{bucket}/{key} with the SDK's own headers — as a raw
/// streamed body. Failures are raised as [StorageException] with the HTTP
/// status so ChatError classifies them like SDK failures; a dropped socket
/// stays an [http.ClientException] and a stall a [TimeoutException], both
/// offline-class (retried without a cap).
///
/// The body is pulled from disk as the socket accepts it (the file stream
/// honours backpressure), so progress counts bytes handed to the socket,
/// not bytes buffered in memory, and nothing larger than a read chunk is
/// held. A retry restarts from byte 0 (no resumable uploads; media is
/// capped at 25 MB).
class ChatMediaUploader {
  ChatMediaUploader({
    required String Function() storageUrl,
    required Future<Map<String, String>> Function() headers,
    http.Client Function()? clientFactory,
    this.idleTimeout = chatUploadStallTimeout,
    this.responseTimeout = chatUploadResponseTimeout,
  }) : _storageUrl = storageUrl,
       _headers = headers,
       _clientFactory = clientFactory ?? http.Client.new;

  final String Function() _storageUrl;

  /// apikey + the person's CURRENT bearer. Async because the repository may
  /// refresh an expired session first (the SDK's AuthHttpClient does the
  /// same for every request it sends; this uploader bypasses it).
  final Future<Map<String, String>> Function() _headers;
  final http.Client Function() _clientFactory;

  /// Longest the body may go without the socket taking a byte; also bounds
  /// the headers step (an expired session's refresh).
  final Duration idleTimeout;

  /// Longest the server may take to answer once the whole body is sent.
  final Duration responseTimeout;

  Future<void> upload({
    required String bucket,
    required String objectKey,
    required String localPath,
    required String mimeType,
    void Function(int sent, int total)? onProgress,
    ChatUploadCancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) throw const ChatUploadCancelled();
    final file = File(localPath);
    final int total;
    try {
      total = await file.length();
    } on FileSystemException {
      // The prepared file is gone (the 7-day sweep, cleared app storage) or
      // unreadable (M8): no retry can bring it back, so the send fails at
      // once with the media copy instead of five "unknown" attempts.
      throw const ChatImageRejectedSignal(chatMediaMissingCode);
    }
    // Before any client or listener exists, so a bad URL leaks neither.
    final url = Uri.parse('${_storageUrl()}/object/$bucket/$objectKey');
    // The session refresh behind the headers is a network call too: bounded
    // and cancellable like the body.
    final headers = await raceUploadCancel(
      _headers().timeout(idleTimeout),
      cancelToken,
    );
    if (cancelToken?.isCancelled == true) throw const ChatUploadCancelled();

    final client = _clientFactory();
    var settled = false;
    Timer? stall;
    final aborted = Completer<Never>();
    void abort(Object reason) {
      if (settled || aborted.isCompleted) return;
      stall?.cancel();
      aborted.completeError(reason);
      client.close();
    }

    void arm(Duration bound, String phase) {
      if (settled) return;
      stall?.cancel();
      stall = Timer(
        bound,
        () => abort(TimeoutException('upload stalled ($phase)', bound)),
      );
    }

    void onCancelled() => abort(const ChatUploadCancelled());
    cancelToken?.onCancel(onCancelled);

    final request = _FileUploadRequest(
      url,
      _body(
        file,
        total,
        onChunk: (sent) {
          arm(idleTimeout, 'body');
          onProgress?.call(sent, total);
        },
        onDone: () => arm(responseTimeout, 'response'),
        cancelToken: cancelToken,
      ),
    )
      ..headers.addAll(headers)
      ..headers['content-type'] = mimeType
      ..headers['x-upsert'] = 'false'
      ..headers['cache-control'] = 'max-age=3600'
      ..contentLength = total;

    arm(idleTimeout, 'body');
    try {
      await Future.any<void>([_exchange(client, request), aborted.future]);
    } on http.ClientException {
      if (cancelToken?.isCancelled == true) throw const ChatUploadCancelled();
      rethrow;
    } finally {
      settled = true;
      stall?.cancel();
      cancelToken?._removeListener(onCancelled);
      client.close();
    }
    if (cancelToken?.isCancelled == true) throw const ChatUploadCancelled();
  }

  Future<void> _exchange(http.Client client, http.BaseRequest request) async {
    final response = await client.send(request);
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw storageExceptionFor(response.statusCode, body);
    }
  }

  /// The failure as storage_client 2.5.5 builds it (fetch.dart
  /// `_handleError`): the JSON body decoded through
  /// [StorageException.fromJson], whose `statusCode` wins over the HTTP
  /// status — Storage answers many refusals (RLS 403, duplicate 409, size
  /// 413) as HTTP 400 with the real code only in the body, and ChatError
  /// classifies by that code. A body that is not a JSON object keeps the
  /// raw text and the HTTP status.
  @visibleForTesting
  static StorageException storageExceptionFor(int status, String body) {
    try {
      final data = json.decode(body);
      if (data is Map<String, dynamic>) {
        return StorageException.fromJson(data, '$status');
      }
    } on FormatException {
      // Not JSON: fall through to the raw body.
    }
    return StorageException(
      body.isEmpty ? 'upload failed' : body,
      statusCode: '$status',
    );
  }

  /// The file, chunk by chunk, as the consumer pulls it. Stops early once
  /// cancelled (the abort itself is the client close).
  static Stream<List<int>> _body(
    File file,
    int total, {
    required void Function(int sent) onChunk,
    required void Function() onDone,
    ChatUploadCancelToken? cancelToken,
  }) async* {
    var sent = 0;
    try {
      await for (final chunk in file.openRead()) {
        if (cancelToken?.isCancelled == true) return;
        yield chunk;
        sent += chunk.length;
        onChunk(sent);
      }
    } on FileSystemException {
      // Removed or unreadable between the length check and the read (M8).
      throw const ChatImageRejectedSignal(chatMediaMissingCode);
    }
    onDone();
  }
}

/// A request whose body is a stream supplied up front (StreamedRequest
/// pushes into a sink that buffers without backpressure).
class _FileUploadRequest extends http.BaseRequest {
  _FileUploadRequest(Uri url, this._bodyStream) : super('POST', url);

  final Stream<List<int>> _bodyStream;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_bodyStream);
  }
}
