import 'package:attune/features/games/platform/feel/game_motion.dart';
import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_prefs.dart';
import 'package:attune/features/games/platform/game_strings.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/platform/shell/game_material_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens a game's settings.
Future<void> showGameSettingsSheet(
  BuildContext context, {
  required GameDefinition definition,
  VoidCallback? onHowToPlay,
  VoidCallback? onReportProblem,
  VoidCallback? onLeaveGame,
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
          child: GameSettingsSheet(
            definition: definition,
            onHowToPlay: onHowToPlay,
            onReportProblem: onReportProblem,
            onLeaveGame: onLeaveGame,
          ),
        ),
  );
}

/// Settings for the games in general, for this game, and a way to get help.
///
/// The middle tab belongs to the game and only exists when the game has
/// settings of its own. Support rows only exist when the caller can act on
/// them: there is no Leave game on a page where no game is in progress.
class GameSettingsSheet extends ConsumerStatefulWidget {
  const GameSettingsSheet({
    super.key,
    required this.definition,
    this.onHowToPlay,
    this.onReportProblem,
    this.onLeaveGame,
  });

  final GameDefinition definition;
  final VoidCallback? onHowToPlay;
  final VoidCallback? onReportProblem;
  final VoidCallback? onLeaveGame;

  @override
  ConsumerState<GameSettingsSheet> createState() => _GameSettingsSheetState();
}

class _GameSettingsSheetState extends ConsumerState<GameSettingsSheet> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final gameSettings = widget.definition.settingsBuilder;
    final tabs = <({String label, WidgetBuilder builder})>[
      (label: GameStrings.general, builder: _general),
      if (gameSettings != null)
        (label: widget.definition.title, builder: gameSettings),
      (label: GameStrings.support, builder: _support),
    ];
    final index = _index.clamp(0, tabs.length - 1);

    return DefaultTextStyle.merge(
      style: const TextStyle(color: GameTheme.onGround),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: GameTheme.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: const Text(
                          GameStrings.settings,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    GameRoundButton(
                      icon: Icons.close_rounded,
                      semanticLabel: GameStrings.close,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < tabs.length; i++)
                        _TabLabel(
                          label: tabs[i].label,
                          selected: i == index,
                          onTap: () => setState(() => _index = i),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: SingleChildScrollView(
                    child: tabs[index].builder(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _general(BuildContext context) {
    final prefs = ref.watch(gamePrefsProvider);
    final notifier = ref.read(gamePrefsProvider.notifier);
    final accent = widget.definition.theme.primary;

    return Column(
      children: [
        _SwitchCard(
          title: GameStrings.soundEffects,
          hint: GameStrings.soundEffectsHint,
          value: prefs.sound,
          accent: accent,
          onChanged: notifier.setSound,
        ),
        const SizedBox(height: 12),
        _SwitchCard(
          title: GameStrings.haptics,
          hint: GameStrings.hapticsHint,
          value: prefs.haptics,
          accent: accent,
          onChanged: notifier.setHaptics,
        ),
      ],
    );
  }

  Widget _support(BuildContext context) {
    final rows = <({String label, IconData icon, VoidCallback onTap})>[
      if (widget.onHowToPlay != null)
        (
          label: GameStrings.howToPlay,
          icon: Icons.question_mark_rounded,
          onTap: widget.onHowToPlay!,
        ),
      if (widget.onReportProblem != null)
        (
          label: GameStrings.reportProblem,
          icon: Icons.flag_outlined,
          onTap: widget.onReportProblem!,
        ),
      if (widget.onLeaveGame != null)
        (
          label: GameStrings.leaveGame,
          icon: Icons.logout_rounded,
          onTap: widget.onLeaveGame!,
        ),
    ];

    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _RowCard(label: row.label, icon: row.icon, onTap: row.onTap),
          ),
      ],
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A long game name, or large text, pushes the last tab past the edge
    // of a phone. The row scrolls, and choosing a tab that is only partly
    // showing brings all of it into view.
    void select() {
      onTap();
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: GameMotion.of(context, GameMotion.settle),
        curve: GameMotion.enterCurve,
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      container: true,
      excludeSemantics: true,
      onTap: select,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: select,
        child: Padding(
          padding: const EdgeInsets.only(right: 24, top: 8, bottom: 8),
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color:
                        selected ? GameTheme.onGround : GameTheme.mutedOnGround,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 3,
                  color: selected ? GameTheme.onGround : Colors.transparent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchCard extends StatelessWidget {
  const _SwitchCard({
    required this.title,
    required this.hint,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
        decoration: BoxDecoration(
          color: GameTheme.raised,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    hint,
                    style: const TextStyle(
                      color: GameTheme.mutedOnGround,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: GameTheme.tile,
              activeTrackColor: accent,
              inactiveThumbColor: GameTheme.mutedOnGround,
              inactiveTrackColor: GameTheme.hairline,
            ),
          ],
        ),
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GameTheme.raised,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Icon(icon, color: GameTheme.onGround, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: GameTheme.onGround,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: GameTheme.mutedOnGround,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
