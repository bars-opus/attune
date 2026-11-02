import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// How an invite leaves the phone (Spec 1 §3.8 R1, RI-4): WhatsApp's
/// share with the text and no recipient (when WhatsApp is installed), the
/// system share sheet, the clipboard. Replaceable in tests.
class InviteShareActions {
  const InviteShareActions();

  static Uri whatsAppUri(String text) =>
      Uri.parse('whatsapp://send?text=${Uri.encodeComponent(text)}');

  /// Needs `whatsapp` in LSApplicationQueriesSchemes (iOS) and a
  /// `<queries>` intent for the scheme (Android 11+).
  Future<bool> canOpenWhatsApp() async {
    try {
      return await canLaunchUrl(Uri.parse('whatsapp://send'));
    } catch (_) {
      return false;
    }
  }

  /// False when WhatsApp didn't open (the caller falls back to [share]).
  Future<bool> openWhatsApp(String text) async {
    try {
      return await launchUrl(
        whatsAppUri(text),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> share(String text) async {
    await Share.share(text);
  }

  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

final inviteShareActionsProvider = Provider<InviteShareActions>(
  (ref) => const InviteShareActions(),
);
