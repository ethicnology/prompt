import 'dart:async';

import '../../features/connection/data/server_profile_store.dart';
import '../../features/queue/data/queue_prompts_dao.dart';

/// A resolved local-storage backend for the current platform, bundling the
/// stores the composition root wires into repositories together with how
/// to release the backend's resources.
///
/// Android and Linux back this with an encrypted, on-disk Drift database
/// (`prompt_local_storage_native.dart`). Web never opens on-disk SQLite:
/// its handle (`prompt_local_storage_web.dart`) is purely in-memory, so
/// [close] is a no-op there and neither store persists past the current
/// page session.
class PromptLocalStorageHandle {
  // Not an initializing formal: `closeHandle` and `_closeHandle` are
  // deliberately different names because the platform implementations
  // that construct this (in other files) need `closeHandle` as a public,
  // callable named argument, which a private initializing formal
  // parameter would not allow across files.
  const PromptLocalStorageHandle({
    required this.serverProfiles,
    required this.queuedPrompts,
    required Future<void> Function() closeHandle,
    // ignore: prefer_initializing_formals
  }) : _closeHandle = closeHandle;

  final ServerProfileStore serverProfiles;
  final QueuePromptsDao queuedPrompts;
  final Future<void> Function() _closeHandle;

  Future<void> close() => _closeHandle();
}
