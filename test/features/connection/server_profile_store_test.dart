import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/connection/data/server_profile_store.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';

void main() {
  group('InMemoryServerProfileStore', () {
    test('loadLast returns null before anything is saved', () async {
      final store = InMemoryServerProfileStore();

      expect(await store.loadLast(), isNull);
    });

    test('loadLast returns the most recently saved profile', () async {
      final store = InMemoryServerProfileStore();
      await store.save(
        ServerProfile(origin: Uri.parse('http://10.0.0.1:4096')),
      );
      await store.save(
        ServerProfile(
          origin: Uri.parse('http://10.0.0.2:4096'),
          username: 'second',
        ),
      );

      final loaded = await store.loadLast();
      expect(loaded?.displayOrigin, 'http://10.0.0.2:4096');
      expect(loaded?.username, 'second');
    });

    test('never persists past the store instance', () async {
      final store = InMemoryServerProfileStore();
      await store.save(
        ServerProfile(origin: Uri.parse('http://10.0.0.1:4096')),
      );

      final freshStore = InMemoryServerProfileStore();

      expect(await freshStore.loadLast(), isNull);
    });
  });
}
