import 'local_notification_types.dart';

LocalNotificationPlatform createLocalNotificationPlatform() =>
    const _UnavailableLocalNotificationPlatform();

class _UnavailableLocalNotificationPlatform
    implements LocalNotificationPlatform {
  const _UnavailableLocalNotificationPlatform();

  @override
  Future<LocalNotificationPermission> requestPermission() async =>
      LocalNotificationPermission.unavailable;

  @override
  Future<void> showSessionNotification(SessionNotificationKind kind) async {}
}
