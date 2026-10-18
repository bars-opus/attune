import 'package:flutter/material.dart';

/// Tells someone why an invite link they opened was not accepted: they are
/// already in a relationship, active or paused (sync audit I-8). Ending
/// first is their choice; nothing was ended for them.
void showOpenRelationshipNotice(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
  );
}
