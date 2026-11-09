// Spec 2 §3.4: the introduction card, person first, photo after, read in
// the order it shows (§3.15 D12). D12 shows it for the person's own profile
// (R-38: no "Why you two" and no actions, which need another person); W5b's
// Today adds both through [DatingCardView.trailing]. Never the date of
// birth, the side, or who the person would like to meet.
import 'dart:typed_data';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_colors.dart'
    show flowAccent;
import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/features/dating/setup/prompts_step.dart'
    show datingPromptText;
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class DatingCard {
  const DatingCard({
    this.displayName,
    this.age,
    this.regionNameKey,
    this.intention,
    this.timeline,
    this.childrenHave,
    this.childrenWant,
    this.identity,
    this.specific,
    this.specificText,
    this.pronouns,
    this.faith,
    this.denomination,
    this.marital,
    this.prompts = const [],
    this.photosAfterMutual = false,
    this.photoIds = const [],
  });

  final String? displayName;
  final int? age;
  final String? regionNameKey;
  final String? intention;
  final String? timeline;
  final bool? childrenHave;
  final String? childrenWant;
  final String? identity;
  final String? specific;
  final String? specificText;
  final String? pronouns;
  final String? faith;
  final String? denomination;
  final String? marital;
  final List<(String, String)> prompts;
  final bool photosAfterMutual;
  final List<String> photoIds;

  /// The same card showing only [ids] of its photos (D12: Task 10's photo
  /// rule decides which may show).
  DatingCard withPhotos(List<String> ids) => DatingCard(
    displayName: displayName,
    age: age,
    regionNameKey: regionNameKey,
    intention: intention,
    timeline: timeline,
    childrenHave: childrenHave,
    childrenWant: childrenWant,
    identity: identity,
    specific: specific,
    specificText: specificText,
    pronouns: pronouns,
    faith: faith,
    denomination: denomination,
    marital: marital,
    prompts: prompts,
    photosAfterMutual: photosAfterMutual,
    photoIds: ids,
  );

  /// Never printed: the card is the person's own answers.
  @override
  String toString() => 'DatingCard(…)';

  factory DatingCard.fromJson(Map<String, dynamic> j) {
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    final gender = j['gender'] is Map ? j['gender'] as Map : const {};
    final faith = j['faith'] is Map ? j['faith'] as Map : const {};
    final photos =
        j['photos'] is List
            ? (j['photos'] as List).whereType<Map>().toList()
            : <Map>[];
    photos.sort(
      (a, b) => ((a['position'] as int?) ?? 0).compareTo(
        (b['position'] as int?) ?? 0,
      ),
    );
    return DatingCard(
      displayName: text(j['display_name']),
      age: j['age'] is int ? j['age'] as int : null,
      regionNameKey: text(j['region_name_key']),
      intention: text(j['intention']),
      timeline: text(j['marriage_timeline']),
      childrenHave:
          j['children_have'] is bool ? j['children_have'] as bool : null,
      childrenWant: text(j['children_want']),
      identity: text(gender['identity']),
      specific: text(gender['specific']),
      specificText: text(gender['specific_text']),
      pronouns: text(j['pronouns']),
      faith: text(faith['faith']),
      denomination: text(faith['denomination']),
      marital: text(j['marital']),
      prompts: [
        if (j['prompts'] is List)
          for (final p in (j['prompts'] as List).whereType<Map>())
            if (p['prompt_id'] is String && p['answer'] is String)
              (p['prompt_id'] as String, p['answer'] as String),
      ],
      photosAfterMutual: j['photos_after_mutual'] == true,
      photoIds: [
        for (final p in photos)
          if (p['id'] is String) p['id'] as String,
      ],
    );
  }
}

String? datingIntentionLine(AppLocalizations loc, DatingCard c) => switch (c
    .intention) {
  'marriage' => switch (c.timeline) {
    'within_two_years' => loc.dating_cardMarriageSoon,
    'few_years' => loc.dating_cardMarriageFew,
    'no_set_time' => loc.dating_cardMarriageNone,
    _ => loc.dating_cardMarriage,
  },
  'committed' => loc.dating_cardCommitted,
  'companionship' => loc.dating_cardCompanionship,
  'not_sure' => loc.dating_cardNotSure,
  _ => null,
};

String? _identity(AppLocalizations loc, String? v) => switch (v) {
  'woman' => loc.dating_identityWoman,
  'man' => loc.dating_identityMan,
  'non_binary' => loc.dating_identityNonBinary,
  _ => null,
};

String? _specific(AppLocalizations loc, DatingCard c) =>
    c.specificText ??
    switch (c.specific) {
      'trans_woman' => loc.dating_specificTransWoman,
      'trans_man' => loc.dating_specificTransMan,
      'genderfluid' => loc.dating_specificGenderfluid,
      'genderqueer' => loc.dating_specificGenderqueer,
      'agender' => loc.dating_specificAgender,
      'intersex' => loc.dating_specificIntersex,
      _ => null,
    };

/// Gender, the specific term and pronouns, as the person chose to show
/// them (§3.4; null when none is shown).
String? datingGenderLine(AppLocalizations loc, DatingCard c) =>
    _join([_identity(loc, c.identity), _specific(loc, c), c.pronouns]);

/// Faith and denomination, when shown.
String? datingFaithLine(AppLocalizations loc, DatingCard c) => _join([
  if (c.faith != null) datingListName(loc, 'dating_faith_${c.faith}'),
  if (c.denomination != null)
    datingListName(loc, 'dating_denomination_${c.denomination}'),
]);

/// Widowed or Divorced, when shown.
String? datingMaritalLine(AppLocalizations loc, DatingCard c) => switch (c
    .marital) {
  'widowed' => loc.dating_maritalWidowed,
  'divorced' => loc.dating_maritalDivorced,
  _ => null,
};

String? _join(List<String?> parts) {
  final shown = [
    for (final p in parts)
      if (p != null) p,
  ];
  return shown.isEmpty ? null : shown.join(' · ');
}

/// The optional lines, only those the person chose to show (§3.4).
List<String> datingShownLines(AppLocalizations loc, DatingCard c) => [
  for (final line in [
    datingGenderLine(loc, c),
    datingFaithLine(loc, c),
    datingMaritalLine(loc, c),
  ])
    if (line != null) line,
];

/// A text link that starts at the start edge, wrapped text included (T11
/// fix 1, M-8), and reads as off when [onPressed] is null (M-4). Styled as
/// FlowTextLink, which stays as it is for the sign-up screens.
class DatingStartLink extends StatelessWidget {
  const DatingStartLink({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: flowAccent(context),
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w),
      ),
      child: Text(label, textAlign: TextAlign.start),
    ),
  );
}

class DatingCardView extends StatelessWidget {
  const DatingCardView({
    super.key,
    required this.card,
    this.photos = const [],
    this.photosHidden = false,
    this.onShowPhotos,
    this.trailing,
  });

  final DatingCard card;

  /// The photos' bytes, in card order (memory only; the caller evicts).
  final List<Uint8List> photos;
  final bool photosHidden;
  final VoidCallback? onShowPhotos;

  /// A widget after a part ('heading', 'intention', 'prompts', 'children',
  /// 'gender', 'faith', 'marital', 'photos'): D12's edit links; W5b's
  /// reasons and actions. Called for every part, shown or not.
  final Widget? Function(String part)? trailing;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    Widget? after(String part) => trailing?.call(part);
    final region =
        card.regionNameKey == null
            ? null
            : datingListName(loc, card.regionNameKey!);
    final intention = datingIntentionLine(loc, card);
    final heading = [
      Semantics(
        header: true,
        child: Text(
          card.age == null
              ? (card.displayName ?? '')
              : loc.dating_cardHeading(card.displayName ?? '', card.age!),
          style: theme.textTheme.headlineSmall,
        ),
      ),
      if (region != null) Text(region, style: theme.textTheme.bodyMedium),
      if (after('heading') case final w?) w,
    ];
    final intentionPart = [
      if (intention != null) Text(intention, style: theme.textTheme.bodyLarge),
      if (after('intention') case final w?) w,
    ];
    final prompts = [
      for (final (id, answer) in card.prompts) ...[
        const SizedBox(height: Spacing.sm),
        Text(datingPromptText(loc, id), style: theme.textTheme.titleSmall),
        Text(answer, style: theme.textTheme.bodyLarge),
      ],
      if (after('prompts') case final w?) w,
    ];
    final children = [
      if (card.childrenHave != null || card.childrenWant != null)
        Text(
          [
            if (card.childrenHave == true) loc.dating_cardHasChildren,
            if (card.childrenHave == false) loc.dating_cardNoChildren,
            if (card.childrenWant == 'yes') loc.dating_cardWantsChildren,
            if (card.childrenWant == 'no') loc.dating_cardNoWantChildren,
            if (card.childrenWant == 'open') loc.dating_cardOpenChildren,
          ].join(' · '),
          style: theme.textTheme.bodyMedium,
        ),
      if (after('children') case final w?) w,
    ];
    // T11 fix 1 (I-2): each optional line is its own part, so each has its
    // own edit link.
    List<Widget> part(String name, String? line) => [
      if (line != null) Text(line, style: theme.textTheme.bodyMedium),
      if (after(name) case final w?) w,
    ];
    final shownPart = [
      ...part('gender', datingGenderLine(loc, card)),
      ...part('faith', datingFaithLine(loc, card)),
      ...part('marital', datingMaritalLine(loc, card)),
    ];
    final photoPart = <Widget>[
      if (card.photosAfterMutual)
        Text(loc.dating_cardPhotosLater, style: theme.textTheme.bodyMedium)
      else if (photosHidden && card.photoIds.isNotEmpty)
        DatingStartLink(
          label: loc.dating_cardShowPhotos,
          onPressed: onShowPhotos,
        )
      else if (card.photoIds.isNotEmpty)
        _Photos(count: card.photoIds.length, photos: photos),
      if (after('photos') case final w?) w,
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...heading,
            ...intentionPart,
            ...prompts,
            ...children,
            ...shownPart,
            const SizedBox(height: Spacing.sm),
            ...photoPart,
          ],
        ),
      ),
    );
  }
}

/// The photos, one page each, read as one group ("3 photos", §3.4; T11
/// fix 1, M-6) with each page's own "Photo n of N", and a row of dots
/// under them (no motion: the dot moves with the page).
class _Photos extends StatefulWidget {
  const _Photos({required this.count, required this.photos});

  final int count;
  final List<Uint8List> photos;

  @override
  State<_Photos> createState() => _PhotosState();
}

class _PhotosState extends State<_Photos> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final page = _page.clamp(0, widget.count - 1);
    return Semantics(
      container: true,
      label: loc.dating_cardPhotos(widget.count),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 280,
            child: PageView(
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                for (var i = 0; i < widget.count; i++)
                  Semantics(
                    image: true,
                    label: loc.dating_cardPhoto(i + 1, widget.count),
                    child:
                        i < widget.photos.length && widget.photos[i].isNotEmpty
                            ? Image.memory(
                              widget.photos[i],
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            )
                            // A neutral slot, in the theme's own colours.
                            : ColoredBox(
                              color: scheme.surfaceContainerHighest,
                              child: Center(
                                child: Icon(
                                  Icons.image_outlined,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                  ),
              ],
            ),
          ),
          if (widget.count > 1) ...[
            const SizedBox(height: Spacing.sm),
            ExcludeSemantics(
              child: Wrap(
                key: const ValueKey('dating_card_dots'),
                alignment: WrapAlignment.center,
                spacing: 6,
                children: [
                  for (var i = 0; i < widget.count; i++)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            i == page ? scheme.primary : scheme.outlineVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
