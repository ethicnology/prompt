import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/platform/local_notification_service.dart';
import 'package:prompt/core/platform/local_notification_types.dart';

void main() {
  test('stays silent until the user grants permission', () async {
    final platform = _RecordingPlatform(LocalNotificationPermission.granted);
    final service = LocalNotificationService(platform);

    await service.showSessionCompleted();
    expect(platform.shown, isEmpty);

    await service.requestPermission();
    await service.showSessionCompleted();

    expect(platform.shown, [SessionNotificationKind.completed]);
  });

  test('never shows anything when permission is denied', () async {
    final platform = _RecordingPlatform(LocalNotificationPermission.denied);
    final service = LocalNotificationService(platform);

    await service.requestPermission();
    await service.showSessionFailed();

    expect(service.isEnabled, isFalse);
    expect(platform.shown, isEmpty);
  });
}

class _RecordingPlatform implements LocalNotificationPlatform {
  _RecordingPlatform(this._permission);

  final LocalNotificationPermission _permission;
  final shown = <SessionNotificationKind>[];

  @override
  Future<LocalNotificationPermission> requestPermission() async => _permission;

  @override
  Future<void> showSessionNotification(SessionNotificationKind kind) async {
    shown.add(kind);
  }
}
