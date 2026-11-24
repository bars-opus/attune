// Spec 2 W9: the couple link faked for widget tests. Every answer is the
// test's; every call is recorded; an answer can be held open (D8 tests).
import 'dart:async';

import 'package:attune/features/dating/link/dating_link.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FakeDatingLink implements DatingLinkGateway {
  FakeDatingLink({
    this.pageAnswer = const DatingLinkPage(
      ok: true,
      displayName: 'Kofi',
      link: DatingLink(state: DatingLinkState.none),
    ),
    this.offerAnswer = DatingPostLinkOffer.none,
  });

  DatingLinkPage pageAnswer;
  DatingLinkAnswer answer = const DatingLinkAnswer(ok: true, requestId: 'r1');
  DatingPostLinkOffer offerAnswer;
  DateTime? originAnswer;
  List<DatingHowWeMetItem>? howAnswer;
  Completer<void>? hold;

  /// Fix round 1 (I-1): holds [dismiss] open until completed.
  Completer<void>? dismissHold;

  final pages = <String>[];
  final asks = <(String key, String matchId, bool keep)>[];
  final confirms = <(String key, String requestId, bool keep)>[];
  final declines = <String>[];
  final cancels = <String>[];
  final origins = <String>[];
  final hows = <String>[];
  int offers = 0;
  final dismissals = <DatingPostLinkOffer>[];

  /// Dismissals that have finished; [offerReads] is this count at each
  /// offer read (a read after "seen" landed sees it).
  int dismissalsDone = 0;
  final offerReads = <int>[];

  Future<DatingLinkAnswer> _answer() async {
    final held = hold;
    if (held != null) await held.future;
    return answer;
  }

  @override
  Future<DatingLinkPage> page(String matchId) async {
    pages.add(matchId);
    return pageAnswer;
  }

  @override
  Future<DatingLinkAnswer> ask(
    String key,
    String matchId, {
    required bool keep,
  }) {
    asks.add((key, matchId, keep));
    return _answer();
  }

  @override
  Future<DatingLinkAnswer> confirm(
    String key,
    String requestId, {
    required bool keep,
  }) {
    confirms.add((key, requestId, keep));
    return _answer();
  }

  @override
  Future<DatingLinkAnswer> decline(String requestId) {
    declines.add(requestId);
    return _answer();
  }

  @override
  Future<DatingLinkAnswer> cancel(String requestId) {
    cancels.add(requestId);
    return _answer();
  }

  @override
  Future<DateTime?> origin(String relationshipId) async {
    origins.add(relationshipId);
    return originAnswer;
  }

  @override
  Future<List<DatingHowWeMetItem>?> howWeMet(String relationshipId) async {
    hows.add(relationshipId);
    return howAnswer;
  }

  @override
  Future<DatingPostLinkOffer> offer() async {
    offers++;
    offerReads.add(dismissalsDone);
    return offerAnswer;
  }

  @override
  Future<bool> dismiss(DatingPostLinkOffer offer) async {
    dismissals.add(offer);
    final held = dismissHold;
    if (held != null) await held.future;
    offerAnswer = DatingPostLinkOffer.none;
    dismissalsDone++;
    return true;
  }
}

List<Override> datingLinkOverrides(FakeDatingLink fake) => [
  datingLinkGatewayProvider.overrideWithValue(fake),
];
