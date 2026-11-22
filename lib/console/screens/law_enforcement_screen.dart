// Spec 2 W7c (§6.4 Law-enforcement log, §6.6): the safety owner's page.
// Every request is recorded as received, then decided (what was disclosed,
// whether the person was told); the quarterly transparency summary counts
// what fell in a window. A moderator sees only that the page is the safety
// owner's (the server refuses them anyway).
//
// Task 9 (Task 8 fix round 1's replies):
// - a request is an emergency or legal process (the summary counts both)
//   and carries the day it came (empty: now); one received time per
//   request however often Record is pressed, so a retry after busy is the
//   server's replay, never a second row; a recorded request clears the
//   form, and a form that isn't whole sends nothing;
// - exists (the same request, already logged with another decision) is
//   decided through the logged request's id;
// - a pending request waits for a decision to be picked; a disclosure needs
//   what was disclosed and can only be widened (already_disclosed); a
//   refusal or a contest sends no categories; a decided request opens with
//   its decision, so the notice alone can be added;
// - a window that isn't two days sends nothing; the counts are raw.
import 'dart:convert';

import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:flutter/material.dart';

/// What can be disclosed (the server's list).
const kConsoleDisclosed = [
  'account',
  'profile',
  'messages',
  'reports',
  'restrictions',
  'verification',
];

/// The decisions, as the console names them.
const kConsoleDecisions = {
  'refused': 'Refused',
  'contested': 'Contested',
  'disclosed': 'Disclosed',
  'partly_disclosed': 'Partly disclosed',
};

/// Spec 2 W7c Task 9 (Task 8 fix round 1, M-2): what a disclosure means.
const kConsoleDisclosureFinal =
    'Once recorded, a disclosure can only be widened, never narrowed or '
    'undone.';

/// A request the console can't record yet (nothing is sent).
const kConsoleRequestNotWhole =
    'Fill in the country (two letters, like GH), the legal basis and what is '
    'asked for. A received day, if any, is like 2026-11-20.';

/// A received day outside the log's range (review M-3).
const kConsoleReceivedRange =
    "The received day must be within the log's last 2 years, and no later "
    'than tomorrow.';

/// A transparency window the console can't send.
const kConsoleWindowDays =
    'Use two dates like 2026-07-01: from the first day, up to the day after '
    'the last.';

/// Said under a summary (Task 8 fix round 1: small-count suppression is
/// done before anything is published).
const kConsoleSummaryRaw =
    'These are raw counts. Suppress small counts before publishing them.';

final _day = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _country = RegExp(r'^[A-Za-z]{2}$');

/// A YYYY-MM-DD day that exists, at midnight UTC; null otherwise.
DateTime? _dayOf(String text) {
  if (!_day.hasMatch(text)) return null;
  final d = DateTime.tryParse('${text}T00:00:00Z');
  return d != null && d.toIso8601String().startsWith(text) ? d : null;
}

/// The log's range for a received day (server M-7: not past its 2 years,
/// not more than a day ahead), kept a day inside on each side.
bool _inRange(DateTime day) {
  final now = DateTime.now().toUtc();
  final today = DateTime.utc(now.year, now.month, now.day);
  return !day.isAfter(today.add(const Duration(days: 1))) &&
      !day.isBefore(DateTime.utc(now.year - 2, now.month, now.day + 1));
}

bool _disclosure(String? decision) =>
    decision == 'disclosed' || decision == 'partly_disclosed';

class LawEnforcementScreen extends StatefulWidget {
  const LawEnforcementScreen({super.key, required this.api, required this.me});

  final ConsoleApi api;
  final ConsoleMe me;

  @override
  State<LawEnforcementScreen> createState() => _LawEnforcementScreenState();
}

class _LawEnforcementScreenState extends State<LawEnforcementScreen> {
  ConsoleAnswer? _read;
  ConsoleAnswer? _summary;
  ConsoleLine? _line;
  ConsoleLine? _summaryLine;

  /// The request the log already holds (exists): decided through its id.
  String? _existsId;
  bool _busy = false;
  bool _counting = false;
  bool _emergency = false;

  /// One received time per request, however often Record is pressed.
  /// Fix round 1 (review M-1, M-2): a typed day keeps this time of day, so
  /// two requests on one day stay two; a changed request takes a new one.
  DateTime? _receivedAt;
  String? _receivedFor;
  final _jurisdiction = TextEditingController();
  final _basis = TextEditingController();
  final _scope = TextEditingController();
  final _received = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();

  List<TextEditingController> get _form => [
    _jurisdiction,
    _basis,
    _scope,
    _received,
  ];

  @override
  void initState() {
    super.initState();
    if (widget.me.owner) _load();
  }

  @override
  void dispose() {
    for (final c in [..._form, _from, _to]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _whole =>
      _country.hasMatch(_jurisdiction.text.trim()) &&
      _basis.text.trim().isNotEmpty &&
      _scope.text.trim().isNotEmpty &&
      (_received.text.trim().isEmpty || _dayOf(_received.text.trim()) != null);

  Future<void> _load() async {
    final r = await widget.api('le_requests');
    if (mounted) setState(() => _read = r);
  }

  Future<ConsoleAnswer> _record(String? id, Map<String, Object?> values) async {
    setState(() {
      _busy = true;
      _line = null;
      _existsId = null;
    });
    final r = await widget.api('le_record', {
      if (id != null) 'request_id': id,
      'values': values,
    });
    if (!mounted) return r;
    setState(() {
      _busy = false;
      _line = r.ok ? const ConsoleLine('Recorded.') : ConsoleLine.of(r);
      if (r.data['id'] case final String logged when r.reason == 'exists') {
        _existsId = logged;
      }
    });
    await _load();
    return r;
  }

  Future<void> _create() async {
    final day = _dayOf(_received.text.trim());
    final refused =
        !_whole
            ? kConsoleRequestNotWhole
            : day != null && !_inRange(day)
            ? kConsoleReceivedRange
            : null;
    if (refused != null) {
      setState(() {
        _existsId = null;
        _line = ConsoleLine(refused, error: true);
      });
      return;
    }
    final identity = [
      for (final c in _form) c.text.trim(),
      _emergency,
    ].join('|');
    if (identity != _receivedFor) {
      _receivedAt = null;
      _receivedFor = identity;
    }
    final at = _receivedAt ??= DateTime.now().toUtc();
    final received =
        day == null
            ? at
            : DateTime.utc(
              day.year,
              day.month,
              day.day,
              at.hour,
              at.minute,
              at.second,
              at.millisecond,
              at.microsecond,
            );
    final r = await _record(null, {
      'received_at': received.toIso8601String(),
      'jurisdiction': _jurisdiction.text.trim().toUpperCase(),
      'legal_basis': _basis.text.trim(),
      'scope': _scope.text.trim(),
      'emergency': _emergency,
    });
    if (!r.ok || !mounted) return;
    setState(() {
      _receivedAt = null;
      _receivedFor = null;
      _emergency = false;
      for (final c in _form) {
        c.clear();
      }
    });
  }

  Map<String, dynamic>? _row(String id) => _read
      ?.list('requests')
      .firstWhere((r) => r['id'] == id, orElse: () => const {});

  Future<void> _decide(String id) async {
    final row = _row(id);
    final chosen = await showDialog<Map<String, Object?>>(
      context: context,
      builder:
          (context) =>
              _DecideDialog(row: row == null || row.isEmpty ? null : row),
    );
    if (chosen != null) await _record(id, chosen);
  }

  Future<void> _transparency() async {
    final from = _from.text.trim();
    final to = _to.text.trim();
    if (_dayOf(from) == null || _dayOf(to) == null) {
      setState(() {
        _summary = null;
        _summaryLine = const ConsoleLine(kConsoleWindowDays, error: true);
      });
      return;
    }
    setState(() {
      _counting = true;
      _summaryLine = null;
    });
    final r = await widget.api('transparency', {'from': from, 'to': to});
    if (!mounted) return;
    setState(() {
      _counting = false;
      _summary = r;
      _summaryLine =
          r.ok
              ? null
              : r.reason == 'invalid'
              ? const ConsoleLine(
                'The window must end after it starts, and be at most 366 '
                'days.',
                error: true,
              )
              : ConsoleLine.of(r);
    });
  }

  Widget _field(
    String key,
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) => consoleField(
    key: ValueKey(key),
    controller: controller,
    label: label,
    maxLines: maxLines,
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.me.owner) {
      return const Center(
        child: Text('The law-enforcement log is the safety owner\'s.'),
      );
    }
    final read = _read;
    final summary = _summary;
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Semantics(
        header: true,
        child: Text(text, style: theme.textTheme.titleMedium),
      ),
    );
    return ConsoleFrame(
      title: 'Law-enforcement log',
      onRefresh: read == null ? null : _load,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_line case final line?)
              Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConsoleStatus(
                    line,
                    textKey: const ValueKey('console_le_line'),
                  ),
                  if (_existsId case final id?)
                    TextButton(
                      key: const ValueKey('console_le_exists_decide'),
                      onPressed: _busy ? null : () => _decide(id),
                      child: const Text('Decide it'),
                    ),
                ],
              ),
            heading('Record a request'),
            _field('console_le_jurisdiction', _jurisdiction, 'Country (GH)'),
            _field('console_le_basis', _basis, 'Legal basis'),
            _field('console_le_scope', _scope, 'What is asked for'),
            _field(
              'console_le_received',
              _received,
              'Received on (2026-11-20; empty for now)',
            ),
            CheckboxListTile(
              key: const ValueKey('console_le_emergency'),
              value: _emergency,
              contentPadding: EdgeInsets.zero,
              title: const Text('Emergency request (no legal process yet)'),
              onChanged: (v) => setState(() => _emergency = v ?? false),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: const ValueKey('console_le_record'),
                onPressed: _busy ? null : _create,
                child: const Text('Record'),
              ),
            ),
            const Divider(height: 32),
            Semantics(
              header: true,
              child: Text('The log', style: theme.textTheme.titleMedium),
            ),
            switch (read) {
              null => const ConsoleLoading('Loading the log.'),
              ConsoleAnswer(ok: false) => ConsoleRetry(
                answer: read,
                onRetry: () {
                  setState(() => _read = null);
                  _load();
                },
              ),
              _ when read.list('requests').isEmpty => const Text(
                'No request is logged yet.',
              ),
              _ => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final r in read.list('requests'))
                    ListTile(
                      key: ValueKey('console_le_${r['id']}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${r['jurisdiction']} · '
                        '${kConsoleDecisions[r['decision']] ?? r['decision']}'
                        ' · received ${consoleDate(r['received_at'])}',
                      ),
                      subtitle: Text(
                        [
                          '${r['legal_basis']}',
                          '${r['scope']}',
                          if (r['emergency'] == true) 'emergency',
                          if ((r['disclosed_categories'] as List? ?? const [])
                              .isNotEmpty)
                            'disclosed: '
                                '${(r['disclosed_categories'] as List).join(', ')}',
                          if (r['user_notified_at'] != null)
                            'person told ${consoleDate(r['user_notified_at'])}',
                        ].join(' · '),
                      ),
                      trailing: TextButton(
                        onPressed: _busy ? null : () => _decide('${r['id']}'),
                        child: const Text('Decide'),
                      ),
                    ),
                ],
              ),
            },
            const Divider(height: 32),
            heading('Transparency summary'),
            _field('console_le_from', _from, 'From (2026-07-01)'),
            _field('console_le_to', _to, 'Up to, not including (2026-10-01)'),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: const ValueKey('console_le_summary'),
                onPressed: _counting ? null : _transparency,
                child: const Text('Count'),
              ),
            ),
            if (_summaryLine case final line?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ConsoleStatus(line),
              ),
            if (summary != null && summary.ok) ...[
              const SizedBox(height: 8),
              SelectableText(
                const JsonEncoder.withIndent(
                  '  ',
                ).convert(summary.data['summary']),
                key: const ValueKey('console_le_summary_text'),
              ),
              const Text(kConsoleSummaryRaw),
            ],
          ],
        ),
      ),
    );
  }
}

/// A request's decision: what was disclosed, and whether the person was
/// told. A pending request waits for a pick; a decided one opens as it is.
class _DecideDialog extends StatefulWidget {
  const _DecideDialog({this.row});

  /// The request as the log read it (null: not in the last read).
  final Map<String, dynamic>? row;

  @override
  State<_DecideDialog> createState() => _DecideDialogState();
}

class _DecideDialogState extends State<_DecideDialog> {
  late String? _decision =
      kConsoleDecisions.containsKey(widget.row?['decision'])
          ? widget.row!['decision'] as String
          : null;
  late final _disclosed = <String>{
    for (final c in (widget.row?['disclosed_categories'] as List? ?? const []))
      if (kConsoleDisclosed.contains(c)) c as String,
  };
  late final bool _toldAlready = widget.row?['user_notified_at'] != null;
  late bool _told = _toldAlready;

  bool get _ready =>
      _decision != null && (!_disclosure(_decision) || _disclosed.isNotEmpty);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Decide'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButton<String>(
              key: const ValueKey('console_le_decision'),
              value: _decision,
              isExpanded: true,
              hint: const Text('Pick a decision'),
              items: [
                for (final MapEntry(:key, :value) in kConsoleDecisions.entries)
                  DropdownMenuItem(value: key, child: Text(value)),
              ],
              onChanged: (v) => setState(() => _decision = v ?? _decision),
            ),
            if (_disclosure(_decision)) ...[
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(kConsoleDisclosureFinal),
              ),
              for (final c in kConsoleDisclosed)
                CheckboxListTile(
                  key: ValueKey('console_le_disclosed_$c'),
                  value: _disclosed.contains(c),
                  title: Text(c),
                  onChanged:
                      (v) => setState(
                        () =>
                            v == true
                                ? _disclosed.add(c)
                                : _disclosed.remove(c),
                      ),
                ),
            ],
            CheckboxListTile(
              key: const ValueKey('console_le_told'),
              value: _told,
              title: Text(
                _toldAlready
                    ? 'The person was told '
                        '(${consoleDate(widget.row?['user_notified_at'])})'
                    : 'The person was told',
              ),
              onChanged:
                  _toldAlready
                      ? null
                      : (v) => setState(() => _told = v ?? false),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('console_le_decide_save'),
        onPressed:
            _ready
                ? () => Navigator.of(context).pop(<String, Object?>{
                  'decision': _decision,
                  'disclosed_categories': [
                    if (_disclosure(_decision))
                      for (final c in kConsoleDisclosed)
                        if (_disclosed.contains(c)) c,
                  ],
                  'user_notified': _told,
                })
                : null,
        child: const Text('Save'),
      ),
    ],
  );
}
