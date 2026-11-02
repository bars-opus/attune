// Spec 1 §1.5, §5.4, §5.6 R2/R15 (W2 B2 review N-7): the in-chat Games stay
// exactly as they are. Every Games route keeps its name and path, the source
// of each Games GoRoute is byte-for-byte what it was when W3 started, the
// chat's Games entry points are still imported, and the auth_exports.dart
// barrel is unchanged. A Games change made on purpose updates this file in
// the same change; nothing in Spec 1 may.
import 'dart:convert';
import 'dart:io';

import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Route name -> path, as the router registers them.
const _gamesRoutes = <String, String>{
  'thirtySixChapterInvitation': '/thirtySixChapterInvitation',
  'thirtySixChapterIntroduction': '/thirtySixChapterIntroduction',
  'thirtySixQuestion': '/thirtySixQuestion',
  'thirtySixChapterCompletion': '/thirtySixChapterCompletion',
  'thirtySixWaiting': '/thirtySixWaiting',
  'thirtySixReveal': '/thirtySixReveal',
  'thirtySixJourneyCompletion': '/thirtySixJourneyCompletion',
  'thirtySixChapterHistory': '/thirtySixChapterHistory',
  'truthOrDareGame': '/truthOrDareGame',
  'truthOrDareToneSelector': '/truthOrDareToneSelector',
  'truthOrDareSessionRouter': '/truthOrDareSessionRouter',
  'customTruthOrDareList': '/customTruthOrDareList',
  'customTruthOrDareCreate': '/customTruthOrDareCreate',
  'truthOrDareHistory': '/truthOrDareHistory',
  'truthReveal': '/truthReveal',
  'dareReveal': '/dareReveal',
  'thirtySixQuestions': '/thirtySixQuestions',
  'thirtySixJourneyOverview': '/thirtySixJourneyOverview',
  'thisOrThatGamesHub': '/thisOrThatGamesHub',
  'thisOrThatToneSelector': '/thisOrThatToneSelector',
  'thisOrThatSessionRouter': '/thisOrThatSessionRouter',
  'mirrorGame': '/mirrorGame',
  'slidingScaleGame': '/slidingScaleGame',
  'scenarioGame': '/scenarioGame',
  'loveMap': '/loveMap',
  'customQuestionList': '/customQuestionList',
  'customQuestionCreate': '/customQuestionCreate',
  'thisOrThatSessionHistory': '/thisOrThatSessionHistory',
  'thisOrThatSessionDetail': '/thisOrThatSessionDetail',
  'thisOrThatCustomList': '/thisOrThatCustomList',
  'thisOrThatCustomCreate': '/thisOrThatCustomCreate',
  'paintBallLobby': '/games/paint-ball/lobby/:relationshipId',
  'paintBallBattle': '/games/paint-ball/battle/:sessionId',
  'paintBallHistory': '/games/paint-ball/history/:relationshipId',
  'paintBallKnockout': '/games/paint-ball/knockout/:sessionId',
  'snakesGame': '/games/snakes/:relationshipId',
  'constellationPrototype': '/games/constellation/prototype',
  'dotsBoxesPrototype': '/games/dots-and-boxes/prototype',
  'wordHuntGame': '/games/word-hunt/:relationshipId',
};

/// Route name -> SHA-256 of its whole `GoRoute(...)` call in app_router.dart.
const _gamesRouteSource = <String, String>{
  'thirtySixChapterInvitation':
      '78fc13c0f63cb839c8f398888a4a4549d1be9428ea02af059f5cfd0c442d03f3',
  'thirtySixChapterIntroduction':
      '1152e0806becc7db7bf1f7380a44e99b91bda7c82c78ae853fb2c9b921b2b2b0',
  'thirtySixQuestion':
      'a5b65ef48ea46255455ce9d47baa7153a2d0182e6ab0491bf07075c29212b9a4',
  'thirtySixChapterCompletion':
      '72f97ad7c9ce6d47318ef135aa0a686e6846815ed1b0216b1f0dfee8dc114827',
  'thirtySixWaiting':
      '8d0ed98f6a0bb948c697cbff5086a1e56cbc0150c19ed0538c676b005a2bd2d1',
  'thirtySixReveal':
      'a95df65ed84ef670ee1bf534a3697e4230fd4300f6110d82a076b154e26b75df',
  'thirtySixJourneyCompletion':
      '55641bdfb9fc5c8ab9a8b27af0cda784f804edc25f757ad9538e52820900bc92',
  'thirtySixChapterHistory':
      '6faa89cbb671ac04e6ca49df42dee745cec289c140ce00f5b85439ed353bb151',
  'truthOrDareGame':
      '76be5d20542bb9c7d30e91823a930e3241e157329eefc7eafdce3471e1ff0b2e',
  'truthOrDareToneSelector':
      'e8b11fba1282aed1797bf0966e2bd7dc2791b04724ae12608c4737f6e193d399',
  'truthOrDareSessionRouter':
      'fe8d729a52f1ac3a145d8fb8925025ff8681d31cb0a6d83d8457486d3a706531',
  'customTruthOrDareList':
      '52434de4d450785539fda6a919e1988aa509dda21c8229a0d0cce662b525485f',
  'customTruthOrDareCreate':
      '9b58ce629efa0ddeed170909bd727f7e0c3ec736fc0cf15a32da4df0d1459aad',
  'truthOrDareHistory':
      'a3f7409a75fbb15561bd40be4510d6c52bc58f89bb25cabccb3da5e8ae62aa6b',
  'truthReveal':
      '45d17c5d7f4fbbb859e1a746c5d9539fb60d930d19a804a3e7b092f621cd18e9',
  'dareReveal':
      'c33a89652fca6aa9d775f869186600ba2204e5ad3ac922183abe4cff0ea4a54d',
  'thirtySixQuestions':
      '0bcd25cccc75f624b9acc230df39382bd64498d41f6278d3f4562069ee9be59d',
  'thirtySixJourneyOverview':
      '76a741c345e498534b2c3f8f5eab5842d033c87538ef8666e7d180b4a6e7fc9d',
  'thisOrThatGamesHub':
      '3c6e15ee139f1e45b90389fe2fd69a810117518516acc1a24f6beee77c369096',
  'thisOrThatToneSelector':
      'ac2a35aef3f0b23b934285da9a7c73fe8fc169ef519c82b8a5170037766dd0bc',
  'thisOrThatSessionRouter':
      'a99935db28953f8371159173deecae12da0d843c535a0b95c936cd09ad328d69',
  'mirrorGame':
      'd738c2f9c8e716b22b2e3319ceabdc0fe5230801ab457d299a245490c20aff5d',
  'slidingScaleGame':
      '7a4de78d2e9a727a06c53e359ffe41aa51f5320f04ce0b2a003346f2a22a67de',
  'scenarioGame':
      '26f89e0c12aaea59cfdf8df84041da5e36467621d418ad974a3d576d8f85b06d',
  'loveMap': '0c445c2db0c91d734711b503cd615103b0348f8fcaa2a2358aeee4da586733a0',
  'customQuestionList':
      'b8289b828f19970b04242f312b8ca3c5a79853c2428d67f7999bf1bc517c84d2',
  'customQuestionCreate':
      'f08b54e5697de36dd69709049451d457a10a35c17eaf2168172a27c4b4b35b9c',
  'thisOrThatSessionHistory':
      'aa33f83d6a1f7ff121b5667526b90fa75ebb524ad13c61e0b6ea286177b3a094',
  'thisOrThatSessionDetail':
      '3deefe616c23a4e7bea2c0377b7a542ab11c3dc2b25c6737d7b98be0bd28165d',
  'thisOrThatCustomList':
      '3a9ef7c83c32dc626bbb21fdff7dd937d0e15be7b4262428377393c70076b39f',
  'thisOrThatCustomCreate':
      '267e87245a314ce24e272790c30d7808885e8a85b618fd9d7fb519617e159b6c',
  'paintBallLobby':
      '4690039dab81262e0834e2aa36e7db4a6dffe503fcb0e122a1a97dcaab539b65',
  'paintBallBattle':
      '313dbd659e99935287c3810c9647f1c2c7a55781fbac3c3db408e03810c67156',
  'paintBallHistory':
      '32fa14d4e62e15b0bfadf3595a63ca2383f88675b19c07e0c07128adee5e18a5',
  'paintBallKnockout':
      '0a8bcd3e350234f4a150ae6e8a485518d0e9691a01b1249b1dcc8b9983534815',
  'snakesGame':
      '67d3730e3fb694efdd7d2dce9e5afdf1b9827523ead6adbcda4e0efdbca31da7',
  'constellationPrototype':
      '1505763b07ead71898bafe408e956043d7f986ed7bd9740e3ba7bffe22fd90d2',
  'dotsBoxesPrototype':
      '728b40a5a8f16dcdf97532e8525593e38ad1a150f09545bfa604e4047116fbb2',
  'wordHuntGame':
      '1cce8fe6cfa7057a070d07645d16dce1dc451792adbff3a577a96552c7cf0eb5',
};

/// The chat screen's Games entry points (§1.5: chat_screen.dart:69-78).
const _chatGamesImports = [
  "import 'package:attune/features/games/paint_ball/models/paint_ball_models.dart';",
  "import 'package:attune/features/games/invites/presentation/game_composer_bar.dart';",
  "import 'package:attune/features/games/invites/state/game_invite_provider.dart';",
  "import 'package:attune/features/games/presentation/providers/game_card_provider.dart';",
  "import 'package:attune/features/games/presentation/providers/game_partner_name_provider.dart';",
  "import 'package:attune/features/games/presentation/widgets/chat_games_sheet.dart';",
  "import 'package:attune/features/games/presentation/widgets/game_icon.dart';",
  "import 'package:attune/features/games/presentation/widgets/game_palette.dart';",
];

/// Fix round 1 (review I#2): the Games use sites in the chat, as code
/// (whitespace-insensitive, so a reflow alone doesn't trip it). Spec 1.5:
/// chat_screen.dart's composer entry point (`showGames: true`, ~:2137) and
/// sheet (~:5189), the staged game above the composer, the game card tap,
/// ChatTextField's Games parameters, and message_bubble's game bubbles.
const _gamesUseSites = <String, List<String>>{
  'lib/features/chat/presentation/screens/chat_screen.dart': [
    'void _openGames() {',
    'showChatGamesPicker(',
    'onOpenGames: _openGames,',
    'showGames: true,',
    'widget: ChatGamesSheet(',
    'if (conversation.canSend && stagedGame != null) GameComposerBar(',
    'onGameTap: (gameType, sessionId, autoAccept) {',
  ],
  'lib/features/chat/presentation/widgets/chat_text_field.dart': [
    'this.onOpenGames,',
    'this.showGames = false,',
    'final VoidCallback? onOpenGames;',
    'final bool showGames;',
    '(!_hasText && widget.showGames && !widget.aiMode)',
    'onTap: widget.enabled ? widget.onOpenGames : null,',
  ],
  'lib/features/chat/presentation/widgets/message_bubble.dart': [
    "import 'package:attune/features/games/presentation/widgets/game_message_bubble.dart';",
    "import 'package:attune/features/games/presentation/widgets/game_trail_line.dart';",
    'final isSelfSurfaced = message.isGame && message.gameSessionId != null;',
    'onGameTap: onGameTap,',
    'if (message.isGameTrail) {',
    'children.add( GameTrailLine( label: message.content, isMine: isMine,',
    '} else if (message.isGame && message.gameSessionId != null) { '
        'children.add( GameMessageBubble( sessionId: message.gameSessionId!,',
    'onTap: (gameType, sessionId, autoAccept) => '
        'onGameTap?.call(gameType, sessionId, autoAccept),',
  ],
};

String _squash(String code) => code.replaceAll(RegExp(r'\s+'), ' ');

const _authExportsSha256 =
    'c615dbed9246f7a4582b9e8c072a8258378f769eb62de54b6960f31c356c63f2';

/// Every `GoRoute(...)` call in [src], whole: parentheses matched, string
/// literals and `//` comments skipped.
List<String> _goRouteBlocks(String src) {
  final blocks = <String>[];
  var from = 0;
  while (true) {
    final start = src.indexOf('GoRoute(', from);
    if (start < 0) return blocks;
    var i = start + 'GoRoute'.length;
    var depth = 0;
    while (i < src.length) {
      final c = src[i];
      if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
        i = src.indexOf('\n', i);
        if (i < 0) i = src.length;
        continue;
      }
      if (c == "'" || c == '"') {
        final quote = c;
        i++;
        while (i < src.length && src[i] != quote) {
          if (src[i] == r'\') i++;
          i++;
        }
        i++;
        continue;
      }
      if (c == '(') depth++;
      if (c == ')') {
        depth--;
        if (depth == 0) break;
      }
      i++;
    }
    blocks.add(src.substring(start, i + 1));
    from = i + 1;
  }
}

Map<String, String> _namedPaths(List<RouteBase> routes) => {
  for (final route in routes) ...{
    if (route is GoRoute && route.name != null) route.name!: route.path,
    ..._namedPaths(route.routes),
  },
};

void main() {
  test('every Games route keeps its name and path', () {
    final router = createAppRouter(RoutingNotifier());
    addTearDown(router.dispose);
    final live = _namedPaths(router.configuration.routes);
    for (final entry in _gamesRoutes.entries) {
      expect(live[entry.key], entry.value, reason: entry.key);
    }
  });

  test('the source of every Games route is unchanged', () {
    final src = File('lib/app/routing/app_router.dart').readAsStringSync();
    final seen = <String, String>{};
    for (final block in _goRouteBlocks(src)) {
      final name = RegExp(r"name:\s*'([^']+)'").firstMatch(block)?.group(1);
      if (name != null && _gamesRouteSource.containsKey(name)) {
        seen[name] = sha256.convert(utf8.encode(block)).toString();
      }
    }
    expect(seen.keys.toSet(), _gamesRouteSource.keys.toSet());
    for (final entry in _gamesRouteSource.entries) {
      expect(seen[entry.key], entry.value, reason: '${entry.key} changed');
    }
  });

  test("the chat's Games entry points are still there", () {
    final chat =
        File(
          'lib/features/chat/presentation/screens/chat_screen.dart',
        ).readAsStringSync();
    for (final line in _chatGamesImports) {
      expect(chat, contains(line));
    }
    expect(chat, contains('ChatGamesSheet'));
  });

  test("the chat's Games use sites are still wired (I#2)", () {
    for (final entry in _gamesUseSites.entries) {
      final code = _squash(File(entry.key).readAsStringSync());
      for (final site in entry.value) {
        expect(
          code.contains(_squash(site)),
          isTrue,
          reason: '${entry.key} no longer has: $site',
        );
      }
    }
  });

  test('the auth_exports.dart barrel is byte-identical', () {
    final bytes =
        File('lib/features/auth/utility/auth_exports.dart').readAsBytesSync();
    expect(sha256.convert(bytes).toString(), _authExportsSha256);
  });
}
