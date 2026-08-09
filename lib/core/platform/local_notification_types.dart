/// Generic notification data only. Sensitive session data never crosses this
/// platform boundary.
library;

enum LocalNotificationPermission { granted, denied, unavailable }

enum SessionNotificationKind { completed, failed }

abstract interface class LocalNotificationPlatform {
  /// Must be called only from a direct user action.
  Future<LocalNotificationPermission> requestPermission();

  Future<void> showSessionNotification(SessionNotificationKind kind);
}
