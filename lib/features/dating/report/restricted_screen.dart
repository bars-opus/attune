// Spec 2 W7a (§3.7 Restricted card and screen, Appeal; §3.15 Restricted,
// hold, appeal; §6.3; D8): what a restricted person reads at
// /dating/restricted. The category first ("About:" for a hold, "Reason:"
// otherwise, in the person's own plain words, never the reporter's), then
// what it means; [Appeal] once, where the restriction allows it, and
// [Contact support]; the age check's [Verify with ID] goes through support
// (Ruling R-56). Never who reported, what they wrote, or the evidence (the
// server sends none of it). Nothing here moves; the appeal waits offline;
// another account on the phone starts from nothing.
//
// Task 4 rulings (task-4-report.md): a busy read is a calm line and a
// retry, a failed read offline says offline (R-T4-1); nothing read on
// opening announces, only the appeal just sent (R-T4-2); the appeal counts
// code points as the server does (R-T4-3); an appeal on its way survives
// the sheet: back and the barrier do nothing, a pop from outside still
// re-reads the screen once it lands, and the request key is held per
// account, so a sheet opened again after busy sends the same request
// (R-T4-4, Task 3's I-1); already_appealed and appeal_unavailable read the
// screen again (R-T4-5); nothing here waits on the phone check (R-54); the
// age check's one way to support is Verify with ID (R-T4-8). The appeal
// sheet is appeal_sheet.dart (fix round 1, M-8).
//
// Fix round 1 (task-4-review.md): a hold leaves the chats open (R-53), so
// the hold leads to Conversations (K-2); Verify with ID says what it does
// and shows the support address, and an email app that doesn't open is
// said in the app's own words with the address (M-3); the accepted screen
// leads back to Me, where Resume is (M-6).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/utils/constants.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/widgets/app_content_width.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_home.dart'
    show DatingHomeState;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/appeal_sheet.dart';
import 'package:attune/features/dating/report/dating_report_providers.dart';
import 'package:attune/features/dating/routes/dating_root_back.dart';
import 'package:attune/features/dating/routes/dating_routes.dart'
    show DatingPaths;
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// §6.3 "Category shown": the plain label the restricted person reads
/// (never the reporter's words; plan copy for the reviewers).
String datingRestrictionLabel(AppLocalizations loc, DatingReportCategory? c) =>
    switch (c) {
      DatingReportCategory.underageRisk => loc.dating_reasonUnderage,
      DatingReportCategory.csam => loc.dating_reasonCsam,
      DatingReportCategory.childSafety => loc.dating_reasonChildSafety,
      DatingReportCategory.threatToLife => loc.dating_reasonThreatToLife,
      DatingReportCategory.sextortion => loc.dating_reasonSextortion,
      DatingReportCategory.romanceScam => loc.dating_reasonMoney,
      DatingReportCategory.threats => loc.dating_reasonThreats,
      DatingReportCategory.entrapment => loc.dating_reasonEntrapment,
      DatingReportCategory.harassment => loc.dating_reasonHarassment,
      DatingReportCategory.explicitContent => loc.dating_reasonExplicit,
      DatingReportCategory.impersonation => loc.dating_reasonImpersonation,
      DatingReportCategory.hidingRelationship => loc.dating_reasonMarried,
      DatingReportCategory.spam => loc.dating_reasonSpam,
      DatingReportCategory.other || null => loc.dating_reasonOther,
    };

/// The support email to open. Fix round 2 (N-1): the age check's email
/// carries a discreet subject, "Attune ID check" (no Dating, no number,
/// nothing of the person), so support can sort it. W7 final client fix
/// (I-6): with the check's reference [code] ("Attune ID check: AB23CD45"),
/// so a moderator finds the waiting case by it; no phone number is asked
/// for any more. Contact support: no subject. Never a body.
Uri datingSupportMail({bool idCheck = false, String? code}) => Uri.parse(
  idCheck
      ? 'mailto:${AppConstants.supportEmail}'
          '?subject=${Uri.encodeComponent(code == null ? 'Attune ID check' : 'Attune ID check: $code')}'
      : 'mailto:${AppConstants.supportEmail}',
);

/// Opens [mail] (fix round 1, M-3); throws when no email app opens, which
/// the screen says in its own words with the address (never the shared
/// util's English snackbar).
typedef DatingSupportContact =
    Future<void> Function(BuildContext context, Uri mail);

final datingSupportContactProvider = Provider<DatingSupportContact>(
  (ref) => (context, mail) async {
    final opened = await launchUrl(mail);
    if (!opened) throw StateError('no email app');
  },
);

class DatingRestrictedScreen extends ConsumerStatefulWidget {
  const DatingRestrictedScreen({super.key});

  @override
  ConsumerState<DatingRestrictedScreen> createState() =>
      _DatingRestrictedScreenState();
}

class _DatingRestrictedScreenState
    extends ConsumerState<DatingRestrictedScreen> {
  /// R-T4-2: the account whose appeal was just sent here; only then is
  /// the sent line read out (an appeal read on opening never announces).
  String? _sentBy;

  /// M-3: the account whose email app didn't open here.
  String? _noMailFor;

  Future<void> _contact(
    String? account, {
    bool idCheck = false,
    String? code,
  }) async {
    try {
      await ref.read(datingSupportContactProvider)(
        context,
        datingSupportMail(idCheck: idCheck, code: code),
      );
    } catch (_) {
      if (!mounted || ref.read(datingAccountProvider) != account) return;
      setState(() => _noMailFor = account);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final account = ref.watch(datingAccountProvider);
    final read = ref.watch(datingRestrictionProvider(account));
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    void retry() => ref.invalidate(datingRestrictionProvider(account));
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(
          leading: datingRootBackButton(context),
          title: Text(loc.flow_slotDatingTitle),
        ),
        body: SafeArea(
          child: ListView(
            padding: AppContentWidth.padded(
              context,
              const EdgeInsets.all(Spacing.md),
            ),
            children: switch (read) {
              AsyncData(value: final r) when r.ok => _body(
                context,
                loc,
                account,
                r,
              ),
              // R-T4-1: busy is a calm line (the server's lock wait); a
              // retry is the same read.
              AsyncData(value: final r) when r.reason == 'busy' => [
                DatingCalmLine(loc.dating_busy),
                FlowSecondaryButton(label: loc.dating_retry, onPressed: retry),
              ],
              AsyncData() || AsyncError() => [
                if (!online)
                  DatingCalmLine(loc.dating_offline)
                else
                  FlowErrorLine(
                    text: loc.dating_errorGeneric,
                    liveRegion: true,
                  ),
                const SizedBox(height: Spacing.sm),
                FlowSecondaryButton(label: loc.dating_retry, onPressed: retry),
              ],
              // §3.15: never animated; R-T4-2: never announced.
              _ => [_Para(loc.dating_restrictedLoading)],
            },
          ),
        ),
      ),
    );
  }

  Future<void> _appeal(String? account, String restrictionId) async {
    final readAgain = await showDatingAppealSheet(
      context,
      account: account,
      restrictionId: restrictionId,
    );
    if (!readAgain || !mounted) return;
    if (ref.read(datingAccountProvider) != account) return;
    setState(() => _sentBy = account);
    ref.invalidate(datingRestrictionProvider(account));
  }

  List<Widget> _body(
    BuildContext context,
    AppLocalizations loc,
    String? account,
    DatingRestrictionRead read,
  ) {
    final r = read.restriction;
    if (r == null) {
      // Final client fix (I-4, R-53): an accepted appeal leaves Dating
      // paused until Resume, so "open again" only when the home (this
      // account's) reads active, as the Me card one tap away says.
      final home = ref.watch(datingHomeProvider(account));
      final active =
          !home.hasError && home.valueOrNull?.state == DatingHomeState.active;
      return [
        _Para(
          !read.appealAccepted
              ? loc.dating_restrictedNone
              : active
              ? loc.dating_appealAccepted
              : loc.dating_appealAcceptedPaused,
          key: const ValueKey('dating_restricted_lifted'),
        ),
        // M-6: back to Me, where the section offers Resume (R-53).
        if (read.appealAccepted)
          FlowPrimaryButton(
            key: const ValueKey('dating_restricted_done'),
            label: loc.dating_done,
            onPressed: () => context.go(datingMeLocation()),
          ),
      ];
    }
    final noMail = _noMailFor != null && _noMailFor == account;
    final label = datingRestrictionLabel(loc, r.category);
    final appeal = r.appeal;
    final age = r.type == DatingRestrictionType.ageReview;
    return [
      if (r.type == DatingRestrictionType.hold)
        _Para(
          loc.dating_restrictedAbout(label),
          key: const ValueKey('dating_restricted_category'),
        )
      else if (r.type == DatingRestrictionType.suspended)
        _Para(
          loc.dating_restrictedReason(label),
          key: const ValueKey('dating_restricted_category'),
        ),
      ...switch (r.type) {
        DatingRestrictionType.hold => [
          // Final client fix (I-3): the spec's interim line (not a decision
          // yet, 24 hours) only for a P0 report's interim hold; any other
          // hold (a moderator's, CSAM, carried, or rejected on appeal)
          // makes no time promise.
          // Spec 2 W8b (W7 carry M-6): and only while a person reviews.
          _Para(
            r.interimHold && read.staffed
                ? loc.dating_restrictedHold
                : loc.dating_restrictedHoldPlain,
            key: const ValueKey('dating_restricted_hold_line'),
          ),
          // K-2 (R-53): a hold leaves the chats open (reading, reporting;
          // the server stops sending).
          FlowSecondaryButton(
            key: const ValueKey('dating_restricted_chats'),
            label: loc.dating_chatsTitle,
            onPressed: () => context.push(DatingPaths.chats),
          ),
          const SizedBox(height: Spacing.sm),
        ],
        DatingRestrictionType.ageReview => [
          _Para(loc.dating_sectionAgeReview),
          // R-56: a moderator lifts it; the way there is support.
          FlowPrimaryButton(
            key: const ValueKey('dating_restricted_verify'),
            label: loc.dating_restrictedVerifyId,
            onPressed:
                () => _contact(account, idCheck: true, code: r.idCheckCode),
          ),
          const SizedBox(height: Spacing.sm),
          // M-3: what the button does, and the address (selectable).
          _Para(
            loc.dating_restrictedVerifyHelp(AppConstants.supportEmail),
            selectable: true,
          ),
          // I-6: the check's reference code, to copy into the email (the
          // subject carries it too); spelt out for a screen reader.
          if (r.idCheckCode case final code?)
            _Para(
              loc.dating_restrictedIdCode(code),
              key: const ValueKey('dating_restricted_id_code'),
              selectable: true,
              spoken: loc.dating_restrictedIdCode(code.split('').join(' ')),
            ),
        ],
        DatingRestrictionType.suspended when r.endsAt == null => [
          _Para(loc.dating_restrictedClosed),
        ],
        DatingRestrictionType.suspended => [
          _Para(
            loc.dating_restrictedUntil(
              MyDateFormat.toDate(r.endsAt!.toLocal()),
            ),
          ),
          _Para(loc.dating_restrictedMeans),
        ],
      },
      if (appeal?.state == DatingAppealState.open)
        // Spec 2 W8b (W7 carry M-6): no review time in testing.
        _Para(
          read.staffed ? loc.dating_appealSent : loc.dating_appealSentTesting,
          key: const ValueKey('dating_restricted_appeal_state'),
          live: _sentBy != null && _sentBy == account,
        )
      else if (appeal?.state == DatingAppealState.rejected)
        _Para(
          loc.dating_appealRejected,
          key: const ValueKey('dating_restricted_appeal_state'),
        ),
      if (r.canAppeal)
        FlowPrimaryButton(
          key: const ValueKey('dating_restricted_appeal'),
          label: loc.dating_appeal,
          onPressed: () => _appeal(account, r.id),
        ),
      // R-T4-8: the age check's one way to support is Verify with ID.
      if (!age) ...[
        const SizedBox(height: Spacing.sm),
        FlowSecondaryButton(
          key: const ValueKey('dating_restricted_support'),
          label: loc.flow_holdContact,
          onPressed: () => _contact(account),
        ),
      ],
      // M-3: no email app opened: the address, in the app's own words.
      if (noMail) ...[
        const SizedBox(height: Spacing.sm),
        _Para(
          loc.dating_restrictedNoMail(AppConstants.supportEmail),
          key: const ValueKey('dating_restricted_no_mail'),
          live: true,
          selectable: true,
        ),
      ],
    ];
  }
}

/// One paragraph of the screen: never animated; [live] only for the line
/// a person's own action just brought (R-T4-2).
class _Para extends StatelessWidget {
  const _Para(
    this.text, {
    super.key,
    this.live = false,
    this.selectable = false,
    this.spoken,
  });

  final String text;
  final bool live;

  /// M-3: a line with the support address can be copied.
  final bool selectable;

  /// I-6: what a screen reader says instead (the code, letter by letter).
  final String? spoken;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;
    final line =
        selectable
            ? SelectableText(text, style: style)
            : Text(text, style: style);
    return Semantics(
      liveRegion: live,
      child: Padding(
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        child:
            spoken == null
                ? line
                : Semantics(
                  label: spoken,
                  excludeSemantics: true,
                  child: line,
                ),
      ),
    );
  }
}
