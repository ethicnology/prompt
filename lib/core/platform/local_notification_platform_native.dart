import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'local_notification_types.dart';

LocalNotificationPlatform createLocalNotificationPlatform() =>
    _NativeLocalNotificationPlatform();

class _NativeLocalNotificationPlatform implements LocalNotificationPlatform {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;
  var _nextId = 0;

  Future<void> _initialize() {
    return _initialization ??= _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        linux: LinuxInitializationSettings(defaultActionName: 'Open'),
      ),
    );
  }

  @override
  Future<LocalNotificationPermission> requestPermission() async {
    await _initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return (await android.requestNotificationsPermission()) == false
          ? LocalNotificationPermission.denied
          : LocalNotificationPermission.granted;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return (await ios.requestPermissions(
                alert: true,
                badge: false,
                sound: true,
              )) ==
              true
          ? LocalNotificationPermission.granted
          : LocalNotificationPermission.denied;
    }
    return LocalNotificationPermission.granted;
  }

  @override
  Future<void> showSessionNotification(SessionNotificationKind kind) async {
    await _initialize();
    final (title, body) = switch (kind) {
      SessionNotificationKind.completed => (
        'Session complete',
        'A session generation has completed.',
      ),
      SessionNotificationKind.failed => (
        'Session failed',
        'A session generation needs attention.',
      ),
    };
    await _plugin.show(
      id: _nextId++,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'session_status',
          'Session status',
          channelDescription: 'Generic session completion and failure updates.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
      ),
    );
  }
}
