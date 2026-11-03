import 'dart:async';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/utils/constants.dart';
import 'package:attune/core/utils/url_launcher_utils.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/safety/data/child_report_service.dart';
import 'package:attune/features/settings/models/settings_config.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Settings -> Safety, and Settings -> Support (Spec 1 §3.15, W6c): the
/// same screen from both, so it is found from either.
SettingsConfig childReportSetting(
  BuildContext context, {
  required String id,
  required int order,
}) {
  final loc = AppLocalizations.of(context)!;
  return SettingsConfig(
    id: id,
    title: loc.support_childReportTitle,
    subtitle: loc.support_childReportSubtitle,
    icon: Icons.child_care_outlined,
    type: SettingsItemType.navigation,
    routeName: RouteNames.reportChildConcern,
    onTap: () => context.push(RouteNames.reportChildConcern),
    iconColor: Colors.red,
    order: order,
  );
}

/// "Report a concern about a child" (Spec 1 §3.15, W6c). A person on the
/// team reads every report; the reported person is never told, and the
/// form never asks who it is. Never animated (§2.2); the app shell's quick
/// exit sits above it.
class ReportChildConcernScreen extends ConsumerStatefulWidget {
  const ReportChildConcernScreen({super.key});

  @override
  ConsumerState<ReportChildConcernScreen> createState() =>
      _ReportChildConcernScreenState();
}

class _ReportChildConcernScreenState
    extends ConsumerState<ReportChildConcernScreen> {
  static const maxLength = 2000;

  final _details = TextEditingController();
  ChildReportPlace? _place;
  bool _busy = false;
  bool _sent = false;
  String? _error;

  /// The limit and a refusal offer the child-safety address, tappable.
  bool _offerEmail = false;

  /// What the server counts: char_length, code points (batch 8 I-1). A
  /// skin-toned emoji is one character on screen and two here.
  int get _length => _details.text.runes.length;

  bool get _tooLong => _length > maxLength;

  bool get _canSend => _details.text.trim().isNotEmpty && !_tooLong;

  AppLocalizations get _loc => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    _details.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  /// "Dating" only for someone who uses it (D20: nothing about Dating on
  /// the Relationship path, and nothing kept on the phone).
  bool _showsDating() {
    final userId = ref.read(homeAuthProvider).currentUser?.id;
    if (userId == null) return false;
    final home = ref.watch(homeStateProvider(userId));
    return home.path == AppPath.dating || (home.dating?.enrolled ?? false);
  }

  String _placeLabel(ChildReportPlace place) => switch (place) {
    ChildReportPlace.chat => _loc.support_childReportChat,
    ChildReportPlace.stories => _loc.support_childReportStories,
    ChildReportPlace.opinions => _loc.support_childReportOpinions,
    ChildReportPlace.dating => _loc.support_childReportDating,
    ChildReportPlace.other => _loc.support_childReportElsewhere,
  };

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.settings);
    }
  }

  Future<void> _send() async {
    if (_busy || !_canSend) return;
    setState(() {
      _busy = true;
      _error = null;
      _offerEmail = false;
    });
    final outcome = await ref
        .read(childReportServiceProvider)
        .send(place: _place, details: _details.text);
    if (!mounted) return;
    final loc = _loc;
    setState(() {
      _busy = false;
      switch (outcome) {
        case ChildReportOutcome.sent:
          _sent = true;
          _details.clear();
          _place = null;
        case ChildReportOutcome.limit:
          _error = loc.support_childReportLimit(AppConstants.childSafetyEmail);
          _offerEmail = true;
        case ChildReportOutcome.invalid:
          _error = loc.support_childReportInvalid(
            AppConstants.childSafetyEmail,
          );
          _offerEmail = true;
        case ChildReportOutcome.failed:
          _error = loc.support_childReportFailed;
      }
    });
    SemanticsService.announce(
      _sent ? loc.support_childReportThanks : _error!,
      Directionality.of(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = _loc;
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurface,
    );
    if (_sent) {
      return FlowFrame(
        title: loc.support_childReportTitle,
        onBack: _leave,
        body: Semantics(
          liveRegion: true,
          child: Text(loc.support_childReportThanks, style: textStyle),
        ),
        actions: [
          FlowPrimaryButton(
            label: loc.support_childReportDone,
            onPressed: _leave,
          ),
        ],
      );
    }
    final places = [
      for (final place in ChildReportPlace.values)
        if (place != ChildReportPlace.dating || _showsDating()) place,
    ];
    final error = _error;
    return FlowFrame(
      title: loc.support_childReportTitle,
      onBack: _leave,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(loc.support_childReportBody, style: textStyle),
          const SizedBox(height: 20),
          Semantics(
            header: true,
            child: Text(
              loc.support_childReportWhere,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final place in places)
                ChoiceChip(
                  label: Text(_placeLabel(place)),
                  selected: _place == place,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (selected) {
                    HapticFeedback.selectionClick();
                    setState(() => _place = selected ? place : null);
                  },
                ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _details,
            minLines: 4,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            // A shared phone: the keyboard learns and suggests nothing from
            // a report (Gboard's incognito; batch 8 review M-6).
            enableSuggestions: false,
            autocorrect: false,
            enableIMEPersonalizedLearning: false,
            decoration: InputDecoration(
              labelText: loc.support_childReportDetails,
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_tooLong) ...[
            const SizedBox(height: 8),
            FlowErrorLine(
              text: loc.support_childReportTooLong,
              style: theme.textTheme.bodyMedium,
              liveRegion: true,
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 8),
            // Read out by _send (SemanticsService), once per failure.
            FlowErrorLine(text: error, style: theme.textTheme.bodyMedium),
            if (_offerEmail)
              FlowTextLink(
                label: AppConstants.childSafetyEmail,
                alignment: AlignmentDirectional.centerStart,
                onPressed:
                    () => UrlLauncherUtils.launchEmail(
                      context: context,
                      email: AppConstants.childSafetyEmail,
                    ),
              ),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              loc.support_childReportCount(_length, maxLength),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.support_childReportSend,
          busy: _busy,
          onPressed: _canSend ? _send : null,
        ),
      ],
    );
  }
}

/// Support resources' link to the report (Spec 1 §3.15 "also linked from
/// the Support screen", §5.4 names it; P-28, batch 8 review M-4). Signed in
/// only, like the route: the report needs the account.
class ReportChildConcernLink extends ConsumerWidget {
  const ReportChildConcernLink({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(homeAuthProvider).currentUser == null) {
      return const SizedBox.shrink();
    }
    final loc = AppLocalizations.of(context)!;
    return InfoRowWidget(
      title: loc.support_childReportTitle,
      subtitle: loc.support_childReportSubtitle,
      icon: Icons.child_care_outlined,
      showAvatar: false,
      showTrailingArrow: true,
      onTap: () => context.push(RouteNames.reportChildConcern),
    );
  }
}
