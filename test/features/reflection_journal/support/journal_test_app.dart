import 'dart:typed_data';

import 'package:attune/features/planning/presentation/widgets/photo_block_view.dart' show planningPhotoPickerProvider;
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:attune/features/reflection_journal/presentation/screens/journal_entry_screen.dart';
import 'package:attune/features/reflection_journal/presentation/screens/reflection_journal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'fake_journal.dart';

/// The journal with its two routes, on fakes. [photos]: what the picker
/// returns (each a JPEG's bytes).
Future<GoRouter> pumpJournal(
  WidgetTester t, {
  required FakeJournalRepository repo,
  FakeJournalMedia? media,
  List<List<int>> photos = const [],
  String initial = '/reflectionJournal',
  Object? extra,
}) async {
  final router = GoRouter(
    initialLocation: initial,
    initialExtra: extra,
    routes: [
      GoRoute(path: '/reflectionJournal', name: 'reflectionJournal', builder: (_, __) => const ReflectionJournalScreen()),
      GoRoute(
        path: '/journalEntry',
        name: 'journalEntry',
        builder: (_, s) {
          final a = s.extra! as JournalEntryArgs;
          return JournalEntryScreen(entryId: a.entryId, isNew: a.isNew, prompt: a.prompt);
        },
      ),
    ],
  );
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      reflectionJournalRepositoryProvider.overrideWithValue(repo),
      journalMediaGatewayProvider.overrideWithValue(media ?? FakeJournalMedia()),
      // No network in tests: photos show their placeholder.
      journalPhotoUrlProvider.overrideWith((ref, path) => Future<String>.error('no network in tests')),
      planningPhotoPickerProvider.overrideWithValue(
        (ImageSource source, int limit) async => (photos: [for (final p in photos) Uint8List.fromList(p)], rejected: 0),
      ),
    ],
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp.router(routerConfig: router),
    ),
  ));
  await t.pumpAndSettle();
  return router;
}
