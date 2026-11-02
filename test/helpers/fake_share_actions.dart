// Spec 1 W4b: how an invite leaves the phone, recorded.
import 'package:attune/features/relationships/presentation/invite_share_actions.dart';

class FakeShareActions extends InviteShareActions {
  FakeShareActions({this.whatsApp = false, this.whatsAppOpens = true});

  bool whatsApp;
  bool whatsAppOpens;
  final whatsAppTexts = <String>[];
  final shared = <String>[];
  final copied = <String>[];

  @override
  Future<bool> canOpenWhatsApp() async => whatsApp;

  @override
  Future<bool> openWhatsApp(String text) async {
    whatsAppTexts.add(text);
    return whatsAppOpens;
  }

  @override
  Future<void> share(String text) async => shared.add(text);

  @override
  Future<void> copy(String text) async => copied.add(text);
}
