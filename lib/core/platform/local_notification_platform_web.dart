import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'local_notification_types.dart';

LocalNotificationPlatform createLocalNotificationPlatform() =>
    _WebLocalNotificationPlatform();

class _WebLocalNotificationPlatform implements LocalNotificationPlatform {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;
  var _nextId = 0;

  Future<void> _initialize() => _initialization ??= _plugin.initialize(
    settings: const InitializationSettings(),
  );

  @override
  Future<LocalNotificationPermission> requestPermission() async {
    await _initialize();
    final web = _plugin
        .resolvePlatformSpecificImplementation<
          WebFlutterLocalNotificationsPlugin
        >();
    if (web == null) {
      return LocalNotificationPermission.unavailable;
    }
    return await web.requestNotificationsPermission() == true
        ? LocalNotificationPermission.granted
        : LocalNotificationPermission.denied;
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
      notificationDetails: const NotificationDetails(),
    );
  }
}
