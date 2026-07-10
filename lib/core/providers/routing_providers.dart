// lib/core/providers/routing_providers.dart
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final routingNotifierProvider = ChangeNotifierProvider<RoutingNotifier>((ref) {
  throw UnimplementedError('Must be overridden in main');
});

final appRouterProvider = Provider<GoRouter>((ref) {
  throw UnimplementedError('Must be overridden in main');
});
