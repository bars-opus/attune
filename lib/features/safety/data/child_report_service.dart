import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where the person saw it (Spec 1 §3.15), as child_safety_reports stores it.
enum ChildReportPlace {
  chat('chat'),
  stories('stories'),
  opinions('opinions'),
  dating('dating'),
  other('other');

  const ChildReportPlace(this.wire);

  final String wire;
}

/// report_child_safety_concern's answer.
enum ChildReportOutcome {
  sent,

  /// `child_report:limit`: five today already.
  limit,

  /// `child_report:invalid`: the server refused the words as written (in
  /// practice, over 2,000 characters as the server counts them). Never
  /// said as a connection problem: trying again can't help (batch 8 I-1).
  invalid,

  /// Offline, a timeout, or anything the server refused otherwise; the
  /// words stay on the screen to send again.
  failed,
}

typedef ChildReportRpc =
    Future<Object?> Function(String fn, Map<String, dynamic> params);

/// "Report a concern about a child" (Spec 1 W6c): one call, nothing else.
/// Nobody is named, and nothing tells anyone but the team.
class ChildReportService {
  ChildReportService(this._rpc);

  final ChildReportRpc _rpc;

  static const timeout = Duration(seconds: 20);

  Future<ChildReportOutcome> send({
    required ChildReportPlace? place,
    required String details,
  }) async {
    try {
      await _rpc('report_child_safety_concern', {
        'p_where': place?.wire,
        'p_details': details.trim(),
      }).timeout(timeout);
      return ChildReportOutcome.sent;
    } on PostgrestException catch (error) {
      final message = error.message;
      if (message.startsWith('child_report:limit')) {
        return ChildReportOutcome.limit;
      }
      if (message.startsWith('child_report:invalid')) {
        return ChildReportOutcome.invalid;
      }
      return ChildReportOutcome.failed;
    } catch (_) {
      // Nothing is logged: the safety features never write to the device
      // log (test/features/safety/safety_privacy_scan_test.dart).
      return ChildReportOutcome.failed;
    }
  }
}

final childReportServiceProvider = Provider<ChildReportService>(
  (ref) => ChildReportService(
    (fn, params) => Supabase.instance.client.rpc(fn, params: params),
  ),
);
