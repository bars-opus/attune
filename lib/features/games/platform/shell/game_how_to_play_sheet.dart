import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_strings.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/platform/shell/game_material_theme.dart';
import 'package:flutter/material.dart';

/// Shows a game's rules, a numbered sentence each.
Future<void> showGameHowToPlay(
  BuildContext context, {
  required GameDefinition definition,
}) {
  // Built once, from where it is opened: the builder below runs again on
  // every rebuild of the sheet, by which time that context may be gone.
  final gameTheme = gameMaterialTheme(context, definition.theme);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: GameTheme.ground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    // The game's dark theme is applied here rather than inherited: a screen
    // opens this from its own context, which sits above its GameBackdrop.
    builder:
        (_) => Theme(
          data: gameTheme,
          child: GameHowToPlaySheet(definition: definition),
        ),
  );
}

class GameHowToPlaySheet extends StatelessWidget {
  const GameHowToPlaySheet({super.key, required this.definition});

  final GameDefinition definition;

  @override
  Widget build(BuildContext context) {
    final rules = definition.howToPlay;

    return DefaultTextStyle.merge(
      style: const TextStyle(color: GameTheme.onGround),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: const Text(
                    GameStrings.howToPlay,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < rules.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              '${i + 1}. ${rules[i]}',
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.35,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                GamePrimaryButton(
                  label: GameStrings.gotIt,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
