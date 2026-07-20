/// Opens Prompt's local storage for the current platform.
///
/// Android and Linux (`dart.library.io` is available) get
/// `prompt_local_storage_native.dart`'s encrypted, on-disk Drift database.
/// Web gets `prompt_local_storage_web.dart`'s in-memory-only default: no
/// queued prompt or server-profile data is written to browser storage.
///
/// Both conditionally exported implementations expose the same
/// `openPromptLocalStorage()` function and [PromptLocalStorageHandle], so
/// the composition root (`app/prompt_app.dart`) only ever imports this
/// file.
library;

export 'database_open_failure.dart';
export 'prompt_local_storage_handle.dart';
export 'prompt_local_storage_web.dart'
    if (dart.library.io) 'prompt_local_storage_native.dart';
