// Spec 1 W6a (§4.5): start-fresh-account's answers, as DM1 reads them.
import 'package:attune/features/auth/sign_up/data/fresh_start_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Functions extends Fake implements FunctionsClient {
  _Functions(this.answer);

  final Future<FunctionResponse> Function() answer;
  final calls = <(String, Object?)>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #invoke) {
      calls.add((
        invocation.positionalArguments.first as String,
        invocation.namedArguments[#body],
      ));
      return answer();
    }
    return super.noSuchMethod(invocation);
  }
}

Future<FreshStartResult> _start(
  Future<FunctionResponse> Function() answer, [
  List<(String, Object?)>? seen,
]) {
  final functions = _Functions(answer);
  return SupabaseFreshStartGateway(
    () => functions,
  ).start('ab' * 64).whenComplete(() => seen?.addAll(functions.calls));
}

void main() {
  test(
    '200 is done; the nonce goes in the body to start-fresh-account',
    () async {
      final seen = <(String, Object?)>[];
      expect(
        await _start(
          () async => FunctionResponse(status: 200, data: {'ok': true}),
          seen,
        ),
        FreshStartResult.done,
      );
      expect(seen.single.$1, 'start-fresh-account');
      expect(seen.single.$2, {'nonce': 'ab' * 64});
    },
  );

  test('400 invalid, 429 try later, anything else unavailable', () async {
    Future<FunctionResponse> fail(int status) => Future.error(
      FunctionException(status: status, details: {'error': 'x'}),
    );
    expect(await _start(() => fail(400)), FreshStartResult.invalid);
    expect(await _start(() => fail(429)), FreshStartResult.tryLater);
    expect(await _start(() => fail(503)), FreshStartResult.unavailable);
    expect(
      await _start(() => Future.error(Exception('offline'))),
      FreshStartResult.unavailable,
    );
  });
}
