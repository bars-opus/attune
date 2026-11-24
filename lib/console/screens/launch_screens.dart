// Spec 2 W10 (§8 W10, §6.4, §6.9, §5.9): the safety owner's launch pages.
// Launch readiness lists every gate of get_dating_launch_readiness() with
// its state in words (never colour alone) and what is red; it is never
// green while the project reads development (R-6). Metrics shows the
// dating.* counters at n >= 50 over 7, 28 or 90 days (smaller ones are
// counted, never named). Fairness shows the weekly reports, flagged
// cohorts first; a flag goes to a person and nothing re-weights by itself.
// A moderator's console asks nothing here: the pages say they are the
// safety owner's.
//
// Fix round 1 (task-2-3-review.md): the top_decile row reads as the share
// the top 10% received (I-1); check codes read in words (M-1); a refusal is
// its line, with no Try again (M-2); a new window clears the old window's
// rows, and only the latest read is shown (M-3); the readiness names the
// countries it checked and where Dating is open (M-4); development is said
// once (M-5); rates read as percentages (M-6).
//
// Final fix (final-review.md): in production, a country open while a gate
// is red says so, in red, with what to do (I-1); any one country can be
// checked (M-1); a fairness figure is rounded (M-8).
import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_app.dart';
import 'package:flutter/material.dart';

const kConsoleLaunchOwnerOnly =
    "The launch pages are the safety owner's. Ask the safety owner.";

/// Said under the first line while the project reads development (the
/// owner keeps it there for testing and demos until launch): calm, never
/// an error, and every red gate still listed.
const kConsoleReadinessDevNote =
    'This project is in development mode for testing and demos, so it is '
    'never ready here; that is expected before launch. A DEV- reference '
    'never counts as evidence, so the gates that rely on one read red here '
    'too. Every red gate below is still to do before Dating opens in '
    'production.';

/// What a launch page reads for a refusal: its line, never Try again
/// (trying again changes nothing). Busy, offline and the rest offer it.
const kConsoleLaunchRefusals = {
  'safety_owner_only',
  'not_moderator',
  'mfa_required',
  'invalid',
};

/// A gate's name in words; an unknown gate reads as its key.
String consoleGateLabel(String gate) {
  final country = gate.contains(':') ? gate.split(':').last : '';
  return switch (gate) {
    'environment' => 'Production mode is set (only the owner sets it)',
    'age_assurance_live' => 'Age assurance runs live (not fake or sandbox)',
    'safety_owner' => 'An active safety owner',
    'moderator' => 'An active moderator',
    'keys' => 'The Dating keys are set and match their fingerprints',
    'introductions_config' =>
      'The introductions config is active with real review references',
    'chat_config' =>
      'The chat safety config is active with a real review reference',
    'flag_evidence' => 'Every launch flag has real gate evidence',
    'no_flag_violations' => 'No gated flag is on without real evidence',
    'no_test_verifications' => 'No pass from the fake providers still stands',
    'kill_switch_clear' => 'No same-gender switch-off is pending',
    'log_settings_safe' => 'The database logs keep no request values',
    'sla_alerts' => 'The SLA alerts have somewhere to go',
    final g when g.startsWith('checklist:') =>
      '$country: the legal checklist is complete with real references',
    final g when g.startsWith('resources:') =>
      '$country: support resources verified within 90 days',
    _ => gate,
  };
}

/// A country check's code in words (country_config_checks and the
/// publisher's own); a flag name or an unknown code reads as itself.
String consoleCheckLabel(Object? code) => switch (code) {
  'dev_reference' => 'a DEV- reference is still in the checklist',
  'evidence_missing' => 'a checklist reference is missing or empty',
  'same_gender_reconsideration_missing' =>
    'the same-gender reconsideration is incomplete',
  'tier_review_missing' => 'the tier change has no review reference of its own',
  'no_calling_code' => "the country isn't in the server's calling codes",
  'resources_not_verified' =>
    'the support resources are not verified within 90 days',
  'exclusion_key_not_ready' => 'the exclusion key is not ready',
  'field_key_not_ready' => 'the field key is not ready',
  _ => '$code',
};

/// What a gate's detail says: the red flags or checks, or a count.
String consoleGateDetail(Object? detail) => switch (detail) {
  final List<Object?> l when l.isNotEmpty => l
      .map(consoleCheckLabel)
      .join(', '),
  final int n when n > 0 => '$n',
  _ => '',
};

/// The readiness answer's first line.
String consoleReadinessLine(ConsoleAnswer r) {
  final gates = r.list('gates');
  final red = gates.where((g) => g['ok'] != true).length;
  if (r.data['ready'] == true) {
    return 'Every gate is green. Dating may be switched on.';
  }
  return 'Not ready: $red of ${gates.length} gates are red.';
}

/// The countries the readiness checked, and where Dating is open now.
String consoleReadinessCountries(ConsoleAnswer r) {
  List<String> codes(Object? v) => [
    for (final c in (v is List ? v : const [])) '$c',
  ];
  final checked = codes(r.data['countries']);
  if (checked.isEmpty) return '';
  final open = codes(r.data['open']);
  return 'Checked for ${checked.join(', ')}. '
      '${open.isEmpty ? 'Dating is not open in any of them yet.' : 'Dating is open now in ${open.join(', ')}.'}';
}

/// In production, Dating open somewhere while a gate is red (the flip
/// leaves a demo-open country open: nothing "opens", so no gate ran).
/// Empty otherwise.
String consoleReadinessOpenWhileRed(ConsoleAnswer r) {
  final open = [
    for (final c
        in (r.data['open'] is List ? r.data['open'] as List : const []))
      '$c',
  ];
  if (r.data['environment'] != 'production' ||
      r.data['ready'] == true ||
      open.isEmpty) {
    return '';
  }
  return 'Dating is open in ${open.join(', ')} while a launch gate is red. '
      'Close it from Countries until every gate is green.';
}

/// A figure the server sent (1.2345) to at most two places ("1.23"),
/// keeping one ("2.0"); '-' if none.
String consoleFigure(Object? v) {
  if (v is! num) return '-';
  final s = v.toStringAsFixed(2);
  return s.endsWith('0') ? s.substring(0, s.length - 1) : s;
}

/// A rate the server sent (0.0912) as a percentage ("9.1%"); '-' if none.
String consolePercent(Object? rate) {
  if (rate is! num) return '-';
  final s = (rate * 100).toStringAsFixed(1);
  return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}%';
}

/// One read, again on demand or when its window changes.
abstract class _LaunchState<T extends StatefulWidget> extends State<T> {
  ConsoleAnswer? read;
  ConsoleAnswer? good;
  int _seq = 0;

  ConsoleApi get api;
  ConsoleMe get me;
  String get action;
  String get title;
  String get loading;
  Map<String, Object?> get params => const {};

  @override
  void initState() {
    super.initState();
    if (me.owner) load();
  }

  Future<void> load() async {
    final seq = ++_seq;
    final r = await api(action, params);
    // Only the latest read is shown (a slow earlier window never wins).
    if (!mounted || seq != _seq) return;
    setState(() {
      read = r;
      if (r.ok) good = r;
    });
  }

  /// A new window: its rows only, never the last window's.
  void changeWindow(VoidCallback change) {
    setState(() {
      change();
      read = null;
      good = null;
    });
    load();
  }

  Widget _problem(ConsoleAnswer r, VoidCallback onRetry) =>
      kConsoleLaunchRefusals.contains(r.reason)
          ? Padding(
            padding: const EdgeInsets.all(16),
            child: ConsoleStatus(
              ConsoleLine.of(r),
              textKey: const ValueKey('console_launch_refusal'),
            ),
          )
          : ConsoleRetry(answer: r, onRetry: onRetry);

  Widget page(
    List<Widget> Function(ConsoleAnswer read) rows, {
    Widget? controls,
  }) {
    if (!me.owner) {
      return ConsoleFrame(
        title: title,
        onRefresh: null,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text(kConsoleLaunchOwnerOnly),
        ),
      );
    }
    final r = read;
    final kept = good;
    final body = switch (r) {
      null => ConsoleLoading(loading),
      ConsoleAnswer(ok: false) when kept == null => Align(
        alignment: Alignment.topLeft,
        child: _problem(r, () {
          setState(() => read = null);
          load();
        }),
      ),
      _ => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [if (!r.ok) _problem(r, load), ...rows(r.ok ? r : kept!)],
        ),
      ),
    };
    return ConsoleFrame(
      title: title,
      onRefresh: r == null ? null : load,
      // The window stays choosable whatever the read did.
      child:
          controls == null
              ? body
              : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: controls,
                    ),
                  ),
                  Expanded(child: body),
                ],
              ),
    );
  }
}

class ReadinessScreen extends StatefulWidget {
  const ReadinessScreen({super.key, required this.api, required this.me});

  final ConsoleApi api;
  final ConsoleMe me;

  @override
  State<ReadinessScreen> createState() => _ReadinessScreenState();
}

class _ReadinessScreenState extends _LaunchState<ReadinessScreen> {
  final _code = TextEditingController();

  /// One country to check (M-1), or none for the server's default list.
  String _country = '';

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Map<String, Object?> get params =>
      _country.isEmpty ? const {} : {'country': _country};

  @override
  ConsoleApi get api => widget.api;

  @override
  ConsoleMe get me => widget.me;

  @override
  String get action => 'readiness';

  @override
  String get title => 'The launch gates (every one green to launch)';

  @override
  String get loading => 'Loading the launch gates.';

  @override
  Widget build(BuildContext context) => page(
    controls: Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 220,
          child: TextField(
            key: const ValueKey('console_readiness_country'),
            controller: _code,
            decoration: const InputDecoration(
              labelText: 'One country (empty: Ghana and the UK)',
            ),
          ),
        ),
        TextButton(
          key: const ValueKey('console_readiness_check'),
          onPressed:
              () => changeWindow(
                () => _country = _code.text.trim().toUpperCase(),
              ),
          child: const Text('Check'),
        ),
      ],
    ),
    (r) => [
      ConsoleStatus(
        ConsoleLine(consoleReadinessLine(r)),
        textKey: const ValueKey('console_readiness_line'),
      ),
      if (consoleReadinessOpenWhileRed(r) case final o when o.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ConsoleStatus(
            ConsoleLine(o, error: true),
            textKey: const ValueKey('console_readiness_open_red'),
          ),
        ),
      if (consoleReadinessCountries(r) case final c when c.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(c, key: const ValueKey('console_readiness_countries')),
        ),
      if (r.data['ready'] != true && r.data['environment'] == 'development')
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            kConsoleReadinessDevNote,
            key: ValueKey('console_readiness_dev_note'),
          ),
        ),
      const SizedBox(height: 8),
      for (final g in r.list('gates'))
        _GateTile(
          gate: '${g['gate']}',
          ok: g['ok'] == true,
          detail: consoleGateDetail(g['detail']),
        ),
    ],
  );
}

class _GateTile extends StatelessWidget {
  const _GateTile({required this.gate, required this.ok, required this.detail});

  final String gate;
  final bool ok;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = ok ? 'Green' : 'Red';
    return MergeSemantics(
      child: ListTile(
        key: ValueKey('console_gate_$gate'),
        dense: true,
        leading: ExcludeSemantics(
          child: Icon(
            ok ? Icons.check_circle_outline : Icons.cancel_outlined,
            color: ok ? scheme.primary : scheme.error,
          ),
        ),
        title: Text(consoleGateLabel(gate)),
        subtitle: Text(detail.isEmpty ? state : '$state: $detail'),
      ),
    );
  }
}

class MetricsScreen extends StatefulWidget {
  const MetricsScreen({super.key, required this.api, required this.me});

  final ConsoleApi api;
  final ConsoleMe me;

  @override
  State<MetricsScreen> createState() => _MetricsScreenState();
}

class _MetricsScreenState extends _LaunchState<MetricsScreen> {
  int _days = 7;

  @override
  ConsoleApi get api => widget.api;

  @override
  ConsoleMe get me => widget.me;

  @override
  String get action => 'metrics';

  @override
  String get title => 'Metrics (counts of 50 or more)';

  @override
  String get loading => 'Loading the metrics.';

  @override
  Map<String, Object?> get params => {'days': _days};

  @override
  Widget build(BuildContext context) => page(
    controls: SegmentedButton<int>(
      key: const ValueKey('console_metrics_days'),
      segments: const [
        ButtonSegment(value: 7, label: Text('7 days')),
        ButtonSegment(value: 28, label: Text('28 days')),
        ButtonSegment(value: 90, label: Text('90 days')),
      ],
      selected: {_days},
      onSelectionChanged: (s) => changeWindow(() => _days = s.first),
    ),
    (r) => [
      Text(
        '${consoleDay(r.data['from'])} to ${consoleDay(r.data['to'])} (UTC). '
        'Counters under ${r.data['min_count'] ?? 50} are not shown: '
        '${r.data['suppressed'] ?? 0}.',
      ),
      if (r.list('metrics').isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('No counter reached 50 in this window.'),
        ),
      for (final m in r.list('metrics'))
        ListTile(
          key: ValueKey('console_metric_${m['key']}'),
          dense: true,
          title: Text('${m['key']}'),
          trailing: Text('${m['count']}'),
        ),
    ],
  );
}

/// A day the server sent ("2026-11-17" → "17 Nov 2026"); '-' if none.
String consoleDay(Object? day) {
  final d = day is String ? DateTime.tryParse(day) : null;
  if (d == null) return '-';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

class FairnessScreen extends StatefulWidget {
  const FairnessScreen({super.key, required this.api, required this.me});

  final ConsoleApi api;
  final ConsoleMe me;

  @override
  State<FairnessScreen> createState() => _FairnessScreenState();
}

class _FairnessScreenState extends _LaunchState<FairnessScreen> {
  int _weeks = 4;

  @override
  ConsoleApi get api => widget.api;

  @override
  ConsoleMe get me => widget.me;

  @override
  String get action => 'fairness';

  @override
  String get title => 'Fairness (weekly, cohorts of 50 or more)';

  @override
  String get loading => 'Loading the fairness reports.';

  @override
  Map<String, Object?> get params => {'weeks': _weeks};

  @override
  Widget build(BuildContext context) => page(
    controls: SegmentedButton<int>(
      key: const ValueKey('console_fairness_weeks'),
      segments: const [
        ButtonSegment(value: 4, label: Text('4 weeks')),
        ButtonSegment(value: 12, label: Text('12 weeks')),
      ],
      selected: {_weeks},
      onSelectionChanged: (s) => changeWindow(() => _weeks = s.first),
    ),
    (r) => [
      Text(
        '${r.data['flagged'] ?? 0} flagged. A flag is for you to review; '
        'nothing re-weights by itself. A change is a new config version '
        'with a fairness review reference.',
      ),
      if (r.list('reports').isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('No fairness report in this window yet.'),
        ),
      for (final (i, f) in r.list('reports').indexed)
        ListTile(
          key: ValueKey('console_fairness_$i'),
          dense: true,
          title: Text(
            '${f['flagged'] == true ? 'Flagged · ' : ''}'
            '${f['country']} · ${f['cohort']} · week of ${consoleDay(f['week'])}',
          ),
          subtitle: Text(consoleFairnessLine(f)),
        ),
    ],
  );
}

/// A fairness row's figures. The top_decile row holds the share of the
/// country's introductions the top 10% of people received (flagged above
/// 25%, W5c), never a per-person rate.
String consoleFairnessLine(Map<String, dynamic> f) => switch (f['cohort']) {
  'top_decile' =>
    'The top 10% received ${consolePercent(f['introductions_per_active'])} '
        'of introductions (flagged above 25%) · ${f['active']} active',
  _ =>
    '${consoleFigure(f['introductions_per_active'])} introductions per active person · '
        'mutual rate ${consolePercent(f['mutual_rate'])} · ${f['active']} active',
};
