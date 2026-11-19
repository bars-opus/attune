import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/games/platform/game_strings.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_backdrop.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/platform/shell/game_content_width.dart';
import 'package:flutter/material.dart';

/// The frame every game is played in.
///
/// One header for all of them: back on the left, a small subtitle over a
/// bold title, settings on the right. The game supplies the middle and,
/// optionally, a row of round actions under it.
class GameScaffold extends StatelessWidget {
  const GameScaffold({
    super.key,
    required this.theme,
    required this.title,
    required this.body,
    this.subtitle,
    this.onBack,
    this.onSettings,
    this.actions = const [],
    this.maxContentWidth = ContentWidth.form,
  });

  final GameTheme theme;
  final String title;
  final String? subtitle;
  final Widget body;
  final VoidCallback? onBack;

  /// Null hides the gear.
  final VoidCallback? onSettings;

  /// Round buttons under the body, such as Hint and Undo.
  final List<Widget> actions;

  /// The body is capped to this on a tablet and centred.
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GameTheme.ground,
      body: GameBackdrop(
        theme: theme,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    GameRoundButton(
                      icon: Icons.arrow_back_rounded,
                      semanticLabel: GameStrings.back,
                      onTap: onBack ?? () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (subtitle != null)
                              Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                // Solid and bold: the header sits on the
                                // game's colour, where thin or translucent
                                // white is hard to read.
                                style: const TextStyle(
                                  color: GameTheme.onGround,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            Semantics(
                              header: true,
                              child: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: GameTheme.onGround,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (onSettings != null)
                      GameRoundButton(
                        icon: Icons.settings_rounded,
                        semanticLabel: GameStrings.settings,
                        onTap: onSettings,
                      )
                    else
                      const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: GameContentWidth(maxWidth: maxContentWidth, child: body),
              ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (final action in actions)
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: action,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
