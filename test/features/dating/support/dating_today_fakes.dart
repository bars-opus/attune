// Spec 2 W5b: Today faked for widget tests. Every answer is the test's;
// every call is recorded; a read can be held open (D8 tests).
import 'dart:async';
import 'dart:convert';

import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/dating_today_providers.dart';
import 'package:attune/features/dating/today/dating_today_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A card as the server sends it (§3.4), [over] on top.
Map<String, Object?> datingCardJson(
  String id, [
  Map<String, Object?> over = const {},
]) => {
  'id': id,
  'display_name': 'Kofi',
  'age': 31,
  'region_name_key': 'dating_region_gh_aa',
  'intention': 'committed',
  'children_have': false,
  'children_want': 'yes',
  'prompts': [
    {
      'prompt_id': 'perfect_sunday',
      'answer': 'Church, then jollof with my cousins.',
    },
  ],
  'reasons': ['same_intention', 'children_want_yes', 'same_region'],
  'photos_after_mutual': false,
  'photos': [
    {'id': '$id-p1', 'position': 1, 'caption': 'At the beach in Busua'},
    {'id': '$id-p2', 'position': 2, 'caption': null},
  ],
  'acted': null,
  ...over,
};

Map<String, Object?> datingTodayJson([Map<String, Object?> over = const {}]) =>
    {
      'ok': true,
      'today_state': 'delivered',
      'drop_at': null,
      'region_name_key': 'dating_region_gh_aa',
      'cards': [datingCardJson('i1')],
      'waiting': <Object?>[],
      'moments': <Object?>[],
      'family_question': false,
      'quiet_note': false,
      'data_saver': false,
      'widen': {'min_age': 25, 'max_age': 40, 'scope': 'region'},
      ...over,
    };

class FakeDatingToday implements DatingTodayGateway {
  FakeDatingToday({Map<String, Object?>? today})
    : json = today ?? datingTodayJson();

  Map<String, Object?> json;
  Completer<DatingToday>? hold;
  DatingActAnswer Function(String id, String action) answer =
      (id, action) => DatingActAnswer(ok: true, action: action);
  final acts = <(String key, String id, String action)>[];
  final seen = <String>[];
  final notes = <String>[];
  final families = <String?>[];
  final photoCalls = <(String, String)>[];
  List<DatingPhotoUrl>? urls = const [
    DatingPhotoUrl(1, 'https://s.test/1'),
    DatingPhotoUrl(2, 'https://s.test/2'),
  ];
  int reads = 0;

  /// Task 7b: every block asked (key, id); an answer can be held open.
  final blocks = <(String key, String id)>[];
  Completer<DatingBlockAnswer>? blockHold;
  DatingBlockAnswer Function(String id) blockAnswer =
      (id) => const DatingBlockAnswer(ok: true);

  @override
  Future<DatingToday> today() async {
    reads++;
    final h = hold;
    if (h != null) return h.future;
    return DatingToday.fromJson(json);
  }

  @override
  Future<DatingActAnswer> act(String key, String id, String action) async {
    acts.add((key, id, action));
    return answer(id, action);
  }

  @override
  Future<DatingBlockAnswer> block(String key, String id) async {
    blocks.add((key, id));
    final h = blockHold;
    if (h != null) return h.future;
    return blockAnswer(id);
  }

  @override
  Future<void> momentSeen(String matchId) async => seen.add(matchId);

  @override
  Future<DatingWrite> dismissNote(String note) async {
    notes.add(note);
    return const DatingWrite(ok: true);
  }

  @override
  Future<DatingWrite> saveFamily(String key, String? value) async {
    families.add(value);
    return const DatingWrite(ok: true);
  }

  @override
  Future<List<DatingPhotoUrl>?> photoUrls(String kind, String id) async {
    photoCalls.add((kind, id));
    return urls;
  }
}

/// A one-pixel PNG for every photo URL; the URLs fetched are recorded.
final datingFetched = <String>[];
List<Override> datingTodayOverrides(FakeDatingToday fake) => [
  datingTodayGatewayProvider.overrideWithValue(fake),
  datingPhotoFetchProvider.overrideWithValue((url) async {
    datingFetched.add(url);
    return datingTestPng;
  }),
];

/// A valid 1 x 1 PNG.
final datingTestPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);
