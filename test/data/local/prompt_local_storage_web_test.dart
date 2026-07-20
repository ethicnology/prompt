import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/data/local/prompt_local_storage_web.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';

void main() {
  test('always succeeds with an in-memory-only handle', () async {
    final result = await openPromptLocalStorage();

    final handle = switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => fail('expected Ok, got Err($failure)'),
    };

    await handle.serverProfiles.save(
      ServerProfile(origin: Uri.parse('http://10.0.0.1:4096')),
    );
    expect(await handle.serverProfiles.loadLast(), isNotNull);

    // close() never throws even though nothing was ever opened on disk.
    await handle.close();
  });

  test('never shares state between two opened handles', () async {
    final firstHandle = switch (await openPromptLocalStorage()) {
      Ok(:final value) => value,
      Err() => fail('expected Ok'),
    };
    await firstHandle.serverProfiles.save(
      ServerProfile(origin: Uri.parse('http://10.0.0.1:4096')),
    );

    final secondHandle = switch (await openPromptLocalStorage()) {
      Ok(:final value) => value,
      Err() => fail('expected Ok'),
    };

    expect(await secondHandle.serverProfiles.loadLast(), isNull);
  });
}
