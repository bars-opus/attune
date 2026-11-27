import 'package:attune/core/widgets/app_content_width.dart';
import 'package:attune/features/settings/utility/settings_exports.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart';
import 'package:attune/features/auth/intro/widgets/intro_guide_widget.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/join_attune_panel.dart';

class LoginProfile extends ConsumerStatefulWidget {
  const LoginProfile({super.key});

  @override
  ConsumerState<LoginProfile> createState() => _LoginProfileState();
}

class _LoginProfileState extends ConsumerState<LoginProfile> {
  late ScrollController _scrollController;
  List<DocumentationModule> modules = [];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    DocumentationRegistry.initialize();
    // Before sign-in no flag is known: only topics for always-on features.
    modules = DocumentationRegistry.visibleModules(const {});
    // Schedule the scroll after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && modules.length > 1) {
        // Get the screen width
        final screenWidth = MediaQuery.of(context).size.width;
        final itemWidth = _getItemWidth();

        // Calculate offset to center the second item (index 1)
        // Formula: (itemWidth * index) - (screenWidth/2) + (itemWidth/2)
        final offset = (itemWidth * 1) - (screenWidth / 2) + (itemWidth / 2);

        // Ensure offset is not negative (for first items)
        final clampedOffset = offset.clamp(0.0, double.infinity);

        _scrollController.jumpTo(clampedOffset);
      }
    });

    // A returning couplesPending user (app restart, re-navigation) has no
    // locally-held invite — `_invite` only ever lived in this State object,
    // never persisted. ATTUNE_MASTER_SPEC.md: "Invite codes are reusable
    // until accepted or expired," and create-relationship-invite already
    // returns the existing live invite instead of minting a new one, so
    // silently re-fetching here re-displays the same code rather than
    // creating a duplicate. onInviteSent() is NOT called from this path —
    // the user is already on the couplesPending track, so there is nothing
    // new for the app shell to persist.
  }

  double _getItemWidth() {
    return 250.w; // Your item width
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final loc = AppLocalizations.of(context)!;

    // Spec 1 W2b (§3.2 G2): this tab is "Join Attune" with the three ways
    // in; the topic cards and the legal link stay.

    return Material(
      color: colorScheme.neutral,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
              // On an iPad: a centred column, buttons included.
              child: AppContentWidth(
                maxWidth: ContentWidth.form,
                child: Padding(
                padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: AppIconButton(
                        icon: Icons.menu,
                        onPressed: () => context.push('/settings'),
                      ),
                    ),
                    // The new sign-in is the only one (2026-11-26): "Join Attune"
                    // with the three ways in.
                    const JoinAttunePanel(),
                    // Gap(Spacing.xl.h),
                    Gap(Spacing.xxl.h),
                    SizedBox(
                      height: 250.h,
                      child: ListView.builder(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        itemCount: modules.length,
                        itemBuilder: (context, index) {
                          final module = modules[index];
                          return SizedBox(
                            width: 250.w, // Make sure items have fixed width
                            child: IntroGuideWidget(module: module),
                          );
                        },
                      ),
                    ),
                    Gap(Spacing.xxl.h),
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          BottomSheetUtils.showDocumentationBottomSheet(
                            maxHeight: MediaQuery.of(context).size.height * 0.7,
                            context: context,
                            widget: AllLegalDocumentationsScreen(),
                          );
                        },
                        child: Text(
                          loc.authReadLegalities,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            decoration: TextDecoration.underline,
                            letterSpacing: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    Gap(Spacing.xxl.h * 3),
                  ],
                ),
              ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
