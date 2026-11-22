// Spec 2 W7a (§3.7, §4.4 Reports, appeals): the report, the restricted
// person's read and the appeal, all through the Dating RPC client. Every
// call is bounded (DatingRpc); a failure answers failed or busy, never the
// error's text.
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/report/dating_report.dart';

abstract class DatingReportGateway {
  /// §3.7 a report of [category] about the other person of [target].
  Future<DatingReportAnswer> report(
    String key,
    DatingReportTarget target,
    DatingReportCategory category,
    String? details, {
    required bool alsoBlock,
  });

  /// The restriction this person sees, if any.
  Future<DatingRestrictionRead> restriction();

  /// One appeal of [restrictionId], with an optional [text].
  Future<DatingReportAnswer> appeal(
    String key,
    String restrictionId,
    String? text,
  );
}

class DatingReportRepository implements DatingReportGateway {
  DatingReportRepository(this._rpc);

  final DatingRpc _rpc;

  Future<T> _guard<T>(
    Future<dynamic> Function() call,
    T Function(Object? raw) parse,
    T busy,
    T failed,
  ) async {
    try {
      return parse(await call());
    } on DatingBusy {
      return busy;
    } catch (_) {
      return failed;
    }
  }

  @override
  Future<DatingReportAnswer> report(
    String key,
    DatingReportTarget target,
    DatingReportCategory category,
    String? details, {
    required bool alsoBlock,
  }) => _guard(
    () => _rpc(
      switch (target) {
        DatingReportMatch() => 'report_dating_match',
        DatingReportCard() => 'report_dating_introduction',
      },
      {
        'p_idempotency_key': key,
        switch (target) {
          DatingReportMatch() => 'p_match_id',
          DatingReportCard() => 'p_introduction_id',
        }: target.id,
        'p_category': category.wire,
        'p_details': details,
        'p_also_block': alsoBlock,
      },
    ),
    DatingReportAnswer.fromJson,
    DatingReportAnswer.busy,
    DatingReportAnswer.failed,
  );

  @override
  Future<DatingRestrictionRead> restriction() => _guard(
    () => _rpc('get_my_dating_restriction'),
    DatingRestrictionRead.fromJson,
    DatingRestrictionRead.busy,
    DatingRestrictionRead.failed,
  );

  @override
  Future<DatingReportAnswer> appeal(
    String key,
    String restrictionId,
    String? text,
  ) => _guard(
    () => _rpc('submit_dating_appeal', {
      'p_idempotency_key': key,
      'p_restriction_id': restrictionId,
      'p_text': text,
    }),
    DatingReportAnswer.fromJson,
    DatingReportAnswer.busy,
    DatingReportAnswer.failed,
  );
}
