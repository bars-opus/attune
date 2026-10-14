import 'package:attune/features/together/data/together_ai_repository.dart';
import 'package:attune/features/together/domain/together_ai.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAiGateway implements TogetherAiGateway {
  FakeAiGateway({this.response, this.error, this.status});
  final Object? response;
  final TogetherAiException? error;
  final Map<String, dynamic>? status;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<dynamic> invoke(String fn, Map<String, dynamic> body) async {
    bodies.add(body);
    if (error != null) throw error!;
    return response;
  }

  @override
  Future<dynamic> rpc(String fn, Map<String, dynamic> params) async =>
      status ?? {'available': false, 'partner_name': ''};
}

void main() {
  test(
    'capture sends the note and my local now; the draft reads back local',
    () async {
      final g = FakeAiGateway(
        response: {
          'draft': {
            'title': 'Dinner',
            'all_day': false,
            'start_local': '2026-11-07T19:00',
            'end_local': '2026-11-07T21:00',
            'with_partner': true,
            'location': 'Osu',
            'note': null,
          },
        },
      );
      final d = await TogetherAiRepository(
        g,
      ).capture('r1', 'dinner Sat 7pm', DateTime(2026, 11, 2, 9, 5));
      expect(g.bodies.single['action'], 'capture');
      expect(g.bodies.single['now_local'], '2026-11-02T09:05');
      expect(g.bodies.single['text'], 'dinner Sat 7pm');
      expect(
        RegExp(
          r'^[0-9a-f-]{36}$',
        ).hasMatch(g.bodies.single['request_id'] as String),
        isTrue,
      );
      expect(
        [d.title, d.start, d.end, d.withPartner, d.location],
        [
          'Dinner',
          DateTime(2026, 11, 7, 19),
          DateTime(2026, 11, 7, 21),
          true,
          'Osu',
        ],
      );
    },
  );

  test('ideas send the window in local time and read three ideas', () async {
    final g = FakeAiGateway(
      response: {
        'ideas': [
          for (var i = 1; i <= 3; i++) {'title': 'Idea $i', 'blurb': 'Line.'},
        ],
      },
    );
    final ideas = await TogetherAiRepository(
      g,
    ).ideas('r1', DateTime(2026, 11, 5, 19), DateTime(2026, 11, 5, 22));
    expect(g.bodies.single['window_start_local'], '2026-11-05T19:00');
    expect(g.bodies.single['window_end_local'], '2026-11-05T22:00');
    expect(ideas.map((i) => i.title), ['Idea 1', 'Idea 2', 'Idea 3']);
  });

  test('an all-day draft has no time', () {
    final d = CaptureDraft.fromJson({
      'title': 'Rent',
      'all_day': true,
      'start_local': '2026-11-05',
      'end_local': null,
      'with_partner': true,
      'location': null,
      'note': null,
    });
    expect([d.allDay, d.start, d.end], [true, DateTime(2026, 11, 5), null]);
  });

  test('availability fails closed', () async {
    expect(
      (await TogetherAiRepository(FakeAiGateway()).status('r1')).available,
      isFalse,
    );
    expect(
      (await TogetherAiRepository(
        FakeAiGateway(status: {'available': true, 'partner_name': 'Kofi'}),
      ).status('r1')).partnerName,
      'Kofi',
    );
  });
}
