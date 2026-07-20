import '../../core/async/result.dart';
import '../../core/security/database_key_store.dart';
import '../../features/connection/data/server_profile_store.dart';
import '../../features/queue/data/in_memory_queue_prompts_dao.dart';
import 'database_open_failure.dart';
import 'prompt_local_storage_handle.dart';

/// Opens Prompt's local storage for the Web target.
///
/// The Web platform has no equivalent to SQLite3MultipleCiphers-at-rest
/// encryption available in this build, so Web never persists queue or
/// server-profile storage by default: both back onto plain in-memory Dart
/// state that is discarded when the page is closed or reloaded. This
/// always succeeds; there is nothing external to fail to open.
///
/// [keyStore] and [resolveDatabasePath] are accepted only so this
/// function's signature matches the native implementation conditionally
/// exported in its place; Web never uses either.
Future<Result<PromptLocalStorageHandle, DatabaseOpenFailure>>
openPromptLocalStorage({
  DatabaseKeyStore? keyStore,
  Future<String> Function()? resolveDatabasePath,
}) async {
  final handle = PromptLocalStorageHandle(
    serverProfiles: InMemoryServerProfileStore(),
    queuedPrompts: InMemoryQueuePromptsDao(),
    closeHandle: () async {},
  );
  return Ok(handle);
}
