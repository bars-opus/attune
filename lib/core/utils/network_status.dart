import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:attune/core/utils/exports/export_screens.dart';

class NetworkStatus extends StatefulWidget {
  final Widget child;

  const NetworkStatus({super.key, required this.child});

  @override
  State<NetworkStatus> createState() => _NetworkStatusState();
}

class _NetworkStatusState extends State<NetworkStatus> {
  ConnectivityResult _connectivity = ConnectivityResult.none;
  final Connectivity _connectivityService = Connectivity();
  late final StreamSubscription<ConnectivityResult> _subscription;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _subscription = _connectivityService.onConnectivityChanged.listen(
      _updateConnectivity,
    );
  }

  Future<void> _checkConnectivity() async {
    final result = await _connectivityService.checkConnectivity();
    _updateConnectivity(result);
  }

  void _updateConnectivity(ConnectivityResult result) {
    setState(() {
      _connectivity = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        widget.child,
        if (_connectivity == ConnectivityResult.none)
          Positioned(
            bottom: 20.h,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.only(bottom: 70.h, left: 10.w, right: 10.w),
                child: SizedBox(
                  height: 70.h,
                  child: SemanticContainerWidget(
                    content: 'Connect to the internet and try again',
                    icon: Icons.warning_amber,
                    title: 'No internet connection',
                    backgroundColor: Colors.red.withValues(alpha: 0.1),
                    borderColor: Colors.red,
                    iconColor: Colors.red,
                    textTheme: theme.textTheme,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
