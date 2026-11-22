// Spec 2 W7 final client fix (final-client-review.md M-14, M-5, I-3, I-6):
// goldens for W7's own surfaces with the most layout risk. The ended list
// with its line and each row's Report (a ListTile's trailing button at
// 2.0); the section's hold card (See why and Conversations, stacked) and
// its restricted and age-check cards; the report sheet whole at 2.0 (its
// field label above the field); the restricted screen's plain hold line
// and the age check with its reference code. Each at 1.0, 1.3, 2.0 and
// RTL, plus dark; each asserts its page first and the three guidelines.
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/dating/chat/conversations_screen.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/report_sheet.dart';
import 'package:attune/features/dating/report/restricted_screen.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../support/dating_chat_fakes.dart';
import '../support/dating_fakes.dart';
import '../support/dating_report_fakes.dart';
import '../support/dating_shell.dart';

/// [name] at every flow variant and in dark, [size] tall; [page] is what
/// each render must show first.
Future<void> _goldens(
  WidgetTester t,
  String name,
  Widget Function() screen, {
  required List<Override> overrides,
  required Finder page,
  Size size = const Size(390, 844),
}) async {
  for (final (variant, scale, direction) in [
    ...flowGoldenVariants,
    ('dark', 1.0, TextDirection.ltr),
  ]) {
    await pumpFlowScreen(
      t,
      variant == 'dark'
          ? () => Theme(data: AppTheme.darkTheme, child: screen())
          : screen,
      textScale: scale,
      direction: direction,
      size: size,
      overrides: overrides,
    );
    expect(page, findsWidgets, reason: '$name $variant: the page first');
    expect(t.takeException(), isNull, reason: '$name at $variant');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.$variant.png'),
    );
    await expectFlowGuidelines(t);
  }
}

void main() {
  final loc = AppLocalizationsEn();

  testWidgets('M-14: the ended list, its line and each row\'s Report', (
    t,
  ) async {
    final fake = FakeDatingChat(
      list: datingConversationsJson(
        ended: [
          {
            'match_id': 'm9',
            'display_name': 'Yaw',
            'ended_at': '2026-11-19T10:00:00Z',
          },
          {
            'match_id': 'm8',
            'display_name': 'Abena Serwaa',
            'ended_at': '2026-11-02T10:00:00Z',
          },
        ],
      ),
    );
    await _goldens(
      t,
      'dating_chats_ended',
      () => const DatingConversationsScreen(),
      overrides: [...datingShellOverrides(), ...datingChatOverrides(fake)],
      page: find.text(loc.dating_endedReportLine),
      size: const Size(390, 1100),
    );
  });

  List<Override> section(DatingHome home) => [
    ...datingShellOverrides(home: FakeDatingHomeGateway(home: home)),
    homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
    homeStateServiceProvider.overrideWithValue(
      HomeStateService(FakeHomeStateGateway(state: homeJson(path: 'dating'))),
    ),
  ];
  Widget sectionScreen() => const Scaffold(
    body: SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: DatingSection(),
    ),
  );

  for (final (name, state) in [
    ('section_hold', DatingHomeState.hold),
    ('section_restricted', DatingHomeState.restricted),
    ('section_age_review', DatingHomeState.ageReview),
  ]) {
    testWidgets('M-14: $name', (t) async {
      await _goldens(
        t,
        name,
        sectionScreen,
        overrides: section(DatingHome(state: state)),
        page: find.byKey(const ValueKey('dating_section_restricted')),
      );
    });
  }

  testWidgets('M-5: the report sheet whole at every size, its label above '
      'the field', (t) async {
    await _goldens(
      t,
      'dating_report_sheet_tall',
      () => const AllowLargeText(
        child: Scaffold(
          body: DatingReportSheet(
            account: 'ama',
            name: 'Kofi',
            target: DatingReportMatch('m1'),
          ),
        ),
      ),
      overrides: [
        ...datingShellOverrides(),
        ...datingReportOverrides(FakeDatingReport()),
      ],
      page: find.text(loc.dating_reportMore),
      size: const Size(390, 5400),
    );
  });

  for (final (name, read, page) in [
    (
      'dating_restricted_hold_plain',
      const DatingRestriction(
        id: 'r1',
        type: DatingRestrictionType.hold,
        category: DatingReportCategory.harassment,
        source: DatingRestrictionSource.moderator,
      ),
      loc.dating_restrictedHoldPlain,
    ),
    (
      'dating_restricted_id_code',
      const DatingRestriction(
        id: 'r1',
        type: DatingRestrictionType.ageReview,
        source: DatingRestrictionSource.idCheck,
        idCheckCode: 'AB23CD45',
      ),
      loc.dating_restrictedIdCode('AB23CD45'),
    ),
  ]) {
    testWidgets('I-3/I-6: $name', (t) async {
      await _goldens(
        t,
        name,
        () => const DatingRestrictedScreen(),
        overrides: [
          ...datingShellOverrides(),
          ...datingReportOverrides(
            FakeDatingReport()
              ..read = DatingRestrictionRead(ok: true, restriction: read),
          ),
        ],
        page: find.text(page),
        size: const Size(390, 1400),
      );
    });
  }
}
