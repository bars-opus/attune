// Spec 2 W7a: the report gateway faked as the server answers: a report or
// an appeal is ok (testing, P2's 48 hours) unless a test sets an answer;
// every call is recorded with its key, so a retry after busy is seen to be
// the same request; the support directory is faked with a Ghana-style
// emergency number unless a test asks for none.
import 'dart:async';

import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/dating_report_providers.dart';
import 'package:attune/features/dating/report/dating_report_repository.dart';
import 'package:attune/features/safety/data/support_resources_repository.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingReportCall {
  const DatingReportCall(
    this.key,
    this.target,
    this.category,
    this.details,
    this.alsoBlock,
  );

  final String key;
  final DatingReportTarget target;
  final DatingReportCategory category;
  final String? details;
  final bool alsoBlock;
}

class FakeDatingReport implements DatingReportGateway {
  final reports = <DatingReportCall>[];
  final appeals = <(String, String, String?)>[];
  DatingReportAnswer answer = const DatingReportAnswer(ok: true, slaHours: 48);
  DatingReportAnswer appealAnswer = const DatingReportAnswer(ok: true);
  DatingRestrictionRead read = DatingRestrictionRead.none;
  int reads = 0;
  Completer<void>? hold;

  @override
  Future<DatingReportAnswer> report(
    String key,
    DatingReportTarget target,
    DatingReportCategory category,
    String? details, {
    required bool alsoBlock,
  }) async {
    reports.add(DatingReportCall(key, target, category, details, alsoBlock));
    final held = hold;
    if (held != null) await held.future;
    return answer;
  }

  @override
  Future<DatingRestrictionRead> restriction() async {
    reads++;
    return read;
  }

  @override
  Future<DatingReportAnswer> appeal(
    String key,
    String restrictionId,
    String? text,
  ) async {
    appeals.add((key, restrictionId, text));
    final held = hold;
    if (held != null) await held.future;
    return appealAnswer;
  }
}

const datingTestEmergency = SupportResource(
  id: 'gh-112',
  countryCode: 'GH',
  category: SupportCategory.emergency,
  name: 'Emergency',
  phone: '112',
);

List<Override> datingReportOverrides(
  FakeDatingReport fake, {
  bool emergency = true,
}) => [
  datingReportGatewayProvider.overrideWithValue(fake),
  supportCountryProvider.overrideWith((ref) async => 'GH'),
  supportResourcesProvider.overrideWith(
    (ref, country) async => SupportResources(
      country: 'GH',
      countrySupported: true,
      catalogueVersion: 'test',
      resources: emergency ? const [datingTestEmergency] : const [],
      fromServer: true,
    ),
  ),
];
