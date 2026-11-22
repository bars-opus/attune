// Spec 2 W7b (§6.4 Queue): open cases by priority and time to their clock
// (the server leaves out a case that needs routing this moderator lacks);
// claim from the row; open a case.
//
// Task 7: loading, busy and offline read calmly with Try again; a case
// another moderator holds offers Take over (the server allows it only
// once their claim has gone quiet, and answers claimed otherwise); the
// queue reads again when a case is closed.
//
// Fix round 1 (I-2): a read that came back full says more are waiting and
// never says a page is empty.
//
// W7 final client fix (I-5, M-2, M-7, I-6): each page reads its own kinds,
// one read per kind (moderation_queue's p_kind; has_more says more are
// waiting), so one kind never crowds another out of the 200. The Queue
// page lists "Waiting for ID / ID still needed" first: every case whose
// asked age check is live, decided No ID came cases too, so a late ID can
// still be handled; its rows give the ID check's code (found from the
// person's email with the browser's find) and never a clock or "late" (the
// server leaves them out of the SLA). A read again that fails keeps the
// last good rows and the action's line above Try again.
import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:attune/console/screens/case_screen.dart'
    show ConsoleIdCheck, consoleCaseKind;
import 'package:flutter/material.dart';

/// "in 2 h 5 m" or "5 m late", from now.
String consoleDue(DateTime? due, DateTime now) {
  if (due == null) return 'no clock';
  final d = due.difference(now);
  final m = d.inMinutes.abs();
  final text = '${m ~/ 60} h ${m % 60} m';
  return d.isNegative ? '$text late' : 'in $text';
}

/// What a claim's answer says.
ConsoleLine consoleClaimLine(ConsoleAnswer r) {
  if (!r.ok) return ConsoleLine.of(r);
  return r.data['took_over'] == true
      ? const ConsoleLine('You took this case over from another moderator.')
      : const ConsoleLine('Claimed: the case is yours.');
}

class QueueScreen extends StatefulWidget {
  const QueueScreen({
    super.key,
    required this.api,
    required this.kinds,
    required this.onOpen,
    this.title = 'Open cases',
    this.idChecks = false,
    this.now,
  });

  final ConsoleApi api;

  /// The kinds this page lists, each its own read, in this order.
  final Set<String> kinds;
  final Future<void> Function(String caseId) onOpen;
  final String title;

  /// I-5: the "Waiting for ID / ID still needed" section, first.
  final bool idChecks;
  final DateTime Function()? now;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  /// Each read's latest answer, by kind ('id_check' for the ID section);
  /// null until the first reads land.
  Map<String, ConsoleAnswer>? _reads;

  /// M-7: each read's last good answer.
  final _good = <String, ConsoleAnswer>{};
  ConsoleLine? _line;
  bool _claiming = false;

  List<String> get _kinds => [
    if (widget.idChecks) 'id_check',
    ...widget.kinds,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final kinds = _kinds;
    final answers = await Future.wait([
      for (final k in kinds)
        widget.api('queue', {'kind': k, 'limit': kConsoleQueueLimit}),
    ]);
    if (!mounted) return;
    setState(() {
      _reads = {for (final (i, k) in kinds.indexed) k: answers[i]};
      for (final (i, k) in kinds.indexed) {
        if (answers[i].ok) _good[k] = answers[i];
      }
    });
  }

  Future<void> _retry() async {
    setState(() => _reads = null);
    await _load();
  }

  Future<void> _claim(String id) async {
    setState(() {
      _claiming = true;
      _line = null;
    });
    final r = await widget.api('claim', {'case_id': id});
    if (!mounted) return;
    setState(() {
      _claiming = false;
      _line = consoleClaimLine(r);
    });
    await _load();
  }

  Future<void> _open(String id) async {
    await widget.onOpen(id);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => ConsoleFrame(
    title: widget.title,
    onRefresh: _reads == null ? null : _load,
    child: _list(context),
  );

  /// The rows a read gave (its last good one when it failed), only of its
  /// kind (server round 3: the ID section's are id_check cases).
  List<Map<String, dynamic>> _rows(String kind) {
    final read = _reads?[kind];
    final answer = read != null && read.ok ? read : _good[kind];
    if (answer == null) return const [];
    return [
      for (final c in answer.list('cases'))
        if (c['kind'] == kind) c,
    ];
  }

  /// A read that may have left cases out: the server's has_more, or (an
  /// older answer without it) a full page.
  bool _capped(String kind) {
    final read = _reads?[kind];
    final answer = read != null && read.ok ? read : _good[kind];
    if (answer == null) return false;
    final more = answer.data['has_more'];
    return more is bool
        ? more
        : answer.list('cases').length >= kConsoleQueueLimit;
  }

  Widget _list(BuildContext context) {
    final reads = _reads;
    if (reads == null) return const ConsoleLoading('Loading the queue.');
    final failed = reads.values.where((r) => !r.ok).firstOrNull;
    final said = switch (_line) {
      final line? => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: ConsoleStatus(line),
      ),
      null => null,
    };
    if (failed != null && _good.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (said != null) said,
            _retryFor(failed),
          ],
        ),
      );
    }
    final now = (widget.now ?? DateTime.now)();
    final ids = widget.idChecks ? _rows('id_check') : const <Map<String, dynamic>>[];
    final cases = [
      for (final k in widget.kinds) ..._rows(k),
    ];
    if (widget.kinds.length > 1) {
      cases.sort(
        (a, b) => '${a['priority']}|${a['sla_due_at'] ?? '~'}'.compareTo(
          '${b['priority']}|${b['sla_due_at'] ?? '~'}',
        ),
      );
    }
    final capped = _kinds.any(_capped);
    return ListView(
      children: [
        if (failed != null) _retryFor(failed),
        if (capped)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ConsoleStatus(
              ConsoleLine(kConsoleQueueCapped),
              textKey: ValueKey('console_queue_capped'),
            ),
          ),
        if (said != null) said,
        if (ids.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Semantics(
              header: true,
              child: Text(
                kConsoleIdSection,
                key: const ValueKey('console_id_section'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          for (final c in ids) _row(c, now, idRow: true),
          if (cases.isNotEmpty) const Divider(height: 24),
        ],
        if (cases.isEmpty && ids.isEmpty && !capped)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Nothing is waiting.'),
          ),
        for (final c in cases) _row(c, now),
      ],
    );
  }

  /// A failed read: its line and Try again (invalid: this server doesn't
  /// know the list yet).
  Widget _retryFor(ConsoleAnswer failed) =>
      failed.reason == 'invalid'
          ? Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const ConsoleStatus(
                  ConsoleLine(kConsoleQueueInvalid, error: true),
                  textKey: ValueKey('console_queue_invalid'),
                ),
                OutlinedButton(
                  key: const ValueKey('console_retry'),
                  onPressed: _retry,
                  child: const Text('Try again'),
                ),
              ],
            ),
          )
          : Align(
            alignment: Alignment.topLeft,
            child: ConsoleRetry(answer: failed, onRetry: _retry),
          );

  Widget _row(Map<String, dynamic> c, DateTime now, {bool idRow = false}) {
    final id = ConsoleIdCheck.of(c['id_check']);
    final waiting = idRow || c['kind'] == 'id_check';
    return ListTile(
      key: ValueKey('console_${idRow ? 'id_' : ''}case_${c['id']}'),
      title: Text(
        [
          c['priority'],
          consoleCaseKind(c['kind']),
          c['category'] ?? c['signal_kind'],
        ].whereType<String>().join(' · '),
      ),
      subtitle: Text(
        [
          // Task 9 fix round 1 (owner): Ask for ID leaves it waiting; I-5
          // a closed No ID came case still needs the ID.
          // Round 3: an ID check waits, or (decided No ID came, its check
          // still live) still needs the ID.
          if (waiting)
            c['state'] == 'decided' || c['state'] == 'closed'
                ? 'ID still needed'
                : 'Waiting for ID',
          // I-6: the code the person's email gives.
          if (idRow && id.code != null) consoleIdCode(id.code!),
          // M-2: a waiting case has no clock (the server leaves it out of
          // the SLA): never "late".
          if (waiting)
            // Round 3: an ID check opens at Ask for ID.
            'asked for ID ${consoleDate(c['created_at'])}'
          else
            consoleDue(DateTime.tryParse('${c['sla_due_at']}'), now),
          if (c['reports'] is int && (c['reports'] as int) > 1)
            '${c['reports']} reports',
          if (c['mine'] == true)
            'yours'
          else if (c['claimed'] == true)
            'claimed',
          if (c['gone'] == true) 'account deleted',
        ].join(' · '),
      ),
      trailing:
          c['mine'] == true || c['state'] == 'decided'
              ? null
              : c['claimed'] == true
              ? TextButton(
                onPressed: _claiming ? null : () => _claim(c['id'].toString()),
                child: const Text('Take over'),
              )
              : TextButton(
                onPressed: _claiming ? null : () => _claim('${c['id']}'),
                child: const Text('Claim'),
              ),
      onTap: () => _open('${c['id']}'),
    );
  }
}
