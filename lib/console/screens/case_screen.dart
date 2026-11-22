// Spec 2 W7b (§6.4 Case, Appeals; §6.2, §6.3): one case as the server
// gives it: its reports (the text, the credibility note, the evidence),
// the person as others see them, prior cases, the safety families by name,
// an appeal's restriction. The actions: claim, dismiss, hold, lift a hold,
// restrict, ask for ID, confirm a minor (an underage_risk case), a note,
// and an appeal's accept or reject. Every action is the server's to allow;
// the page reads the case again after each. Never the reporter, never a
// special-category answer, never CSAM (the server sends none of them).
//
// Task 7: a refused case (missing, or one the moderator is a party to:
// the same code) reads the same and offers no retry; busy and offline are
// calm and keep the last read on screen; an appeal says who may decide it
// (the original decider, or nobody recorded: decider_unknown); a note is
// counted in code points, as the server counts it. No action here removes
// a delivered message.
//
// Fix round 1 (task-7-review.md): Dismiss, Confirm a minor and an appeal's
// Accept or Reject wait for a confirm naming the consequence (I-1); the
// Restrict category starts as the case's leading report category, or
// waits for a pick, never a guess (I-3); the case is built whole, not
// lazily, so its signed photos load inside their minute (M-2).
//
// Spec 2 W7c Task 9: Record an escalation (a record, never a send; CSA 292
// only as its own consent kind), and the case's escalations listed with
// each read (the reference only when the server gives it: the owner's and
// the recorder's). Console round 3: Ask for ID and Lift hold confirm; a
// decided case can still lift what it placed (an age check once support
// has seen the ID, R-56); no line assumes one hold per person (a report's
// hold and a CSAM hold can both be live, Task 8 fix round 1).
import 'dart:async';

import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// §3.7's categories, in the console's order (a hold's or a restriction's).
const kConsoleCategories = [
  'underage_risk',
  'csam',
  'child_safety',
  'threat_to_life',
  'sextortion',
  'romance_scam',
  'threats',
  'entrapment',
  'harassment',
  'explicit_content',
  'impersonation',
  'hiding_relationship',
  'spam',
  'other',
];

/// Spec 2 W7c Task 9: a case's escalations that couldn't be read.
const kConsoleEscalationsUnread =
    "Couldn't read this case's escalations. Read again.";

/// Said in the escalation dialog: a record, never a send (§6.5).
const kConsoleEscalationRecordOnly =
    'This records what was reported, and where. The console sends nothing '
    'to anyone.';

/// §6.5's kinds, as the console names them.
const kConsoleEscalationKinds = {
  'police': 'Police',
  'ncmec': 'NCMEC',
  'iwf': 'IWF',
  'csa': 'Cyber Security Authority',
  'csa_292_with_consent': "CSA 292, with the person's consent",
};

/// An escalation's reference, at most this many code points (the server's).
const kConsoleReferenceLimit = 200;

/// Said when the consent kind is picked (§6.5, review M-4).
const kConsoleConsentOnly =
    'Record this only if the person agreed to the report. If they '
    "didn't, don't record it: add a note instead.";

/// A note's most, in code points (the server's char_length).
const kConsoleNoteLimit = 1000;

/// Keeps a field to [limit] code points, cutting only between characters.
class ConsoleCodePointLimit extends TextInputFormatter {
  const ConsoleCodePointLimit(this.limit);

  final int limit;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.runes.length <= limit) return newValue;
    if (oldValue.text.runes.length >= limit) return oldValue;
    final kept = StringBuffer();
    var n = 0;
    for (final c in newValue.text.characters) {
      final r = c.runes.length;
      if (n + r > limit) break;
      kept.write(c);
      n += r;
    }
    final text = kept.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// What an action's answer says. Fix round 1 (I-1): a decision that ends
/// holds says the other holds stay; Ask for ID says the case waits.
ConsoleLine consoleActionLine(
  String action,
  ConsoleAnswer r, {
  bool accepted = false,
}) {
  if (!r.ok) return ConsoleLine.of(r);
  if (r.data['took_over'] == true) {
    return const ConsoleLine('You took this case over from another moderator.');
  }
  if ((action == 'lift_hold' || action == 'lift_case_holds') &&
      r.data['lifted'] is int) {
    final n = r.data['lifted'] as int;
    // Task 9: only this case's own; another hold may still be live.
    final lifted = switch (n) {
      0 => 'This case had no hold to lift.',
      1 => "Lifted this case's hold.",
      _ => "Lifted $n of this case's holds.",
    };
    return ConsoleLine('$lifted $kConsoleOtherHolds');
  }
  if (action == 'dismiss') {
    return const ConsoleLine('Dismissed. $kConsoleOtherHolds');
  }
  if (action == 'decide_appeal' && accepted) {
    return const ConsoleLine('Accepted. $kConsoleOtherHolds');
  }
  if (action == 'ask_for_id') return const ConsoleLine(kConsoleAskedForId);
  if (action == 'close_no_id') return const ConsoleLine(kConsoleClosedNoId);
  return const ConsoleLine('Done.');
}

/// A case's state as the console says it (awaiting_id: waiting for ID).
String? consoleCaseState(Object? state) => switch (state) {
  'awaiting_id' => 'waiting for ID',
  final String s => s,
  _ => null,
};

/// A case's kind as the console says it (server round 3: id_check is "ID
/// check"; the others are their own names).
String? consoleCaseKind(Object? kind) => switch (kind) {
  'id_check' => 'ID check',
  final String k => k,
  _ => null,
};

/// A case's outcome as the console says it (id_verified: the ID showed an
/// adult, the server's awaiting_id path).
String? consoleCaseOutcome(Object? outcome) => switch (outcome) {
  'id_verified' => 'ID checked: an adult',
  'no_id_received' => 'Closed: no ID came',
  // Round 3: the age reports moved to an ID check and nothing else was open.
  'asked_for_id' => 'Asked for ID: moved to an ID check',
  final String o => o,
  _ => null,
};

/// One recorded escalation: its kind, when, by whom, and the reference
/// when the server gave it (the owner's and the recorder's alone).
String consoleEscalationLine(Map<String, dynamic> e) => [
  kConsoleEscalationKinds[e['kind']] ?? '${e['kind']}',
  'recorded ${consoleDate(e['recorded_at'])}',
  if (e['mine'] == true) 'by you',
  if (e['reference'] case final String ref when ref.isNotEmpty)
    'their reference: $ref',
].join(' · ');

/// W7 final client fix (I-5): the case's ID check as the server reads it
/// (`id_check {state, restriction_live, code}`). The ID actions key on
/// [live] (the age check Ask for ID wrote for this case), never on the
/// case's state, so a joining report or No ID came never strands them.
class ConsoleIdCheck {
  const ConsoleIdCheck({this.live = false, this.state, this.code});

  factory ConsoleIdCheck.of(Object? raw) {
    if (raw is! Map || raw['restriction_live'] != true) {
      return const ConsoleIdCheck();
    }
    final code = raw['code'];
    return ConsoleIdCheck(
      live: true,
      // Server round 2: the state derives from the ID track's own outcome.
      state:
          raw['state'] == 'no_id' || raw['outcome'] == 'no_id_received'
              ? 'no_id'
              : 'awaiting',
      code: code is String && code.isNotEmpty ? code : null,
    );
  }

  final bool live;

  /// 'awaiting' (waiting for the ID) or 'no_id' (No ID came recorded: ID
  /// still needed; server round 2: the case may still be open for its
  /// other reports); null when nothing is live.
  final String? state;

  /// I-6: the reference code the person's email gives.
  final String? code;

  bool get stillNeeded => state == 'no_id';
}

/// M-8: an appeal this moderator may not decide now, and why (null: they
/// may). The original decider never; nobody recorded, only the safety
/// owner; either way the owner from 24 hours after it was sent. The
/// server stays the judge.
String? consoleAppealBlocked(
  Map<String, dynamic>? appeal,
  Map<String, dynamic>? restriction,
  ConsoleMe me,
  DateTime now,
) {
  final mine = restriction?['decided_by_me'] == true;
  final unknown = restriction?['decider_known'] == false;
  if (!mine && !unknown) return null;
  final sent = DateTime.tryParse('${appeal?['submitted_at']}')?.toUtc();
  final from = sent?.add(const Duration(hours: 24));
  if (me.owner && from != null && !now.toUtc().isBefore(from)) return null;
  if (me.owner && from != null) {
    return 'You can decide it from ${consoleDate(from.toIso8601String())}.';
  }
  return consoleReason(unknown ? 'decider_unknown' : 'same_decider');
}

class CaseScreen extends StatefulWidget {
  const CaseScreen({
    super.key,
    required this.api,
    required this.me,
    required this.caseId,
    this.now,
  });

  final ConsoleApi api;
  final ConsoleMe me;
  final String caseId;

  /// The clock (M-8: an owner's 24 hours); tests set it.
  final DateTime Function()? now;

  @override
  State<CaseScreen> createState() => _CaseScreenState();
}

class _CaseScreenState extends State<CaseScreen> {
  /// The latest read, and the latest that worked (kept on screen when a
  /// read again is busy or offline).
  ConsoleAnswer? _read;
  ConsoleAnswer? _good;

  /// The case's escalations (Task 9), read with the case.
  ConsoleAnswer? _escalations;
  ConsoleLine? _line;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final params = {'case_id': widget.caseId};
    final (r, e) =
        await (
          widget.api('case', params),
          widget.api('case_escalations', params),
        ).wait;
    if (!mounted) return;
    setState(() {
      _read = r;
      if (r.ok) _good = r;
      _escalations = e;
    });
  }

  Future<void> _act(
    String action, [
    Map<String, Object?> extra = const {},
  ]) async {
    setState(() {
      _busy = true;
      _line = null;
    });
    final r = await widget.api(action, {'case_id': widget.caseId, ...extra});
    if (!mounted) return;
    setState(() {
      _busy = false;
      _line = consoleActionLine(action, r, accepted: extra['accept'] == true);
    });
    await _load();
  }

  Future<String?> _pickCategory(String title) => showDialog<String>(
    context: context,
    builder:
        (context) => SimpleDialog(
          title: Text(title),
          children: [
            for (final c in kConsoleCategories)
              SimpleDialogOption(
                key: ValueKey('console_category_$c'),
                onPressed: () => Navigator.of(context).pop(c),
                child: Text(c),
              ),
          ],
        ),
  );

  Future<void> _hold() async {
    final c = await _pickCategory('Hold: category');
    if (c != null) await _act('hold', {'category': c});
  }

  /// Asks first, then acts: an irreversible decision (I-1).
  Future<bool> _sure(String title, String consequence, String confirm) =>
      consoleConfirm(
        context,
        title: title,
        consequence: consequence,
        confirm: confirm,
      );

  Future<void> _dismiss(String consequence) async {
    if (!await _sure('Dismiss this case?', consequence, 'Dismiss')) return;
    await _act('dismiss');
  }

  /// Server round 2: an open case's own holds (never the asked check).
  Future<void> _liftCaseHolds(String consequence) async {
    if (!await _sure("Lift the case's holds?", consequence, kConsoleLiftCaseHolds)) {
      return;
    }
    await _act('lift_case_holds');
  }

  Future<void> _askForId() async {
    if (!await _sure(
      'Ask for ID for an age check?',
      kConfirmCaseAskForId,
      kConsoleAskIdAgeCheck,
    )) {
      return;
    }
    await _act('ask_for_id');
  }

  Future<void> _liftHold(String consequence) async {
    if (!await _sure(
      '$kConsoleLiftAgeCheck?',
      consequence,
      kConsoleLiftAgeCheck,
    )) {
      return;
    }
    await _act('lift_hold');
  }

  /// Round 3: a case's ID check, or the case an ID check came from.
  Widget _link(String label, String key, String caseId) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton(
      key: ValueKey(key),
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      onPressed:
          () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder:
                  (_) => CaseScreen(
                    api: widget.api,
                    me: widget.me,
                    caseId: caseId,
                    now: widget.now,
                  ),
            ),
          ),
      child: Text(label),
    ),
  );

  Future<void> _closeNoId(String consequence) async {
    if (!await _sure('No ID came?', consequence, 'No ID came')) return;
    await _act('close_no_id');
  }

  Future<void> _confirmMinor(String consequence) async {
    if (!await _sure('Confirm a minor?', consequence, 'Confirm a minor')) {
      return;
    }
    await _act('confirm_minor');
  }

  Future<void> _decide(bool accept) async {
    final sure =
        accept
            ? await _sure('Accept the appeal?', kConfirmAccept, 'Accept')
            : await _sure('Reject the appeal?', kConfirmReject, 'Reject');
    if (!sure) return;
    await _act('decide_appeal', {'accept': accept});
  }

  Future<void> _restrict(String? lead) async {
    final chosen = await showDialog<(String, int?, String)>(
      context: context,
      builder: (context) => _RestrictDialog(category: lead),
    );
    if (chosen == null) return;
    final (type, days, category) = chosen;
    await _act('restrict', {
      'type': type,
      'category': category,
      'ends_at':
          days == null
              ? null
              : DateTime.now()
                  .toUtc()
                  .add(Duration(days: days))
                  .toIso8601String(),
    });
  }

  /// Spec 2 W7c (§6.5): what a person did, recorded; never a send.
  Future<void> _escalate() async {
    final chosen = await showDialog<(String, String)>(
      context: context,
      builder: (context) => const _EscalationDialog(),
    );
    if (chosen == null) return;
    final (kind, reference) = chosen;
    await _act('escalate', {
      'kind': kind,
      if (reference.trim().isNotEmpty) 'reference': reference.trim(),
    });
  }

  Future<void> _note() async {
    final note = await showDialog<String>(
      context: context,
      builder: (context) => const _NoteDialog(),
    );
    if (note != null && note.trim().isNotEmpty) {
      await _act('note', {'note': note});
    }
  }

  @override
  Widget build(BuildContext context) {
    final read = _read;
    final good = _good;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Case'),
        actions: [
          IconButton(
            key: const ValueKey('console_refresh'),
            tooltip: 'Read again',
            onPressed: read == null || _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: switch (read) {
        null => const ConsoleLoading('Loading the case.'),
        ConsoleAnswer(ok: false, reason: 'case_unavailable') => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                consoleReason(read.reason),
                key: const ValueKey('console_case_refused'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const ValueKey('console_back_to_queue'),
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Back to the queue'),
              ),
            ],
          ),
        ),
        ConsoleAnswer(ok: false) when good == null => Align(
          alignment: Alignment.topCenter,
          child: ConsoleRetry(
            answer: read,
            onRetry: () {
              setState(() => _read = null);
              _load();
            },
          ),
        ),
        _ => _case(context, (good ?? read).data, stale: read.ok ? null : read),
      },
    );
  }

  Widget _case(
    BuildContext context,
    Map<String, dynamic> data, {
    ConsoleAnswer? stale,
  }) {
    final theme = Theme.of(context);
    final c = Map<String, dynamic>.from(data['case'] as Map? ?? const {});
    final reports = [
      for (final r in (data['reports'] as List? ?? const []))
        if (r is Map) Map<String, dynamic>.from(r),
    ];
    final profile =
        data['profile'] is Map
            ? Map<String, dynamic>.from(data['profile'] as Map)
            : null;
    final appeal =
        data['appeal'] is Map
            ? Map<String, dynamic>.from(data['appeal'] as Map)
            : null;
    final restriction =
        appeal?['restriction'] is Map
            ? Map<String, dynamic>.from(appeal!['restriction'] as Map)
            : null;
    final appealCase = c['kind'] == 'appeal';
    // W7 final client fix (server round 3): the ID check is its own case
    // (kind id_check). It holds the moved age reports and the asked age
    // check, and allows only its four actions; an ordinary case's Dismiss,
    // Confirm a minor and Lift the case's holds are plain again.
    final idCase = c['kind'] == 'id_check';
    final id = idCase ? ConsoleIdCheck.of(c['id_check']) : const ConsoleIdCheck();
    final open =
        c['state'] == 'open' ||
        c['state'] == 'in_review' ||
        (idCase && c['state'] == 'awaiting_id');
    final escalations = _escalations;
    final underage = reports.any(
      (r) =>
          r['category'] == 'underage_risk' &&
          (r['state'] == 'open' || r['state'] == 'in_review'),
    );
    final ordinary = !appealCase && !idCase;
    // On an ID check: the age check lifts while it is live (a late ID on
    // a decided No ID came check too); Confirm a minor while it is open or
    // its check is live; No ID came and Dismiss (asked by mistake) while it
    // is open.
    // Server round 4: an orphaned ID check (the person deleted their
    // account) offers only No ID came.
    final orphan = idCase && c['gone'] == true;
    final liftCopy =
        idCase && id.live && !orphan
            ? (open ? kConfirmLiftAgeCheck : kConfirmLiftIdDecided)
            : null;
    final caseHoldsCopy =
        ordinary && open
            ? (underage ? kConfirmLiftCaseHoldsUnderage : kConfirmLiftCaseHolds)
            : null;
    final minorCopy =
        idCase && (open || id.live) && !orphan
            ? kConfirmMinorIdCheck
            : ordinary && open && underage
            ? kConfirmMinor
            : null;
    final noId = idCase && open && (id.live || orphan);
    final idDismiss = idCase && open && !orphan;
    final appealBlocked =
        open && appealCase
            ? consoleAppealBlocked(
              appeal,
              restriction,
              widget.me,
              (widget.now ?? DateTime.now)(),
            )
            : null;
    // The leading report's category (by priority, then the earliest): what
    // the person is told and what their one appeal answers (I-3).
    final lead =
        ([...reports]..sort(
              (a, b) => '${a['priority']}${a['created_at']}'.compareTo(
                '${b['priority']}${b['created_at']}',
              ),
            ))
            .map((r) => r['category'])
            .whereType<String>()
            .where(kConsoleCategories.contains)
            .firstOrNull;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Semantics(
        header: true,
        child: Text(text, style: theme.textTheme.titleMedium),
      ),
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kConsoleMaxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stale != null)
                ConsoleRetry(
                  answer: stale,
                  onRetry: () {
                    _load();
                  },
                ),
              Semantics(
                header: true,
                child: Text(
                  [
                    c['priority'],
                    consoleCaseKind(c['kind']),
                    consoleCaseState(c['state']),
                    c['signal_kind'],
                    consoleCaseOutcome(c['outcome']),
                  ].whereType<String>().join(' · '),
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (c['sla_due_at'] is String)
                Text(
                  'Due ${consoleDate(c['sla_due_at'])} · opened '
                  '${consoleDate(c['created_at'])}',
                ),
              if (c['gone'] == true) const Text('The account was deleted.'),
              // I-6: the code the person's ID email gives, to find with.
              if (id.code case final code?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SelectableText(
                    consoleIdCode(code),
                    key: const ValueKey('console_id_code'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              if (id.live)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    id.stillNeeded
                        ? kConsoleIdStillNeededNote
                        : kConsoleAwaitingIdNote,
                    key: const ValueKey('console_id_note'),
                  ),
                ),
              // Round 3: an ID check and the case it came from link to
              // each other.
              if (c['origin_case'] case final String origin when idCase)
                _link(kConsoleOpenOrigin, 'console_origin_case', origin),
              if (c['id_case'] case final String idCaseId when !idCase)
                _link(kConsoleOpenIdCase, 'console_id_case', idCaseId),
              if (_line case final line?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ConsoleStatus(
                    line,
                    textKey: const ValueKey('console_case_line'),
                  ),
                ),
              if (reports.isNotEmpty) heading('Reports'),
              for (final r in reports)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${r['priority']} · ${r['category']} · ${r['state']}',
                        ),
                        if (r['details'] is String) Text('"${r['details']}"'),
                        if (r['reporter_triggered'] is String)
                          Text(
                            "The reporter's messages in this chat triggered: ${r['reporter_triggered']}",
                            key: ValueKey('console_credibility_${r['id']}'),
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        if (r['evidence'] is List)
                          ExpansionTile(
                            title: Text(
                              'Evidence (${(r['evidence'] as List).length} messages)',
                            ),
                            children: [
                              for (final m
                                  in (r['evidence'] as List).whereType<Map>())
                                ListTile(
                                  dense: true,
                                  title: SelectableText('${m['text']}'),
                                  subtitle: Text(
                                    '${m['from']} · ${consoleDate(m['at'])}',
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              if (profile != null) ...[
                heading('As others see them'),
                Text(
                  [
                    profile['display_name'],
                    profile['age'],
                    profile['country'],
                    profile['region'],
                  ].where((v) => v != null).join(' · '),
                ),
                for (final p
                    in (profile['prompts'] as List? ?? const [])
                        .whereType<Map>())
                  Text('${p['prompt']}: ${p['answer']}'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p
                        in (profile['photos'] as List? ?? const [])
                            .whereType<Map>())
                      consoleImage(p['url'], 'Photo ${p['position']}'),
                  ],
                ),
              ],
              if ((data['families'] as List? ?? const []).isNotEmpty) ...[
                heading('Safety families in the chat'),
                Text((data['families'] as List).join(', ')),
              ],
              if ((data['prior'] as List? ?? const []).isNotEmpty) ...[
                heading('Earlier cases (this account or number)'),
                for (final p in (data['prior'] as List).whereType<Map>())
                  Text(
                    '${consoleCaseKind(p['kind'])} · ${consoleCaseState(p['state'])} · ${consoleCaseOutcome(p['outcome']) ?? '-'} · ${consoleDate(p['created_at'])}',
                  ),
              ],
              if (appeal != null) ...[
                heading('Appeal'),
                Text(
                  appeal['text'] is String ? '"${appeal['text']}"' : 'No text.',
                ),
                if (appeal['submitted_at'] is String)
                  Text('Sent ${consoleDate(appeal['submitted_at'])}'),
                if (restriction != null)
                  Text(
                    'Restriction: ${restriction['type']} · '
                    '${restriction['category']} · '
                    'until ${restriction['ends_at'] == null ? 'closed for good' : consoleDate(restriction['ends_at'])}',
                  ),
                if (restriction?['decider_known'] == false)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      consoleReason('decider_unknown'),
                      key: const ValueKey('console_decider_unknown'),
                    ),
                  ),
                if (restriction?['decided_by_me'] == true) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'You made the original decision, so a different person '
                      'must decide this appeal.',
                    ),
                  ),
                  if (widget.me.owner)
                    const Text(
                      'As the safety owner, you can decide it from 24 hours '
                      'after it was sent.',
                    ),
                ],
                // M-8: Accept and Reject are off; the lines above say why,
                // and the owner reads from when.
                if (appealBlocked != null && widget.me.owner)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      appealBlocked,
                      key: const ValueKey('console_appeal_blocked'),
                      style: TextStyle(color: theme.colorScheme.onSurface),
                    ),
                  ),
              ],
              heading('Escalations recorded'),
              switch (escalations) {
                null => const SizedBox.shrink(),
                ConsoleAnswer(ok: false) => Text(
                  kConsoleEscalationsUnread,
                  key: const ValueKey('console_escalations_unread'),
                ),
                _ when escalations.list('escalations').isEmpty => const Text(
                  'None recorded.',
                ),
                _ => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in escalations.list('escalations'))
                      SelectableText(consoleEscalationLine(e)),
                  ],
                ),
              },
              heading('Actions'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (open && !appealCase && c['mine'] != true)
                    OutlinedButton(
                      key: const ValueKey('console_claim'),
                      onPressed: _busy ? null : () => _act('claim'),
                      child: const Text('Claim'),
                    ),
                  if (ordinary && open) ...[
                    OutlinedButton(
                      key: const ValueKey('console_dismiss'),
                      onPressed: _busy ? null : () => _dismiss(kConfirmDismiss),
                      child: const Text('Dismiss'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('console_hold'),
                      onPressed: _busy ? null : _hold,
                      child: const Text('Hold'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('console_restrict'),
                      onPressed: _busy ? null : () => _restrict(lead),
                      child: const Text('Restrict'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('console_ask_id'),
                      onPressed: _busy ? null : _askForId,
                      child: const Text(kConsoleAskIdAgeCheck),
                    ),
                  ],
                  if (liftCopy != null)
                    OutlinedButton(
                      key: const ValueKey('console_lift_hold'),
                      onPressed: _busy ? null : () => _liftHold(liftCopy),
                      child: const Text(kConsoleLiftAgeCheck),
                    ),
                  if (minorCopy != null)
                    OutlinedButton(
                      key: const ValueKey('console_minor'),
                      onPressed: _busy ? null : () => _confirmMinor(minorCopy),
                      child: const Text('Confirm a minor'),
                    ),
                  if (noId)
                    OutlinedButton(
                      key: const ValueKey('console_no_id'),
                      onPressed:
                          _busy
                              ? null
                              : () => _closeNoId(
                                orphan ? kConfirmNoIdGone : kConfirmNoId,
                              ),
                      child: const Text('No ID came'),
                    ),
                  if (idDismiss)
                    OutlinedButton(
                      key: const ValueKey('console_dismiss'),
                      onPressed:
                          _busy ? null : () => _dismiss(kConfirmDismissIdCheck),
                      child: const Text(kConsoleDismissIdCheck),
                    ),
                  if (caseHoldsCopy != null)
                    OutlinedButton(
                      key: const ValueKey('console_lift_case_holds'),
                      onPressed:
                          _busy ? null : () => _liftCaseHolds(caseHoldsCopy),
                      child: const Text(kConsoleLiftCaseHolds),
                    ),
                  if (open && appealCase) ...[
                    FilledButton(
                      key: const ValueKey('console_appeal_accept'),
                      onPressed:
                          _busy || appealBlocked != null
                              ? null
                              : () => _decide(true),
                      child: const Text('Accept appeal'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('console_appeal_reject'),
                      onPressed:
                          _busy || appealBlocked != null
                              ? null
                              : () => _decide(false),
                      child: const Text('Reject appeal'),
                    ),
                  ],
                  OutlinedButton(
                    key: const ValueKey('console_add_note'),
                    onPressed: _busy ? null : _note,
                    child: const Text('Add a note'),
                  ),
                  OutlinedButton(
                    key: const ValueKey('console_escalate'),
                    onPressed: _busy ? null : _escalate,
                    child: const Text('Record an escalation'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// M-11: what a restriction of [type] for [days] (null: for good) does.
String consoleRestrictConsequence(String type, int? days) => switch ((
  type,
  days,
)) {
  ('suspended', null) =>
    'Suspend for good: every match this person has closes, and Dating is '
        "closed for them for good. They can appeal once. This can't be "
        'undone here.',
  ('suspended', final int n) =>
    'Suspend for $n days: every match this person has closes, and they '
        "can't use Dating until then; afterwards Dating stays paused until "
        'they resume it. They can appeal once.',
  (_, null) =>
    "A closer look, with no end date: this person isn't told, and gets no "
        'new introductions while it lasts.',
  (_, final int n) =>
    "A closer look for $n days: this person isn't told, and gets no new "
        'introductions until then.',
};

class _RestrictDialog extends StatefulWidget {
  const _RestrictDialog({required this.category});

  /// The case's leading report category; null means the moderator picks.
  final String? category;

  @override
  State<_RestrictDialog> createState() => _RestrictDialogState();
}

class _RestrictDialogState extends State<_RestrictDialog> {
  String _type = 'suspended';
  int? _days = 7;
  late String? _category = widget.category;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Restrict'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Type'),
        DropdownButton<String>(
          key: const ValueKey('console_restrict_type'),
          value: _type,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'suspended', child: Text('Suspend')),
            DropdownMenuItem(
              value: 'under_review',
              child: Text('A closer look (not shown)'),
            ),
          ],
          onChanged: (v) => setState(() => _type = v ?? _type),
        ),
        const SizedBox(height: 8),
        const Text('For how long'),
        DropdownButton<int?>(
          key: const ValueKey('console_restrict_days'),
          value: _days,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 7, child: Text('7 days')),
            DropdownMenuItem(value: 30, child: Text('30 days')),
            DropdownMenuItem(value: 90, child: Text('90 days')),
            DropdownMenuItem(value: null, child: Text('For good')),
          ],
          onChanged: (v) => setState(() => _days = v),
        ),
        const SizedBox(height: 8),
        const Text('Category'),
        DropdownButton<String>(
          key: const ValueKey('console_restrict_category'),
          value: _category,
          isExpanded: true,
          hint: const Text('Pick a category'),
          items: [
            for (final c in kConsoleCategories)
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
        // W7 final client fix (M-11): what follows the type and length
        // picked, before Restrict (For good is irreversible here).
        const SizedBox(height: 12),
        Text(
          consoleRestrictConsequence(_type, _days),
          key: const ValueKey('console_restrict_consequence'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('console_restrict_save'),
        onPressed: switch (_category) {
          final String c => () => Navigator.of(context).pop((_type, _days, c)),
          null => null,
        },
        child: const Text('Restrict'),
      ),
    ],
  );
}

/// A note, its field owned by the dialog (disposed with it). Counted in
/// code points, as the server counts it; Ctrl+Enter saves.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog();

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _text.removeListener(_changed);
    _text.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_text.text);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a note'),
    content: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
      },
      child: TextField(
        key: const ValueKey('console_note'),
        controller: _text,
        autofocus: true,
        maxLines: 4,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        inputFormatters: const [ConsoleCodePointLimit(kConsoleNoteLimit)],
        decoration: InputDecoration(
          helperText:
              "Never write someone's gender, faith or who they want to meet.",
          counterText: '${_text.text.runes.length} / $kConsoleNoteLimit',
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('console_note_save'),
        onPressed: _save,
        child: const Text('Save'),
      ),
    ],
  );
}

/// Spec 2 W7c (§6.5): the escalation's kind and the reference the other
/// body gave; CSA 292 only with the victim's consent.
class _EscalationDialog extends StatefulWidget {
  const _EscalationDialog();

  @override
  State<_EscalationDialog> createState() => _EscalationDialogState();
}

class _EscalationDialogState extends State<_EscalationDialog> {
  /// Fix round 1 (review M-5): a pick, never a guess.
  String? _kind;
  final _reference = TextEditingController();

  @override
  void dispose() {
    _reference.removeListener(_changed);
    _reference.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _reference.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record an escalation'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(kConsoleEscalationRecordOnly),
        DropdownButton<String>(
          key: const ValueKey('console_escalation_kind'),
          value: _kind,
          isExpanded: true,
          hint: const Text('Pick a kind'),
          items: [
            for (final MapEntry(:key, :value)
                in kConsoleEscalationKinds.entries)
              DropdownMenuItem(value: key, child: Text(value)),
          ],
          onChanged: (v) => setState(() => _kind = v ?? _kind),
        ),
        // Review M-4: the consent kind only with the person's agreement.
        if (_kind == 'csa_292_with_consent')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(kConsoleConsentOnly),
          ),
        // Task 9: never learnt; counted in code points, as the server.
        TextField(
          key: const ValueKey('console_escalation_reference'),
          controller: _reference,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          inputFormatters: const [
            ConsoleCodePointLimit(kConsoleReferenceLimit),
          ],
          decoration: InputDecoration(
            labelText: 'Their reference',
            counterText:
                '${_reference.text.runes.length} / $kConsoleReferenceLimit',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('console_escalation_save'),
        onPressed: switch (_kind) {
          final String kind =>
            () => Navigator.of(context).pop((kind, _reference.text)),
          null => null,
        },
        child: const Text('Record'),
      ),
    ],
  );
}
