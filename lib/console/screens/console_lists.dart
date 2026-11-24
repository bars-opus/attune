// Spec 2 W7b (§6.4): the console's other pages. Photos waiting for a
// person (approve, or reject with a reason); verifications waiting for a
// person (the gesture photos beside the approved ones: pass, fail, ask for
// ID); S1 W9b's Opinions review queue v0 through its own RPCs (at-risk
// first; keep or escalate an at-risk item unless it breaks a rule on its
// own); countries (publishing is the safety owner's); the audit.
//
// Task 7: each page has its title, Read again, loading, an empty line, and
// busy or offline with Try again (calm, never red); a publish says what it
// made and the checks still open, and a replayed publish (no checks) says
// nothing changed; a config code reads as its own line.
//
// Fix round 1 (task-7-review.md): photo Approve, Opinions Remove and
// Publish wait for a confirm naming the consequence (Publish shows the
// country and the parsed values) (I-1); each page is built whole, and a
// signed photo that won't load (its minute ran out) reads the page again
// by itself, at most once in 50 seconds (M-2; these reads write no audit).
// Fix round 2: the verification decisions confirm too.
//
// Spec 2 W7c Task 9 (owner 2026-11-22, R-60): the CSAM hold list, the
// safety owner's alone (a moderator's console asks nothing): each live
// hold with its date, whether it was carried over, and Spec 1's reviews of
// the person's matched uploads (id, status, date: never a name, never the
// image). A lift needs a written reason (code points, as the server counts
// it), then a confirm that names the consequence and repeats the reason,
// Cancel focused; nothing is sent on a cancel at either step.
import 'dart:convert';

import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:attune/console/screens/case_screen.dart';
import 'package:attune/console/screens/launch_screens.dart';
import 'package:flutter/material.dart';

/// Spec 2 W7c Task 9 (owner 2026-11-22, R-60): the CSAM hold lift.
const kConsoleCsamOwnerOnly = "The CSAM hold list is the safety owner's.";
// Fix round 1 (review M-6): a report's or a moderator's CSAM hold has no
// hash match, so the copy names the hold's grounds.
const kConfirmCsamLift =
    'Lift this CSAM hold: this person is back in introductions and can send '
    'messages again, unless another hold or restriction applies. Only lift '
    "it once review shows the hold's grounds were wrong (for a hash match, "
    "a false positive). Spec 1's account hold and its review aren't changed "
    "here. This can't be undone here.";
const kConsoleCsamGuidance =
    "Lift a CSAM hold only once review shows the hold's grounds were wrong "
    '(for a hash match, a false positive). A hold placed through a case '
    "opens its case for that review. Spec 1's account hold and its review "
    "are separate and aren't changed here.";
const kConsoleCsamLifted = 'Lifted. Your reason is kept in the audit.';

/// Where a CSAM hold came from (Task 8 fix round 2: a report's or a
/// moderator's csam-category hold is listed too; its case is never named).
const kConsoleCsamFromHash = 'a hash match';
const kConsoleCsamFromCase =
    "placed through a case (a report's or a moderator's)";

/// Loads [action] once, and again after [act] or on demand.
abstract class _ListState<T extends StatefulWidget> extends State<T> {
  ConsoleAnswer? read;

  /// W7 final client fix (M-7): the last read that worked, kept on screen
  /// (with the action's line) when a read again is busy or offline.
  ConsoleAnswer? good;
  ConsoleLine? line;
  bool busy = false;

  ConsoleApi get api;
  String get action;
  String get title;
  String get loading => 'Loading.';
  Map<String, Object?> get params => const {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = await api(action, params);
    if (!mounted) return;
    setState(() {
      read = r;
      if (r.ok) good = r;
    });
  }

  DateTime? _resigned;

  /// A signed photo failed (likely past its minute): read again for new
  /// links, at most once in 50 seconds, so a broken image never loops.
  void imageFailed() {
    final now = DateTime.now();
    if (_resigned case final at?
        when now.difference(at) < const Duration(seconds: 50)) {
      return;
    }
    _resigned = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
  }

  /// Asks first: an irreversible decision (I-1).
  Future<bool> sure(String title, String consequence, String confirm) =>
      consoleConfirm(
        context,
        title: title,
        consequence: consequence,
        confirm: confirm,
      );

  Future<void> act(
    String action,
    Map<String, Object?> params, {
    ConsoleLine Function(ConsoleAnswer r)? done,
  }) async {
    setState(() {
      busy = true;
      line = null;
    });
    final r = await api(action, params);
    if (!mounted) return;
    setState(() {
      busy = false;
      line =
          r.ok
              ? (done?.call(r) ?? const ConsoleLine('Done.'))
              : ConsoleLine.of(r);
    });
    await load();
  }

  Widget page(List<Widget> Function(ConsoleAnswer read) rows) {
    final r = read;
    final kept = good;
    // M-7: an action's line is never lost to a read again that failed.
    final said = switch (line) {
      final l? => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ConsoleStatus(l, textKey: const ValueKey('console_list_line')),
      ),
      null => null,
    };
    return ConsoleFrame(
      title: title,
      onRefresh: r == null ? null : load,
      child: switch (r) {
        null => ConsoleLoading(loading),
        ConsoleAnswer(ok: false) when kept == null => Align(
          alignment: Alignment.topLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (said != null)
                Padding(padding: const EdgeInsets.all(16), child: said),
              ConsoleRetry(
                answer: r,
                onRetry: () {
                  setState(() => read = null);
                  load();
                },
              ),
            ],
          ),
        ),
        _ => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (said != null) said,
              // M-7: the last good read stays, under the failed read's
              // line and Try again.
              if (!r.ok) ConsoleRetry(answer: r, onRetry: load),
              ...rows(r.ok ? r : kept!),
            ],
          ),
        ),
      },
    );
  }
}

/// A detail map as "key: value" pairs.
String _detail(Object? detail) =>
    detail is Map && detail.isNotEmpty
        ? [for (final e in detail.entries) '${e.key}: ${e.value}'].join(', ')
        : '';

class PhotosScreen extends StatefulWidget {
  const PhotosScreen({super.key, required this.api});

  final ConsoleApi api;

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends _ListState<PhotosScreen> {
  @override
  ConsoleApi get api => widget.api;

  @override
  String get action => 'photos';

  @override
  String get title => 'Photos waiting for a person';

  @override
  String get loading => 'Loading the photos.';

  @override
  Widget build(BuildContext context) => page(
    (r) => [
      if (r.list('photos').isEmpty) const Text('No photo is waiting.'),
      for (final p in r.list('photos'))
        Card(
          key: ValueKey('console_photo_${p['id']}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                consoleImage(
                  p['url'],
                  'Photo ${p['position']}',
                  onFailed: imageFailed,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    [
                      'Photo ${p['position']}',
                      if (p['reason'] is String) p['reason'],
                      if (p['created_at'] is String)
                        'added ${consoleDate(p['created_at'])}',
                    ].join(' · '),
                  ),
                ),
                FilledButton(
                  onPressed:
                      busy
                          ? null
                          : () async {
                            if (!await sure(
                              'Approve this photo?',
                              consoleConfirmApprove(p['position']),
                              'Approve',
                            )) {
                              return;
                            }
                            await act('photo_decide', {
                              'photo_id': p['id'],
                              'approve': true,
                            });
                          },
                  child: const Text('Approve'),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  key: ValueKey('console_photo_reject_${p['id']}'),
                  tooltip: 'Reject, with a reason',
                  enabled: !busy,
                  onSelected:
                      (reason) => act('photo_decide', {
                        'photo_id': p['id'],
                        'approve': false,
                        'reason': reason,
                      }),
                  itemBuilder:
                      (_) => [
                        for (final reason in const [
                          'face_unclear',
                          'too_small',
                          'contains_child',
                          'unsafe',
                        ])
                          PopupMenuItem(value: reason, child: Text(reason)),
                      ],
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Reject'),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class VerificationsScreen extends StatefulWidget {
  const VerificationsScreen({super.key, required this.api});

  final ConsoleApi api;

  @override
  State<VerificationsScreen> createState() => _VerificationsScreenState();
}

class _VerificationsScreenState extends _ListState<VerificationsScreen> {
  /// A verification decision, once confirmed (fix round 2).
  Future<void> _decideCheck(Object? session, String outcome) async {
    final (title, consequence, confirm) = switch (outcome) {
      'pass' => ('Identity passes?', kConfirmIdentityPass, 'Identity passes'),
      'fail' => ('Identity fails?', kConfirmIdentityFail, 'Identity fails'),
      _ => (
        '$kConsoleAskIdDocument?',
        kConfirmAskForId,
        kConsoleAskIdDocument,
      ),
    };
    if (!await sure(title, consequence, confirm)) return;
    await act('verification_decide', {
      'session_id': session,
      'outcome': outcome,
    });
  }

  @override
  ConsoleApi get api => widget.api;

  @override
  String get action => 'verifications';

  @override
  String get title => 'Verifications waiting for a person';

  @override
  String get loading => 'Loading the checks.';

  @override
  Widget build(BuildContext context) => page(
    (r) => [
      if (r.list('sessions').isEmpty) const Text('No check is waiting.'),
      for (final s in r.list('sessions'))
        Card(
          key: ValueKey('console_session_${s['id']}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${s['step']} · ${s['kind']} · since ${consoleDate(s['since'])}',
                ),
                if (s['gestures'] is List)
                  Text('Gestures: ${(s['gestures'] as List).join(', ')}'),
                const SizedBox(height: 8),
                const Text('The gesture photos'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (i, u)
                        in (s['review'] as List? ?? const []).indexed)
                      consoleImage(
                        u,
                        'Gesture photo ${i + 1}',
                        onFailed: imageFailed,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Approved photos'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p
                        in (s['photos'] as List? ?? const []).whereType<Map>())
                      consoleImage(
                        p['url'],
                        'Approved photo ${p['position']}',
                        onFailed: imageFailed,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (s['step'] == 'human') ...[
                      FilledButton(
                        key: ValueKey('console_pass_${s['id']}'),
                        onPressed:
                            busy ? null : () => _decideCheck(s['id'], 'pass'),
                        child: const Text('Identity passes'),
                      ),
                      OutlinedButton(
                        key: ValueKey('console_fail_${s['id']}'),
                        onPressed:
                            busy ? null : () => _decideCheck(s['id'], 'fail'),
                        child: const Text('Identity fails'),
                      ),
                    ],
                    OutlinedButton(
                      key: ValueKey('console_ask_id_${s['id']}'),
                      onPressed:
                          busy
                              ? null
                              : () => _decideCheck(s['id'], 'ask_for_id'),
                      child: const Text(kConsoleAskIdDocument),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class OpinionsScreen extends StatefulWidget {
  const OpinionsScreen({super.key, required this.api});

  final ConsoleApi api;

  @override
  State<OpinionsScreen> createState() => _OpinionsScreenState();
}

class _OpinionsScreenState extends _ListState<OpinionsScreen> {
  @override
  ConsoleApi get api => widget.api;

  @override
  String get action => 'opinions_queue';

  @override
  String get title => 'Opinions review queue v0';

  @override
  String get loading => 'Loading the Opinions reports.';

  @override
  Widget build(BuildContext context) => page(
    (r) => [
      const Text(
        "Opinions review queue v0. Someone may be at risk: keep the post or escalate it; remove it only when it breaks a rule on its own.",
      ),
      const SizedBox(height: 8),
      if (r.list('reports').isEmpty)
        const Text('No priority report is waiting.'),
      for (final p in r.list('reports'))
        Card(
          key: ValueKey('console_opinion_${p['report_id']}'),
          child: ListTile(
            leading:
                p['reason'] == 'Someone may be at risk'
                    ? const Tooltip(
                      message: 'At risk',
                      child: Icon(Icons.priority_high),
                    )
                    : null,
            title: Text('${p['reason']}'),
            subtitle: Text(
              [
                '${p['excerpt'] ?? ''}',
                [
                  '${p['content_type']}',
                  if (p['reported_at'] is String)
                    'reported ${consoleDate(p['reported_at'])}',
                  if (p['hidden_pending_review'] == true)
                    'hidden while waiting',
                ].join(' · '),
              ].join('\n'),
            ),
            isThreeLine: true,
            trailing:
                p['content_removed'] == true
                    ? const Text('Removed')
                    : TextButton(
                      onPressed:
                          busy
                              ? null
                              : () async {
                                if (!await sure(
                                  'Remove it?',
                                  consoleConfirmRemove(p['content_type']),
                                  'Remove',
                                )) {
                                  return;
                                }
                                await act('opinions_remove', {
                                  'type': p['content_type'],
                                  'id': p['content_id'],
                                });
                              },
                      child: const Text('Remove'),
                    ),
          ),
        ),
    ],
  );
}

class CountriesScreen extends StatefulWidget {
  const CountriesScreen({super.key, required this.api, required this.me});

  final ConsoleApi api;
  final ConsoleMe me;

  @override
  State<CountriesScreen> createState() => _CountriesScreenState();
}

/// What a publish's answer says. A replay (the same values again, nobody
/// having published since) answers without checks: nothing changed.
ConsoleLine consolePublishLine(ConsoleAnswer r) {
  final d = r.data;
  final what = '${d['country']} version ${d['version']}';
  if (d['checks'] is! List) {
    return ConsoleLine(
      '$what was already published with these values. Nothing changed.',
    );
  }
  // Spec 2 W10 fix round 1 (M-1): each check in words.
  final checks = (d['checks'] as List).map(consoleCheckLabel).join(', ');
  return ConsoleLine(
    [
      'Published $what (${d['environment']}): '
          'Dating ${d['dating_enabled'] == true ? 'on' : 'off'}, '
          'same gender ${d['same_gender_enabled'] == true ? 'on' : 'off'}.',
      if (checks.isNotEmpty) 'Checks still open: $checks.',
      if (d['switched'] == true)
        d['affected'] is int
            ? 'Same gender was switched off for ${d['affected']} people.'
            : 'Same gender is off; the switch-off for people already '
                'matched is still pending.',
    ].join(' '),
  );
}

class _CountriesScreenState extends _ListState<CountriesScreen> {
  final _country = TextEditingController();
  final _values = TextEditingController(text: '{}');

  @override
  ConsoleApi get api => widget.api;

  @override
  String get action => 'countries';

  @override
  String get title => 'Country settings';

  @override
  String get loading => 'Loading the countries.';

  @override
  void dispose() {
    _country.dispose();
    _values.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    Object? values;
    try {
      values = jsonDecode(_values.text);
    } catch (_) {
      values = null;
    }
    if (values is! Map) {
      setState(
        () => line = ConsoleLine(consoleReason('values_not_json'), error: true),
      );
      return;
    }
    final country = _country.text.trim().toUpperCase();
    if (!await sure(
      'Publish $country?',
      consoleConfirmPublish(country, values),
      'Publish',
    )) {
      return;
    }
    await act('publish_country', {
      'country': country,
      'values': values,
    }, done: consolePublishLine);
  }

  @override
  Widget build(BuildContext context) => page(
    (r) => [
      if (r.list('countries').isEmpty)
        const Text('No country is published yet.'),
      for (final c in r.list('countries'))
        ListTile(
          key: ValueKey('console_country_${c['country']}'),
          title: Text('${c['country']} · tier ${c['tier']} · v${c['version']}'),
          subtitle: Text(
            'Dating ${c['dating_enabled'] == true ? 'on' : 'off'} · same gender '
            '${c['same_gender_enabled'] == true ? 'on' : 'off'} · regions '
            '${c['open_regions'] is List ? (c['open_regions'] as List).join(', ') : 'all'}'
            '${c['published_at'] is String ? ' · published ${consoleDate(c['published_at'])}' : ''}',
          ),
        ),
      if (widget.me.owner) ...[
        const Divider(),
        Semantics(header: true, child: const Text('Publish (safety owner)')),
        consoleField(
          key: const ValueKey('console_country_code'),
          controller: _country,
          label: 'Country (GH)',
        ),
        consoleField(
          key: const ValueKey('console_country_values'),
          controller: _values,
          label: 'Values (JSON)',
          maxLines: 3,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const ValueKey('console_publish'),
            onPressed: busy ? null : _publish,
            child: const Text('Publish'),
          ),
        ),
      ],
    ],
  );
}

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key, required this.api});

  final ConsoleApi api;

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends _ListState<AuditScreen> {
  @override
  ConsoleApi get api => widget.api;

  @override
  String get action => 'audit';

  @override
  String get title => 'Audit (newest first)';

  @override
  String get loading => 'Loading the audit.';

  @override
  Map<String, Object?> get params => const {'limit': 200};

  @override
  Widget build(BuildContext context) => page(
    (r) => [
      if (r.list('actions').isEmpty) const Text('Nothing is recorded yet.'),
      for (final a in r.list('actions'))
        ListTile(
          dense: true,
          title: Text('${a['action']}${a['mine'] == true ? ' (you)' : ''}'),
          subtitle: Text(
            [
              consoleDate(a['at']),
              if (_detail(a['detail']) case final d when d.isNotEmpty) d,
            ].join(' · '),
          ),
        ),
    ],
  );
}

/// A CSAM lift's reason, at most this many code points (the server's).
const kConsoleCsamReasonLimit = 1000;

class CsamHoldsScreen extends StatefulWidget {
  const CsamHoldsScreen({super.key, required this.api, required this.me});

  final ConsoleApi api;
  final ConsoleMe me;

  @override
  State<CsamHoldsScreen> createState() => _CsamHoldsScreenState();
}

class _CsamHoldsScreenState extends _ListState<CsamHoldsScreen> {
  @override
  ConsoleApi get api => widget.api;

  @override
  String get action => 'csam_holds';

  @override
  String get title => 'CSAM holds';

  @override
  String get loading => 'Loading the CSAM holds.';

  /// A moderator's console asks nothing (R-60; the server refuses anyway).
  @override
  Future<void> load() async {
    if (widget.me.owner) await super.load();
  }

  Future<void> _openCase(String caseId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => CaseScreen(api: widget.api, me: widget.me, caseId: caseId),
      ),
    );
    if (mounted) await load();
  }

  Future<void> _lift(Object? id) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _CsamReasonDialog(),
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    final yes = await sure(
      'Lift this CSAM hold?',
      '$kConfirmCsamLift\n\nYour reason: "$reason"',
      'Lift the hold',
    );
    if (!yes) return;
    await act('lift_csam_hold', {
      'restriction_id': id,
      'reason': reason,
    }, done: (_) => const ConsoleLine(kConsoleCsamLifted));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.me.owner) {
      return const Center(child: Text(kConsoleCsamOwnerOnly));
    }
    return page(
      (r) => [
        const Text(kConsoleCsamGuidance),
        const SizedBox(height: 8),
        if (r.list('holds').isEmpty) const Text('No CSAM hold is live.'),
        for (final h in r.list('holds'))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      'Since ${consoleDate(h['since'])}',
                      h['case_id'] == null
                          ? kConsoleCsamFromHash
                          : kConsoleCsamFromCase,
                      if (h['carried'] == true)
                        'carried over from a deleted account',
                    ].join(' · '),
                  ),
                  if ((h['escalations'] as List? ?? const []).isEmpty)
                    const Text('No Spec 1 review is linked.')
                  else
                    for (final e in (h['escalations'] as List).whereType<Map>())
                      SelectableText(
                        'Spec 1 review ${e['id']} · ${e['status']} · '
                        '${consoleDate(e['created_at'])}',
                      ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Fix round 1 (review I-2): the evidence for a
                      // case-placed hold is its case (the owner's to read).
                      if (h['case_id'] case final String caseId)
                        OutlinedButton(
                          key: ValueKey('console_csam_case_${h['id']}'),
                          onPressed: () => _openCase(caseId),
                          child: const Text('Open its case'),
                        ),
                      OutlinedButton(
                        key: ValueKey('console_csam_lift_${h['id']}'),
                        onPressed: busy ? null : () => _lift(h['id']),
                        child: const Text('Lift this hold'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The lift's written reason: required, counted in code points, never
/// learnt by the keyboard. Answers the trimmed reason, or null on Cancel.
class _CsamReasonDialog extends StatefulWidget {
  const _CsamReasonDialog();

  @override
  State<_CsamReasonDialog> createState() => _CsamReasonDialogState();
}

class _CsamReasonDialogState extends State<_CsamReasonDialog> {
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

  @override
  Widget build(BuildContext context) {
    final reason = _text.text.trim();
    return AlertDialog(
      title: const Text('Why lift this hold?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: TextField(
          key: const ValueKey('console_csam_reason'),
          controller: _text,
          autofocus: true,
          maxLines: 4,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          inputFormatters: const [
            ConsoleCodePointLimit(kConsoleCsamReasonLimit),
          ],
          decoration: InputDecoration(
            labelText: 'Your reason (kept in the audit)',
            helperText:
                'What the review found. Never describe the image, or write '
                "someone's gender, faith or who they want to meet.",
            helperMaxLines: 3,
            counterText:
                '${_text.text.runes.length} / $kConsoleCsamReasonLimit',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('console_csam_reason_next'),
          onPressed:
              reason.isEmpty ? null : () => Navigator.of(context).pop(reason),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
