import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/intro/widgets/intro_guide_widget.dart';
import 'package:attune/home/widgets/semantic_container_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';

/// The manual topics an empty chat offers, in this order: support first,
/// then the hard-moment tools, the good things, play, streaks, and how the
/// chat works.
const List<String> chatEmptyStateModuleIds = [
  'quietStates',
  'hardMoment',
  'shareAWin',
  'appreciation',
  'games',
  'streaks',
  'chat',
];

/// The topics to show for someone whose enabled flags are [enabledFlags]:
/// a topic about a feature that is switched off has no card.
List<DocumentationModule> chatEmptyStateModules(Set<String> enabledFlags) => [
  for (final id in chatEmptyStateModuleIds)
    if (DocumentationRegistry.getById(id) case final module?)
      if (DocumentationRegistry.requiredFlags(id).every(enabledFlags.contains))
        module,
];

/// A partner's name fit to greet them by, or null for the placeholder
/// names the app falls back to ("Partner", "your partner") or nothing.
String? realPartnerName(String? value) {
  final name = value?.trim();
  if (name == null || name.isEmpty) return null;
  final normalized = name.toLowerCase();
  if (normalized == 'partner' || normalized == 'your partner') return null;
  return name;
}

/// What an empty conversation shows on the wallpaper: a greeting and one
/// card per thing the chat can do, each opening its manual page. Replaced by
/// the message list as soon as there is a message.
class ChatEmptyState extends StatelessWidget {
  const ChatEmptyState({
    super.key,
    required this.partnerName,
    required this.modules,
    this.bottomInset = 0,
  });

  /// The partner's own name, never the couple's chat name: the greeting
  /// addresses one person. Null when no real name is known; the greeting is
  /// then just "Say hello".
  final String? partnerName;

  final List<DocumentationModule> modules;

  /// Clearance for the message bar and anything stacked above it, so the
  /// cards are never covered.
  final double bottomInset;

  static const double cardSize = 190;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final appColors = theme.appColors;
    final name = partnerName;
    final headline = textTheme.headlineSmall?.copyWith(
      color: colorScheme.onSurface,
      fontWeight: FontWeight.bold,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - bottomInset).clamp(
                0,
                double.infinity,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: Spacing.xl.w),
                  child: Column(
                    children: [
                      Semantics(
                        header: true,
                        label:
                            name == null ? 'Say hello' : 'Say hello to $name',
                        excludeSemantics: true,
                        child: Column(
                          children: [
                            Text(
                              name == null ? 'Say hello' : 'Say hello to',
                              textAlign: TextAlign.center,
                              style: headline,
                            ),
                            if (name != null)
                              Text(
                                name,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: headline,
                              ),
                          ],
                        ),
                      ),
                      Gap(Spacing.md.h),
                      // The hint in the app's tip container (the manual's
                      // tip colours), so it reads clearly on the wallpaper
                      // and points at the cards below.
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: ContentWidth.form,
                        ),
                        child: SemanticContainerWidget(
                          title: '',
                          content:
                              'Whenever you are ready, here are a few things you can do in this chat.',
                          icon: Icons.lightbulb_outline,
                          backgroundColor: appColors.success.withValues(
                            alpha: 0.1,
                          ),
                          borderColor: appColors.success,
                          iconColor: appColors.success,
                          textTheme: textTheme,
                        ),
                      ),
                    ],
                  ),
                ),
                if (modules.isNotEmpty) ...[
                  Gap(Spacing.lg.h),
                  SizedBox(
                    height: cardSize.h,
                    child: ListView.builder(
                      key: const ValueKey('chat_empty_state_cards'),
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
                      itemCount: modules.length,
                      itemBuilder:
                          (context, index) => IntroGuideWidget(
                            module: modules[index],
                            size: cardSize,
                          ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
