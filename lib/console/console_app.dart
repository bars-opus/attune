// Spec 2 W7b (§6.4): the console's shell. Signed out: the phone and its
// code; then TOTP (a first sign-in enrols an authenticator app); then the
// server says whether this account is an active moderator. Only then the
// pages: the queue, appeals, signals, photos, verifications, Opinions,
// countries and the audit. Nothing here is stored on the device by the
// console itself.
//
// Task 7 (the live contract): every fixed code the function can answer
// has its own line (consoleReason); busy, offline and claimed are a calm
// moment's wait, never an error (consoleCalm). Nothing here signs the
// moderator out but the Sign out button: an unauthorized answer or an
// unreachable Auth offers Try again first.
//
// Fix round 1 (task-7-review.md): an irreversible decision waits for a
// confirm that names its consequence, Cancel focused (I-1); sign-out
// clears the phone number and a copied TOTP key (M-1); a new code or
// another number (M-5); an idle console signs out after 30 minutes (M-6).
//
// Spec 2 W7c Task 9 (console round 3): the law-enforcement log and the CSAM
// hold list are pages of their own (the safety owner's; a moderator's
// console asks nothing, R-60); the codes Task 8's fix round added have
// their lines; a code check that outlives its time box says it may still
// have worked (Check my sign-in), never "That code didn't work."; the
// copied key is cleared by writing an empty clipboard, never by reading it
// (a read can raise the browser's permission prompt), and only when this
// console copied it.
import 'dart:async';
import 'dart:convert';

import 'package:attune/console/console_api.dart';
import 'package:attune/console/console_auth.dart';
import 'package:attune/console/screens/case_screen.dart';
import 'package:attune/console/screens/console_lists.dart';
import 'package:attune/console/screens/law_enforcement_screen.dart';
import 'package:attune/console/screens/queue_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const kConsoleTitle = 'Attune moderation';

/// The most cases one queue read asks for (the function's own most).
const kConsoleQueueLimit = 200;

/// Said when a queue read came back full: more may wait unseen.
// W7 final client fix (final minor): each kind is its own read, so the
// cap is per kind.
const kConsoleQueueCapped =
    'More are waiting — showing the first 200 of this kind by priority, so '
    "some of this page's cases may not be listed.";

/// How long an untouched console stays signed in.
const kConsoleIdle = Duration(minutes: 30);
const kConsoleIdleLine =
    'You were signed out after 30 minutes without activity.';

const kConsoleClipboardHint =
    'Once you are signed in, or if you sign out, the console empties your '
    'clipboard, as it held the key.';

// The confirm steps (fix round 1, I-1): each names what can't be undone.
const kConfirmMinor =
    'Confirm a minor: closes the case, restricts Dating for age review and '
    "places an account hold. This can't be undone here.";
// Task 9 fix round 1 (I-1): a decision ends only what its case placed; the
// person may hold more (another case's hold, a CSAM hold), so no confirm
// promises they are free.
const kConsoleStillHeld =
    'unless another hold or restriction applies: a hold another case placed '
    "stays, and so does a CSAM hold, which only the safety owner's CSAM lift "
    'ends';
const kConfirmDismiss =
    'Dismiss: closes the case with no action and lifts the holds it placed '
    "(a signal's throttle too). This person is back in introductions "
    "$kConsoleStillHeld. This can't be undone here.";
// W7 final client fix (M-9, R-53): an accepted suspension leaves Dating
// paused until the person resumes it.
const kConfirmAccept =
    'Accept the appeal: ends this restriction. Dating stays paused until '
    'this person resumes it, and they can use it again then '
    '$kConsoleStillHeld. Each restriction has one appeal, so this is final.';
const kConfirmReject =
    'Reject the appeal: the restriction stays. Each restriction has one '
    'appeal, so this is final.';

// Fix round 2: the verification decisions.
const kConfirmIdentityPass =
    'Identity passes: this person is verified as the one in their photos, '
    "and the gesture photos are deleted. This can't be undone here.";
const kConfirmIdentityFail =
    "Identity fails: this person's check fails, and the gesture photos are "
    "deleted. This can't be undone here.";
// W7 final client fix (M-10): the identity check's Ask for an ID document
// and the case's age check are two actions with two names.
const kConfirmAskForId =
    'Ask for an ID document: this identity check ends without a decision, '
    'and this person is asked to verify with an ID document instead. This '
    "can't be undone here.";

/// M-10: the two actions' labels.
const kConsoleAskIdDocument = 'Ask for an ID document';
const kConsoleAskIdAgeCheck = 'Ask for ID (age check)';

// Spec 2 W7c Task 9 (console round 3): the case's Ask for ID and Lift hold
// confirm too; a lift never says the person has no hold left (a person can
// hold a report's hold and a CSAM hold at once, Task 8 fix round 1).
//
// Fix round 1 (owner): Ask for ID no longer closes the case. It waits for
// the person's ID email and stays in the queue as Waiting for ID; once
// support has seen the ID, Lift hold (an adult) decides it, or Confirm a
// minor, or Dismiss.
// W7 final client fix (server round 3): Ask for ID opens a separate ID
// check case (kind id_check) that holds the age reports and the age check;
// this case keeps its other reports and holds.
const kConfirmCaseAskForId =
    'Ask for ID (age check): opens a separate ID check case for this '
    "person, and this case's age reports move there. Dating is restricted "
    'for an age check until this person shows an ID document to support; '
    'the ID check waits in the queue as Waiting for ID. This case keeps its '
    'other reports and holds. If it has none left, it closes and lifts its '
    "holds, except a CSAM hold (only the safety owner's CSAM lift ends one).";

/// Server round 2 (kept in round 3): "Lift the case's holds" on an
/// ordinary open case (moderation_lift_case_holds): its interim holds and
/// report age checks, never an ID check's age check, never CSAM.
const kConsoleLiftCaseHolds = "Lift the case's holds";
const kConfirmLiftCaseHolds =
    "Lift the case's holds: lifts the holds and the report age checks this "
    "case placed (never an ID check's age check). This person is back in "
    'introductions and can send messages again $kConsoleStillHeld. '
    'Lifting decides nothing about the case.';

/// W7 final client fix (M-1, M-R1-1): on a case with an underage report,
/// lifting its holds lifts the interim age check too, so the guidance
/// returns.
const kConfirmLiftCaseHoldsUnderage =
    "$kConfirmLiftCaseHolds Lift an age check only once support has seen "
    "this person's ID.";

/// Server round 3: an ID check case's four actions, each naming its
/// consequence. None changes the holds or reports of the case it came
/// from.
const kConsoleLiftAgeCheck = 'Lift the age check';
const kConsoleDismissIdCheck = 'Dismiss (asked by mistake)';
const kConsoleNotOrigin =
    "Nothing here changes the case it came from: its holds and reports are "
    'decided there.';
const kConfirmLiftAgeCheck =
    "Lift the age check: support has seen this person's ID and they are an "
    'adult. This lifts the age check and closes this ID check (its age '
    "reports not upheld). $kConsoleNotOrigin This can't be undone here.";

/// A late ID on a decided No ID came check: the check ends, the decision
/// stands.
const kConfirmLiftIdDecided =
    "Lift the age check: support has seen this person's ID and they are an "
    'adult. This lifts the age check; this ID check stays decided as No ID '
    "came. $kConsoleNotOrigin This can't be undone here.";
const kConfirmMinorIdCheck =
    "Confirm a minor: support has seen this person's ID and they are under "
    '18. This closes this ID check (its age reports upheld), restricts '
    'Dating for age review in place of the age check, and places an account '
    "hold. This can't be undone here.";

/// Server round 5: "No ID came" decides a waiting ID check (no_id_received).
const kConfirmNoId =
    'No ID came: closes this ID check without an ID (its age reports '
    'upheld). The age check stays, so this person still cannot use Dating '
    'until they verify with an ID document through support; a late ID is '
    "still handled here. This can't be undone here.";
/// Server round 4: No ID came on an orphaned ID check (the person deleted
/// their account): the age check stays on their phone number.
const kConfirmNoIdGone =
    'No ID came: closes this ID check without an ID (its age reports '
    'upheld). This person deleted their account, so the age check stays '
    'on their phone number: if they return, they still cannot use Dating '
    'until they verify with an ID document through support, and a late ID '
    "is handled here again. This can't be undone here.";
const kConsoleClosedNoId =
    'Closed: no ID came. The age check stays until this person verifies.';

/// Dismiss on an ID check asked by mistake: it lifts the age check
/// without an ID.
const kConfirmDismissIdCheck =
    'Dismiss (asked by mistake): closes this ID check with no action (its '
    'age reports not upheld) and lifts the age check without an ID. Use it '
    "only when asking was a mistake. $kConsoleNotOrigin This can't be undone "
    'here.';

/// Said after Ask for ID (the ID check waits in the queue).
const kConsoleAskedForId =
    'Asked for ID. A separate ID check case now holds the age reports and '
    "waits in the queue as Waiting for ID until support has seen this "
    "person's ID.";

/// Server round 3: the links between a case and its ID check.
const kConsoleOpenIdCase = 'Open its ID check';
const kConsoleOpenOrigin = 'Open the case it came from';

/// Said on an ID check waiting for the person's ID.
const kConsoleAwaitingIdNote =
    "This ID check is waiting for this person's ID email. Once support has "
    "seen it: Lift the age check if they are an adult, Confirm a minor if "
    "they aren't. If no ID comes: No ID came.";

/// I-5: said on an ID check closed as No ID came whose age check is live.
const kConsoleIdStillNeededNote =
    'ID still needed: this ID check was closed without an ID, and its age '
    "check stays until this person's ID email comes. Once support has seen "
    "it: Lift the age check if they are an adult, Confirm a minor if they "
    "aren't.";

/// I-6: the ID check's reference code, as the person's email gives it.
String consoleIdCode(String code) => 'ID check code: $code';

/// I-5: the queue's ID-check section.
const kConsoleIdSection = 'Waiting for ID / ID still needed';

/// I-5: a queue read the server refused as invalid (a kind it doesn't
/// know: a server older than this console).
const kConsoleQueueInvalid =
    "The server doesn't know this list yet, so it can't be shown. The "
    'console may be newer than the server: read again once the server is '
    'updated.';

/// Task 8 fix round 2: Lift hold never lifts or counts a CSAM hold, so a
/// case that holds only CSAM holds answers lifted: 0.
const kConsoleOtherHolds =
    "A hold another case placed isn't lifted here, and only the safety "
    "owner's CSAM lift ends a CSAM hold.";

/// A code check that outlived its time box: it may still have worked.
const kConsoleSlowCheck =
    'Checking the code took too long, so it may still have worked. Check '
    'your sign-in before you enter a code again.';

String consoleConfirmApprove(Object? position) =>
    "Approve: photo $position goes live on this person's profile, for "
    'others to see.';

String consoleConfirmRemove(Object? type) =>
    'Remove: takes this ${type == 'comment' ? 'comment' : 'post'} down for '
    "everyone. It can't be restored from the console.";

String consoleConfirmPublish(String country, Map<Object?, Object?> values) => [
  'Publish $country: these values become its live settings, as a new '
      'version:',
  const JsonEncoder.withIndent('  ').convert(values),
  if (values['same_gender_enabled'] == false)
    'Turning same gender off closes same-gender matches at once.',
].join('\n');

/// Asks before an irreversible decision: its consequence in plain words,
/// Cancel focused (Enter or Esc cancels). True only on the confirm button.
Future<bool> consoleConfirm(
  BuildContext context, {
  required String title,
  required String consequence,
  required String confirm,
}) async =>
    await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                child: Text(
                  consequence,
                  key: const ValueKey('console_confirm_text'),
                ),
              ),
            ),
            actions: [
              TextButton(
                key: const ValueKey('console_confirm_cancel'),
                autofocus: true,
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey('console_confirm_ok'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(confirm),
              ),
            ],
          ),
    ) ==
    true;

/// The widest a page's text runs (readable on a desktop screen).
const kConsoleMaxWidth = 960.0;

/// The moderator's role and routing, from whoami.
class ConsoleMe {
  const ConsoleMe({required this.role, required this.routing});

  final String role;
  final bool routing;

  bool get owner => role == 'safety_owner';
}

/// What the console reads for a fixed code. A missing case and a case the
/// moderator is a party to answer the same code, so they read the same.
String consoleReason(String? reason) => switch (reason) {
  'busy' => 'The server is busy. Try again in a moment.',
  'offline' => "Can't reach the server. Check your connection, then try again.",
  'claimed' => 'Another moderator is working on this case.',
  'case_unavailable' => "This case isn't available.",
  'same_decider' =>
    'A different person from the one who made the decision must decide this appeal.',
  'decider_unknown' =>
    "Nobody is recorded as making the original decision, so the console "
        "can't check that a different person decides. Only the safety owner "
        'can decide this appeal, from 24 hours after it was sent.',
  'appeal_unavailable' => "This appeal isn't open any more.",
  'photo_unavailable' => "This photo isn't available any more.",
  'session_unavailable' => "This check isn't available any more.",
  'safety_owner_only' => 'Only the safety owner can do this.',
  'not_moderator' => "This account isn't a moderator.",
  'mfa_required' =>
    'Your authenticator check has lapsed. Sign out, then sign in again.',
  'unauthorized' =>
    "We couldn't confirm your sign-in. Try again; if it keeps happening, "
        'sign out and sign in again.',
  'invalid' => 'Check what you entered.',
  'values_not_json' =>
    'The values must be a JSON object, like {"dating_enabled": true}.',
  'config:invalid_country' => 'Use a two-letter country code, like GH.',
  'config:invalid_values' =>
    "A value isn't the right type or is out of range. Nothing was published.",
  'config:unknown_key' =>
    "A key isn't a country setting: check its spelling. Nothing was published.",
  'config:invalid_tz' =>
    "The reference time zone isn't one the server knows (use a name like "
        'Africa/Accra). Nothing was published.',
  'config:invalid_lists' =>
    "A list isn't in the right form: the regions, faiths and ID documents "
        'are lists, the legal checklist is an object, and each region has a '
        'code. Nothing was published.',
  'config:checklist_keys_removed' =>
    'The legal checklist only grows: keep every item it already has. '
        'Nothing was published.',
  'config:invalid_regions' =>
    "The regions don't add up: each region once, open regions from the "
        'region list, and at least one open region while Dating is on. '
        'Nothing was published.',
  'config:no_calling_code' =>
    "This country isn't in the server's calling codes yet, so these "
        'settings would hide it from the phone check. Nothing was published.',
  'config:production_checks_failed' =>
    "The production checks didn't pass, so nothing was published.",
  // Spec 2 W7c (Task 8 fix round 1).
  'exists' =>
    'This request is already in the log with another decision. Decide it '
        'there instead.',
  'already_disclosed' =>
    'Something was already disclosed for this request. A disclosure can '
        'only be widened: keep every category already disclosed.',
  'consent_kind_required' =>
    'This case has a sextortion report or signal, so CSA can be recorded '
        "only as \"CSA 292, with the person's consent\", and only if the "
        "person agreed to it. If they didn't, add a note instead.",
  'hold_unavailable' =>
    "This hold isn't live any more, or it isn't one you can lift.",
  final String r when r.startsWith('config:') =>
    "The server didn't accept these values. Nothing was published.",
  _ => 'Something went wrong. Try again.',
};

/// A reason that is a moment's wait, not a refusal: said calmly.
bool consoleCalm(String? reason) =>
    const {'busy', 'offline', 'claimed'}.contains(reason);

/// A date the server sent, in UTC ("1 Dec 2026, 00:00 UTC"); '-' if none.
String consoleDate(Object? iso) {
  final d = iso is String ? DateTime.tryParse(iso)?.toUtc() : null;
  if (d == null) return '-';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day} ${months[d.month - 1]} ${d.year}, '
      '${two(d.hour)}:${two(d.minute)} UTC';
}

/// A line the console says after a read or an action.
class ConsoleLine {
  const ConsoleLine(this.text, {this.error = false});

  /// The line for a refused or failed answer.
  factory ConsoleLine.of(ConsoleAnswer r) =>
      ConsoleLine(consoleReason(r.reason), error: !consoleCalm(r.reason));

  final String text;
  final bool error;
}

/// A line, announced to a screen reader; red only for a refusal.
class ConsoleStatus extends StatelessWidget {
  const ConsoleStatus(this.line, {super.key, this.textKey});

  final ConsoleLine line;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colour = line.error ? scheme.error : scheme.onSurfaceVariant;
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(top: 2, right: 8),
              child: Icon(
                line.error ? Icons.error_outline : Icons.info_outline,
                size: 18,
                color: colour,
              ),
            ),
          ),
          Flexible(
            child: Text(
              line.text,
              key: textKey,
              style: TextStyle(color: colour),
            ),
          ),
        ],
      ),
    );
  }
}

/// A signed photo (it lives 60 s: an image that won't load says to read
/// the page again), labelled for a screen reader.
Widget consoleImage(Object? url, String label, {VoidCallback? onFailed}) {
  Widget box(String text) => SizedBox(
    width: 120,
    height: 120,
    child: ColoredBox(
      color: const Color(0x14000000),
      child: Center(child: Text(text, textAlign: TextAlign.center)),
    ),
  );
  return Semantics(
    container: true,
    image: true,
    label: url is String ? label : '$label, no image',
    child: ExcludeSemantics(
      child:
          url is String
              ? Image.network(
                url,
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  onFailed?.call();
                  return box("Couldn't load.\nRead again.");
                },
              )
              : box('No image'),
    ),
  );
}

/// Loading: a spinner and what is loading.
class ConsoleLoading extends StatelessWidget {
  const ConsoleLoading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ExcludeSemantics(child: CircularProgressIndicator()),
        const SizedBox(height: 12),
        Text(text),
      ],
    ),
  );
}

/// A read that failed: its line, and Try again unless it was refused.
class ConsoleRetry extends StatelessWidget {
  const ConsoleRetry({super.key, required this.answer, required this.onRetry});

  final ConsoleAnswer answer;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConsoleStatus(ConsoleLine.of(answer)),
        OutlinedButton(
          key: const ValueKey('console_retry'),
          onPressed: onRetry,
          child: const Text('Try again'),
        ),
      ],
    ),
  );
}

/// A page's frame: its title, a Read again button, its width kept readable.
class ConsoleFrame extends StatelessWidget {
  const ConsoleFrame({
    super.key,
    required this.title,
    required this.onRefresh,
    required this.child,
  });

  final String title;
  final VoidCallback? onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kConsoleMaxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('console_refresh'),
                  tooltip: 'Read again',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    ),
  );
}

/// Text fields never let the keyboard learn (the app's rule, kept here).
TextField consoleField({
  required Key key,
  required TextEditingController controller,
  required String label,
  TextInputType? keyboardType,
  Iterable<String>? autofillHints,
  ValueChanged<String>? onSubmitted,
  bool autofocus = false,
  int maxLines = 1,
}) => TextField(
  key: key,
  controller: controller,
  autofocus: autofocus,
  keyboardType: keyboardType,
  autofillHints: autofillHints,
  maxLines: maxLines,
  autocorrect: false,
  enableSuggestions: false,
  enableIMEPersonalizedLearning: false,
  textInputAction: maxLines == 1 ? TextInputAction.done : null,
  onSubmitted: onSubmitted,
  decoration: InputDecoration(labelText: label),
);

class ConsoleApp extends StatelessWidget {
  const ConsoleApp({super.key, required this.api, required this.auth});

  final ConsoleApi api;
  final ConsoleAuth auth;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: kConsoleTitle,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xFF2E7D32)),
    home: ConsoleGate(api: api, auth: auth),
  );
}

class ConsoleGate extends StatefulWidget {
  const ConsoleGate({super.key, required this.api, required this.auth});

  final ConsoleApi api;
  final ConsoleAuth auth;

  @override
  State<ConsoleGate> createState() => _ConsoleGateState();
}

class _ConsoleGateState extends State<ConsoleGate> {
  ConsoleSession? _session;
  ConsoleMe? _me;
  ConsoleLine? _line;
  bool _busy = false;
  bool _codeSent = false;
  bool _copied = false;

  /// A code check outlived its time box (Task 9): Check my sign-in.
  bool _slow = false;

  /// The TOTP key this console put on the clipboard (cleared later).
  String? _copiedKey;
  ConsoleEnrolment? _enrolment;
  final _phone = TextEditingController();
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ConsoleSession session;
    try {
      session = await widget.auth.session();
    } catch (_) {
      // Fix round 2: a check that fails reads as unreachable (Try again),
      // never a spinner that never ends.
      session = ConsoleSession.unreachable;
    }
    ConsoleMe? me;
    ConsoleLine? line;
    if (session == ConsoleSession.ready) {
      final r = await widget.api('whoami');
      if (r.ok) {
        me = ConsoleMe(
          role: r.data['role'] as String? ?? 'moderator',
          routing: r.data['sensitive_routing_allowed'] == true,
        );
      } else {
        line = ConsoleLine.of(r);
      }
    }
    if (session != ConsoleSession.needsEnrol) await _forgetKey();
    if (!mounted) return;
    setState(() {
      _session = session;
      _me = me;
      _line = line;
      _busy = false;
      _slow = false;
      _code.clear();
    });
  }

  Future<void> _retry() async {
    setState(() {
      _busy = true;
      _line = null;
    });
    await _refresh();
  }

  Future<void> _step(Future<bool> Function() action, String failed) async {
    setState(() {
      _busy = true;
      _line = null;
    });
    final bool ok;
    try {
      ok = await action();
    } on TimeoutException {
      // Task 9: the check may still have gone through; never "didn't work".
      if (!mounted) return;
      setState(() {
        _busy = false;
        _slow = true;
        _line = const ConsoleLine(kConsoleSlowCheck);
      });
      return;
    }
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _line = ConsoleLine(failed, error: true);
      });
      return;
    }
    await _refresh();
  }

  Future<void> _sendCode({bool again = false}) async {
    setState(() {
      _busy = true;
      _line = null;
    });
    final ok = await widget.auth.sendCode(_phone.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (again) {
        _line =
            ok
                ? const ConsoleLine('We sent a new code.')
                : const ConsoleLine(
                  "We couldn't send a new code. Wait a minute, then try "
                  'again.',
                  error: true,
                );
        return;
      }
      _codeSent = ok;
      _line =
          ok
              ? null
              : const ConsoleLine(
                "We couldn't send a code. Check the number starts with + "
                'and its country code.',
                error: true,
              );
    });
  }

  void _changeNumber() => setState(() {
    _codeSent = false;
    _code.clear();
    _line = null;
  });

  void _next() {
    if (_busy) return;
    if (!_codeSent) {
      _sendCode();
      return;
    }
    _step(
      () => widget.auth.verifyCode(_phone.text.trim(), _code.text.trim()),
      "That code didn't work.",
    );
  }

  void _verify(String? factorId) {
    if (_busy) return;
    _step(
      () => widget.auth.verifyTotp(_code.text.trim(), factorId: factorId),
      "That code didn't work.",
    );
  }

  Future<void> _enrol() async {
    setState(() {
      _busy = true;
      _line = null;
    });
    final e = await widget.auth.enrol();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _enrolment = e;
      _line =
          e == null
              ? const ConsoleLine(
                'Something went wrong. Try again.',
                error: true,
              )
              : null;
    });
  }

  Future<void> _copyKey(String secret) async {
    await Clipboard.setData(ClipboardData(text: secret));
    _copiedKey = secret;
    if (mounted) setState(() => _copied = true);
  }

  /// Empties the clipboard if this console put the key there. Task 9: it
  /// is never read first (on the web a read can ask the moderator for a
  /// lasting clipboard permission); the hint says it is emptied.
  ///
  /// Fix round 1 (review M-7): the key is forgotten, and "Key copied." with
  /// its hint goes, only once the empty write succeeds; a refused write
  /// (a tab without focus) is tried again on the next refresh.
  Future<void> _forgetKey() async {
    if (_copiedKey == null) return;
    try {
      await Clipboard.setData(const ClipboardData(text: ''));
      _copiedKey = null;
      _copied = false;
    } catch (_) {}
  }

  Future<void> _signOut({ConsoleLine? line}) async {
    Navigator.of(context).popUntil((r) => r.isFirst);
    await widget.auth.signOut();
    // The refresh below clears a copied key (signed out is not enrolment).
    if (!mounted) return;
    setState(() {
      _codeSent = false;
      _copied = false;
      _enrolment = null;
      _session = null;
      _phone.clear();
      _code.clear();
    });
    await _refresh();
    if (mounted && line != null) setState(() => _line = line);
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    if (_session == ConsoleSession.ready && me != null) {
      return ConsoleHome(
        api: widget.api,
        me: me,
        onSignOut: _signOut,
        onIdle: () => _signOut(line: const ConsoleLine(kConsoleIdleLine)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text(kConsoleTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AutofillGroup(
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                ..._form(context),
                if (_line case final line?)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: ConsoleStatus(
                      line,
                      textKey: const ValueKey('console_line'),
                    ),
                  ),
                if (_slow)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton(
                      key: const ValueKey('console_check_again'),
                      onPressed: _busy ? null : _retry,
                      child: const Text('Check my sign-in'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget get _signOutButton => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextButton(onPressed: _signOut, child: const Text('Sign out')),
  );

  Widget get _retryButton => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: OutlinedButton(
      key: const ValueKey('console_retry'),
      onPressed: _busy ? null : _retry,
      child: const Text('Try again'),
    ),
  );

  List<Widget> _form(BuildContext context) {
    switch (_session) {
      case null:
        return const [ConsoleLoading('Checking your session.')];
      case ConsoleSession.signedOut:
        return [
          const Text('Sign in with your Attune phone number.'),
          consoleField(
            key: const ValueKey('console_phone'),
            controller: _phone,
            label: 'Phone number (with +country code)',
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            autofocus: true,
            onSubmitted: (_) => _next(),
          ),
          if (_codeSent) ...[
            const SizedBox(height: 8),
            Text('We sent a code to ${_phone.text.trim()}.'),
            consoleField(
              key: const ValueKey('console_code'),
              controller: _code,
              label: 'Code',
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              autofocus: true,
              onSubmitted: (_) => _next(),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: const ValueKey('console_resend'),
                  onPressed: _busy ? null : () => _sendCode(again: true),
                  child: const Text('Send a new code'),
                ),
                TextButton(
                  key: const ValueKey('console_change_number'),
                  onPressed: _busy ? null : _changeNumber,
                  child: const Text('Use a different number'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('console_next'),
            onPressed: _busy ? null : _next,
            child: Text(_codeSent ? 'Sign in' : 'Send code'),
          ),
        ];
      case ConsoleSession.needsEnrol:
        final enrolment = _enrolment;
        return [
          const Text(
            'Set up your authenticator app. Every sign-in needs its code.',
          ),
          const SizedBox(height: 12),
          if (enrolment == null)
            FilledButton(
              key: const ValueKey('console_enrol'),
              onPressed: _busy ? null : _enrol,
              child: const Text('Set up'),
            )
          else ...[
            const Text(
              'In your authenticator app, add an account by its key, then '
              'enter the code it shows.',
            ),
            const SizedBox(height: 8),
            SelectableText('Key: ${enrolment.secret}'),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  key: const ValueKey('console_copy_key'),
                  onPressed: () => _copyKey(enrolment.secret),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy the key'),
                ),
                if (_copied)
                  Semantics(liveRegion: true, child: const Text('Key copied.')),
              ],
            ),
            if (_copied) const Text(kConsoleClipboardHint),
            ..._totp(factorId: enrolment.factorId),
          ],
          _signOutButton,
        ];
      case ConsoleSession.needsTotp:
        return [
          const Text('Enter the code from your authenticator app.'),
          ..._totp(),
          _signOutButton,
        ];
      case ConsoleSession.unreachable:
        return [
          const ConsoleStatus(
            ConsoleLine("Can't reach the server to check your sign-in."),
          ),
          _retryButton,
          _signOutButton,
        ];
      case ConsoleSession.ready:
        return [
          if (_line == null)
            const ConsoleLoading('Checking your moderator access.')
          else
            _retryButton,
          _signOutButton,
        ];
    }
  }

  List<Widget> _totp({String? factorId}) => [
    consoleField(
      key: const ValueKey('console_totp'),
      controller: _code,
      label: 'Authenticator code',
      keyboardType: TextInputType.number,
      autofillHints: const [AutofillHints.oneTimeCode],
      autofocus: true,
      onSubmitted: (_) => _verify(factorId),
    ),
    const SizedBox(height: 12),
    FilledButton(
      key: const ValueKey('console_verify'),
      onPressed: _busy ? null : () => _verify(factorId),
      child: const Text('Verify'),
    ),
  ];
}

/// The console's pages, by destination.
enum ConsolePage {
  queue('Queue', Icons.inbox_outlined),
  appeals('Appeals', Icons.gavel_outlined),
  signals('Signals', Icons.sensors_outlined),
  photos('Photos', Icons.photo_outlined),
  verifications('Verifications', Icons.verified_user_outlined),
  opinions('Opinions', Icons.forum_outlined),
  countries('Countries', Icons.public_outlined),
  lawEnforcement('Law enforcement', Icons.policy_outlined),
  csamHolds('CSAM holds', Icons.shield_outlined),
  audit('Audit', Icons.history_outlined);

  const ConsolePage(this.label, this.icon);

  final String label;
  final IconData icon;
}

class ConsoleHome extends StatefulWidget {
  const ConsoleHome({
    super.key,
    required this.api,
    required this.me,
    required this.onSignOut,
    this.onIdle,
  });

  final ConsoleApi api;
  final ConsoleMe me;
  final VoidCallback onSignOut;

  /// Called once the console has gone untouched for [kConsoleIdle].
  final VoidCallback? onIdle;

  @override
  State<ConsoleHome> createState() => _ConsoleHomeState();
}

class _ConsoleHomeState extends State<ConsoleHome> {
  ConsolePage _page = ConsolePage.queue;
  Timer? _idle;

  @override
  void initState() {
    super.initState();
    // Any pointer or key, on any page or dialog, is activity.
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
    _poke();
  }

  @override
  void dispose() {
    _idle?.cancel();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  void _onPointer(PointerEvent _) => _poke();

  bool _onKey(KeyEvent _) {
    _poke();
    return false;
  }

  void _poke() {
    _idle?.cancel();
    _idle = Timer(kConsoleIdle, () => widget.onIdle?.call());
  }

  Future<void> _openCase(String id) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CaseScreen(api: widget.api, me: widget.me, caseId: id),
    ),
  );

  Widget _body() => switch (_page) {
    ConsolePage.queue => QueueScreen(
      key: const ValueKey('queue'),
      api: widget.api,
      title: 'Open cases',
      kinds: const {'report', 'photo', 'verification', 'csam_hit'},
      // W7 final client fix (I-5): Waiting for ID / ID still needed first.
      idChecks: true,
      onOpen: _openCase,
    ),
    ConsolePage.appeals => QueueScreen(
      key: const ValueKey('appeals'),
      api: widget.api,
      title: 'Open appeals',
      kinds: const {'appeal'},
      onOpen: _openCase,
    ),
    ConsolePage.signals => QueueScreen(
      key: const ValueKey('signals'),
      api: widget.api,
      title: 'Open signals',
      kinds: const {'signal'},
      onOpen: _openCase,
    ),
    ConsolePage.photos => PhotosScreen(api: widget.api),
    ConsolePage.verifications => VerificationsScreen(api: widget.api),
    ConsolePage.opinions => OpinionsScreen(api: widget.api),
    ConsolePage.countries => CountriesScreen(api: widget.api, me: widget.me),
    ConsolePage.lawEnforcement => LawEnforcementScreen(
      api: widget.api,
      me: widget.me,
    ),
    ConsolePage.csamHolds => CsamHoldsScreen(api: widget.api, me: widget.me),
    ConsolePage.audit => AuditScreen(api: widget.api),
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('$kConsoleTitle · ${_page.label}'),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(
            child: Text(widget.me.owner ? 'Safety owner' : 'Moderator'),
          ),
        ),
        TextButton(onPressed: widget.onSignOut, child: const Text('Sign out')),
      ],
    ),
    body: Row(
      children: [
        // Every page reachable at any window height: the rail scrolls.
        LayoutBuilder(
          builder:
              (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: NavigationRail(
                      selectedIndex: _page.index,
                      labelType: NavigationRailLabelType.all,
                      onDestinationSelected:
                          (i) => setState(() => _page = ConsolePage.values[i]),
                      destinations: [
                        for (final p in ConsolePage.values)
                          NavigationRailDestination(
                            icon: Icon(p.icon),
                            label: Text(p.label),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _body()),
      ],
    ),
  );
}
