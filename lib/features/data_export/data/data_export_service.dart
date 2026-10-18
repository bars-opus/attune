import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// "Download my data" (Spec 3c; research 06 §3 F1 (5)). The server decides
/// what is in it; this asks for one, reads its state and gets a short link.
enum ExportState { queued, building, ready, failed, expired }

enum ExportRefusal { inProgress, tooSoon, other }

class DataExportException implements Exception {
  const DataExportException(this.reason);
  final ExportRefusal reason;
}

class DataExportStatus {
  const DataExportStatus({
    required this.state,
    required this.requestedAt,
    this.readyAt,
    this.expiresAt,
    this.nextAllowedAt,
    this.parts,
    this.earlierParts,
    this.earlierExpiresAt,
  });

  factory DataExportStatus.fromRow(Map<String, dynamic> row) {
    DateTime? at(String k) =>
        row[k] == null ? null : DateTime.parse(row[k] as String);
    return DataExportStatus(
      state: switch (row['status']) {
        'queued' => ExportState.queued,
        'building' => ExportState.building,
        'ready' => ExportState.ready,
        'expired' => ExportState.expired,
        _ => ExportState.failed,
      },
      requestedAt: at('requested_at')!,
      readyAt: at('ready_at'),
      expiresAt: at('expires_at'),
      nextAllowedAt: at('next_allowed_at'),
      parts: row['parts'] as int?,
      earlierParts: row['earlier_parts'] as int?,
      earlierExpiresAt: at('earlier_expires_at'),
    );
  }

  final ExportState state;
  final DateTime requestedAt;
  final DateTime? readyAt;
  final DateTime? expiresAt;
  final DateTime? nextAllowedAt;

  /// How many files make up a ready download.
  final int? parts;

  /// While this one is not ready: an earlier download that still is, and
  /// until when (re-review M8).
  final int? earlierParts;
  final DateTime? earlierExpiresAt;

  bool get inProgress =>
      state == ExportState.queued || state == ExportState.building;
}

typedef ExportRpc =
    Future<dynamic> Function(String fn, [Map<String, dynamic>? params]);
typedef ExportInvoke = Future<dynamic> Function(String fn);

class DataExportService {
  DataExportService({ExportRpc? rpc, ExportInvoke? invoke})
    : _rpc = rpc,
      _invoke = invoke;

  final ExportRpc? _rpc;
  final ExportInvoke? _invoke;

  Future<dynamic> _call(String fn) {
    final rpc = _rpc;
    if (rpc != null) return rpc(fn);
    return Supabase.instance.client.rpc(fn);
  }

  Future<void> request() async {
    try {
      await _call('request_my_export');
    } on PostgrestException catch (e) {
      if (e.message.contains('export:in_progress')) {
        throw const DataExportException(ExportRefusal.inProgress);
      }
      if (e.message.contains('export:too_soon')) {
        throw const DataExportException(ExportRefusal.tooSoon);
      }
      throw const DataExportException(ExportRefusal.other);
    } catch (_) {
      // Network, timeout, anything: one typed answer (final review I6).
      throw const DataExportException(ExportRefusal.other);
    }
  }

  Future<DataExportStatus?> latest() async {
    final rows = await _call('get_my_export') as List<dynamic>?;
    if (rows == null || rows.isEmpty) return null;
    return DataExportStatus.fromRow(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  /// 15-minute links to each part of the person's own ready download.
  Future<List<String>> downloadUrls() async {
    final invoke = _invoke;
    final data =
        invoke != null
            ? await invoke('get-export-url')
            : (await Supabase.instance.client.functions.invoke(
              'get-export-url',
            )).data;
    final urls = data is Map ? (data['urls'] as List?)?.cast<String>() : null;
    if (urls == null || urls.isEmpty) {
      throw const DataExportException(ExportRefusal.other);
    }
    return urls;
  }
}

final dataExportServiceProvider = Provider<DataExportService>(
  (_) => DataExportService(),
);
