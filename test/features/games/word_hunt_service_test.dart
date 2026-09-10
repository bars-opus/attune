import 'package:attune/features/games/word_hunt/models/word_hunt_models.dart';
import 'package:attune/features/games/word_hunt/services/word_hunt_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every Word Hunt RPC answers with a jsonb object rather than an HTTP
/// status, so "did it work" is a field. Getting this wrong in either
/// direction is silent: swallowing an error hands the UI a session with
/// no grid, and throwing on a success loses a finished result.
void main() {
  test('a plain payload passes through', () {
    final out = unwrapWordHuntResponse({
      'session_id': 's1',
      'status': 'active',
    });
    expect(out['session_id'], 's1');
  });

  test('an error object becomes a typed error, not a payload', () {
    expect(
      () => unwrapWordHuntResponse({
        'error': true,
        'code': 'FORBIDDEN',
        'message': "You don't have access to this game.",
      }),
      throwsA(
        isA<WordHuntApiError>()
            .having((e) => e.code, 'code', 'FORBIDDEN')
            .having((e) => e.message, 'message', contains('access')),
      ),
    );
  });

  test('a payload with error:false is not mistaken for an error', () {
    final out = unwrapWordHuntResponse({'error': false, 'hit': true});
    expect(out['hit'], isTrue);
  });

  test('a null response throws rather than yielding an empty session', () {
    // This is what a call to a function that does not exist looks like.
    expect(
      () => unwrapWordHuntResponse(null),
      throwsA(isA<WordHuntApiError>()),
    );
  });

  test('a scalar response throws', () {
    expect(() => unwrapWordHuntResponse(42), throwsA(isA<WordHuntApiError>()));
    expect(
      () => unwrapWordHuntResponse('ok'),
      throwsA(isA<WordHuntApiError>()),
    );
  });

  test('the thrown error is always showable, even when malformed', () {
    try {
      unwrapWordHuntResponse({'error': true});
      fail('should have thrown');
    } on WordHuntApiError catch (e) {
      expect(e.message, isNotEmpty);
      expect(e.code, 'UNKNOWN');
    }
  });
}
