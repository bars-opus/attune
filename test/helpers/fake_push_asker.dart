// Spec 1 W3c: the contextual push ask, scripted.
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';

class FakePushAsker implements PushAsker {
  FakePushAsker({this.granted = false, this.grantOnAsk = true});

  bool granted;
  bool grantOnAsk;
  final asked = <PushAskContext>[];

  @override
  bool get permissionGranted => granted;

  @override
  Future<PushAskOutcome> askInContext(PushAskContext context) async {
    asked.add(context);
    granted = grantOnAsk;
    return granted ? PushAskOutcome.granted : PushAskOutcome.declined;
  }
}
