import 'local_notification_platform_stub.dart'
    if (dart.library.html) 'local_notification_platform_web.dart'
    if (dart.library.io) 'local_notification_platform_native.dart'
    as implementation;
import 'local_notification_types.dart';

export 'local_notification_types.dart';

LocalNotificationPlatform createLocalNotificationPlatform() =>
    implementation.createLocalNotificationPlatform();
