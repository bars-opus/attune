// test/features/pulse/pulse_refresh_copy_test.dart
import 'package:attune/features/pulse/domain/pulse_refresh_copy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

void main() {
  test('a 429 with a retry time is worded in hours', () {
    expect(
      pulseRefreshMessage(
        const FunctionException(
          status: 429,
          details: {'retry_after_seconds': 7200},
        ),
      ),
      'You can refresh again in about 2 hours.',
    );
    expect(
      pulseRefreshMessage(
        const FunctionException(
          status: 429,
          details: {'retry_after_seconds': 7201},
        ),
      ),
      'You can refresh again in about 3 hours.',
    );
  });

  test('under an hour says so', () {
    expect(
      pulseRefreshMessage(
        const FunctionException(
          status: 429,
          details: {'retry_after_seconds': 1800},
        ),
      ),
      'You can refresh again in under an hour.',
    );
  });

  test('a 429 without details assumes the full day', () {
    expect(
      pulseRefreshMessage(const FunctionException(status: 429)),
      'You can refresh again in about 24 hours.',
    );
  });

  test('anything else is a plain retry line, never the raw error', () {
    expect(
      pulseRefreshMessage(
        const FunctionException(status: 500, details: 'boom'),
      ),
      "Couldn't refresh Pulse. Try again.",
    );
    expect(
      pulseRefreshMessage(Exception('x')),
      "Couldn't refresh Pulse. Try again.",
    );
  });
}
