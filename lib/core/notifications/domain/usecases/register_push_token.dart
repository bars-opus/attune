// lib/features/notifications/domain/usecases/register_push_token.dart
import 'package:equatable/equatable.dart';
import 'package:attune/core/notifications/data/repositories/notification_repository_interface.dart';



/// Parameters for registering push token
class RegisterPushTokenParams extends Equatable {
  final String userId;
  final String token;
  final String platform; // 'ios', 'android', 'web'

  const RegisterPushTokenParams({
    required this.userId,
    required this.token,
    required this.platform,
  });

  @override
  List<Object?> get props => [userId, token, platform];
}

/// Use case for registering a device push token
class RegisterPushTokenUseCase {
  final NotificationRepositoryInterface repository;

  RegisterPushTokenUseCase(this.repository);

  Future<void> call(RegisterPushTokenParams params) async {
    await repository.savePushToken(
      userId: params.userId,
      token: params.token,
      platform: params.platform,
    );
  }
}
