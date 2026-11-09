// Spec 1 §8 W10a: TextScalePolicy keeps every Games route at 1.0 through its
// route prefixes, and every route the audit hasn't checked; every other
// route gets the cap. The Games routes are found from app_router.dart itself
// (every GoRoute whose builder uses a class imported from
// lib/features/games/), so a Games route added later fails here until its
// prefix is listed. No Games file is edited.
import 'dart:io';

import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/text_scale_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Routes outside the W10a audit (they keep 1.0 until they are audited and
/// their prefix is added to TextScalePolicy.auditedRoutePrefixes).
const _notYetAudited = {
  'intro',
  'login',
  'profile',
  'pulse',
  'chatInsights',
  'chatImport',
  'weeklyCheckin',
  'checkinComplete',
  'logMomentType',
  'logMomentDetails',
  'quizEntry',
  'attachmentQuiz',
  'attachmentQuizLoading',
  'attachmentQuizResult',
  'conflictStyleQuiz',
  'conflictStyleLoading',
  'conflictStyleResult',
  'loveLanguageQuiz',
  'loveLanguageResult',
  'communicationStyleQuiz',
  'communicationStyleLoading',
  'communicationStyleResult',
  'partnerQuizResult',
  'communityFeed',
  'notificationInbox',
  'previousRelationships',
  // W10 B6 I-1: Settings is audited by exact location; this child is not.
  'dataExport',
  // W10 B6 I-4: inside the audited prefixes, but no audit test reaches them.
  'language',
  'theme',
  'licenses',
  'allLegalDocumentation',
  'appInfoScreen',
  'blockedAccountsScreen',
  'mutedAuthorsScreen',
  'neutralScreen',
  'starredMessages',
  'chatMessageSearch',
  'ephemeralCamera',
  'familyMembers',
  'anonymousProfile',
  'opinionEngagement',
  'opinionLoader',
};

/// Routes the W10a audit checked: they get the cap. A new route fails below
/// until it is listed here or in [_notYetAudited], even one that falls
/// under an audited prefix (W10 final W-m2).
const _audited = {
  // Spec 2 W3a (§3.0): every Dating screen.
  'datingSetupStep',
  'datingUnlock',
  'datingSettings',
  'datingNotOpen',
  'datingLeave',
  'aboutUs',
  'addEditReminder',
  'ageStop',
  'appreciationJar',
  'birthDateSettings',
  'chatChannel',
  'chatMedia',
  'chatScreen',
  'commentThread',
  'editOpinion',
  'ephemeralVideoViewer',
  'guestAge',
  'healingJourney',
  'healingStage',
  'hiddenPeriods',
  'home',
  'howYouUseAttune',
  'imageCaption',
  'imageViewer',
  'invite',
  'invitePartner',
  'joinInvite',
  'journalEntry',
  'onboarding',
  'outsidePerspective',
  'planning',
  'planning_flow',
  'quietStates',
  'quoteCompose',
  'reflectionJournal',
  'reportChildConcern',
  'safetyPin',
  'safetyResources',
  'settings',
  'signUp',
  'signedInDevices',
  'streakCamera',
  'tagBrowse',
  'timeline',
  'together',
  'videoTrim',
  'videoViewer',
  'welcome',
};

/// Routes registered without a name (the arch checks below go by name):
/// the boot route and the Ask 2 flow. Any other unnamed route fails.
const _unnamedAllowed = {"'/_invisible'", 'RouteNames.ask2Flow'};

/// Every class declared in the Games files app_router.dart imports.
Set<String> _gamesClasses(String router) {
  final classes = <String>{};
  final imports = RegExp(
    r"import 'package:attune/(features/games/[^']+)'[^;]*;",
  ).allMatches(router);
  for (final m in imports) {
    final src = File('lib/${m.group(1)}').readAsStringSync();
    classes.addAll(
      RegExp(
        r'^class (\w+)',
        multiLine: true,
      ).allMatches(src).map((c) => c.group(1)!),
    );
  }
  return classes;
}

/// Every `GoRoute(...)` call in [src], whole (parentheses matched; string
/// literals and // comments skipped); nested routes are found too.
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
        i++;
        while (i < src.length && src[i] != c) {
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
    from = start + 'GoRoute('.length;
  }
}

Map<String, String> _namedPaths(List<RouteBase> routes) => {
  for (final route in routes) ...{
    if (route is GoRoute && route.name != null) route.name!: route.path,
    ..._namedPaths(route.routes),
  },
};

/// A concrete location for [path] (`:id` filled in).
String _location(String path) => path.replaceAll(RegExp(r':\w+'), 'x');

bool _gamesPrefix(String location) =>
    TextScalePolicy.gameRoutePrefixes.any(location.startsWith);

void main() {
  final src = File('lib/app/routing/app_router.dart').readAsStringSync();
  final games = _gamesClasses(src);
  final gamesRouteNames = <String>{};
  for (final block in _goRouteBlocks(src)) {
    final name = RegExp(r"name:\s*'([^']+)'").firstMatch(block)?.group(1);
    final usesGames = games.any(
      (c) => RegExp('\\b${RegExp.escape(c)}\\(').hasMatch(block),
    );
    if (name != null && usesGames) gamesRouteNames.add(name);
  }
  final router = createAppRouter(RoutingNotifier());
  final paths = _namedPaths(router.configuration.routes);
  router.dispose();

  test('the Games routes are found (39 today)', () {
    expect(games, isNotEmpty);
    expect(gamesRouteNames.length, greaterThanOrEqualTo(39));
    expect(paths.keys, containsAll(gamesRouteNames));
    expect(paths.keys, containsAll(_notYetAudited));
  });

  test('every GoRoute is named, but the allowed few (W10 B6 M-3)', () {
    for (final block in _goRouteBlocks(src)) {
      if (RegExp(r'\bname:\s*\S').hasMatch(block)) continue;
      final path = RegExp(r'path:\s*([^,\n]+),').firstMatch(block)?.group(1);
      expect(_unnamedAllowed, contains(path), reason: block.split('\n').first);
    }
  });

  test('a Games import with show/as is still read (W10 B6 M-4)', () {
    expect(
      _gamesClasses(
        "import 'package:attune/features/games/presentation/widgets/"
        "game_grid_tile.dart' show GameGridTile;",
      ),
      contains('GameGridTile'),
    );
  });

  test('every Games route keeps 1.0 through a Games prefix', () {
    for (final name in gamesRouteNames) {
      final at = _location(paths[name]!);
      expect(_gamesPrefix(at), isTrue, reason: '$name ($at): add its prefix');
      expect(TextScalePolicy.keepsDefaultSize(at), isTrue, reason: name);
    }
  });

  test('no Games prefix matches a route that is not a Games route', () {
    for (final MapEntry(key: name, value: path) in paths.entries) {
      if (gamesRouteNames.contains(name)) continue;
      expect(_gamesPrefix(_location(path)), isFalse, reason: '$name ($path)');
    }
  });

  test('only the routes not audited yet keep 1.0; the rest get the cap', () {
    for (final MapEntry(key: name, value: path) in paths.entries) {
      if (gamesRouteNames.contains(name)) continue;
      expect(
        TextScalePolicy.keepsDefaultSize(_location(path)),
        _notYetAudited.contains(name),
        reason: '$name ($path)',
      );
    }
  });

  test('every route is classified: audited, not audited yet, or Games '
      '(W10 final W-m2)', () {
    expect(_audited.intersection(_notYetAudited), isEmpty);
    expect(paths.keys, containsAll(_audited));
    for (final MapEntry(key: name, value: path) in paths.entries) {
      if (gamesRouteNames.contains(name)) continue;
      expect(
        _audited.contains(name) || _notYetAudited.contains(name),
        isTrue,
        reason: '$name ($path): audit it, or list it in _notYetAudited',
      );
      expect(
        TextScalePolicy.keepsDefaultSize(_location(path)),
        !_audited.contains(name),
        reason: '$name ($path)',
      );
    }
  });
}
