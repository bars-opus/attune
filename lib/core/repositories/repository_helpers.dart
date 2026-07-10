import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

/// Thrown by repository methods on failure.
///
/// Carries a [userMessage] safe to surface in the UI (no schema, paths, or
/// internal IDs) plus the original [cause] / [stackTrace] for logs.
class RepositoryException implements Exception {
  final String userMessage;
  final Object? cause;
  final StackTrace? stackTrace;

  RepositoryException(this.userMessage, {this.cause, this.stackTrace});

  @override
  String toString() => userMessage;
}

/// Default per-call timeout for Supabase queries.
const Duration kRepoQueryTimeout = Duration(seconds: 10);

/// Wraps a repository operation with timeout, retry on transient errors,
/// structured logging, and conversion to [RepositoryException] on failure.
///
/// - [op]: the network call to execute.
/// - [opName]: short identifier for logs (e.g. "getShops").
/// - [userMessage]: what to show the user if all attempts fail.
/// - [timeout]: per-attempt timeout. Defaults to [kRepoQueryTimeout].
/// - [maxAttempts]: total attempts including the first. 1 = no retry.
Future<T> runRepoQuery<T>(
  Future<T> Function() op, {
  required String opName,
  required String userMessage,
  Duration timeout = kRepoQueryTimeout,
  int maxAttempts = 3,
}) async {
  Object? lastError;
  StackTrace? lastStack;

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      return await op().timeout(timeout);
    } catch (e, stack) {
      lastError = e;
      lastStack = stack;

      final retryable = _isRetryable(e);
      final lastAttempt = attempt == maxAttempts - 1;

      developer.log(
        '[$opName] attempt ${attempt + 1}/$maxAttempts failed '
        '(retryable=$retryable): ${e.runtimeType}',
        name: 'repository',
        error: e,
        stackTrace: stack,
      );

      if (!retryable || lastAttempt) break;

      // Exponential backoff with jitter: 250ms, 500ms, 1s ± 25%.
      final base = 250 * pow(2, attempt).toInt();
      final jitter = (base * 0.25 * Random().nextDouble()).toInt();
      await Future.delayed(Duration(milliseconds: base + jitter));
    }
  }

  throw RepositoryException(
    userMessage,
    cause: lastError,
    stackTrace: lastStack,
  );
}

/// Classifies an error as worth retrying. Network blips and 5xx errors are
/// retryable; auth, validation, and other 4xx errors are not.
bool _isRetryable(Object error) {
  if (error is TimeoutException) return true;

  // Supabase / PostgREST errors carry HTTP-ish status codes in `code`.
  // Treat 5xx and network-level failures as transient.
  final msg = error.toString().toLowerCase();
  if (msg.contains('socketexception') ||
      msg.contains('handshakeexception') ||
      msg.contains('connection') ||
      msg.contains('timed out')) {
    return true;
  }

  // PostgrestException with statusCode property.
  try {
    final dyn = error as dynamic;
    final status = dyn.statusCode;
    if (status is int && status >= 500 && status < 600) return true;
  } catch (_) {
    // Not a PostgrestException — fall through.
  }

  return false;
}
