import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';

import '../../data/planning_models.dart';

/// P1 offers only the blocks that exist; P3/P4 add theirs here.
const _tools = <(PlanningBlockType, IconData, String)>[
  (PlanningBlockType.text, Icons.notes_rounded, 'Text'),
  (PlanningBlockType.checklist, Icons.checklist_rounded, 'Checklist'),
  (PlanningBlockType.date, Icons.event_rounded, 'Date'),
];

Future<PlanningBlockType?> showBlockToolTray(BuildContext context) => showModalBottomSheet<PlanningBlockType>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: Spacing.allMd,
          child: Wrap(spacing: Spacing.md, runSpacing: Spacing.md, children: [
            for (final (type, icon, label) in _tools)
              SizedBox(
                width: 96,
                child: InkWell(
                  borderRadius: BorderRadiusTokens.mdAll,
                  onTap: () => Navigator.of(c).pop(type),
                  child: Padding(
                    padding: Spacing.allSm,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircleAvatar(radius: 24, child: Icon(icon)),
                      const SizedBox(height: Spacing.xs),
                      Text(label),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
