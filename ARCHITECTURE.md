# Prompt Architecture

This document defines the target architecture before implementation begins. It is deliberately smaller than a full Clean Architecture stack: Prompt needs strong boundaries for privacy, streaming, and cross-platform behavior, but not forwarding-only layers or a large dependency framework.

## Sources and Influences

- Flutter's application architecture guide recommends views/view models over repositories/services, with use cases only for complex or shared orchestration: <https://docs.flutter.dev/app-architecture/guide>
- Flutter's adaptive UI guidance bases layouts on available space and input capabilities, not a presumed device class: <https://docs.flutter.dev/ui/adaptive-responsive>
- Flutter's performance guidance favors localized rebuilds, lazy lists, and profiling outside debug mode: <https://docs.flutter.dev/perf/best-practices>
- Dart's dependency guidance favors maintained version ranges, lockfile enforcement, and regular updates: <https://dart.dev/tools/pub/dependencies#best-practices>
- Bull Bitcoin Mobile inspired the explicit documentation map, strict data boundaries, typed recoverable failures, reproducible verification, and feature isolation. Prompt intentionally does not copy its BLoC, service-locator, monorepo, or large dependency footprint: <https://github.com/SatoshiPortal/bullbitcoin-mobile>

## Product Boundary

Prompt is a private Flutter client for a user-controlled OpenCode server. It targets Android, Linux, and Web. The server is reachable over WireGuard; the Web client additionally requires HTTPS. Prompt is not an OpenCode server, an autonomous background worker, or a cloud synchronization service.

Native clients accept HTTP only for RFC1918 IPv4, Tailscale's CGNAT range (`100.64.0.0/10`), or IPv6 ULA origins, so each WireGuard or Tailscale user can configure their own server without a hard-coded address. Android enables cleartext transport solely because Android's static network policy cannot express private address ranges; the application validates the origin before every request. Web always rejects HTTP. Widening the client-side origin policy is a security architecture change requiring review and documentation.

OpenCode is the authoritative source for projects, sessions, messages, provider state, workspace operations, and agent execution. Prompt owns presentation state, local preference state, its durable prompt queue, and a bounded cache.

## System View

```text
Flutter views
    |
View models
    |
Repositories
    |--------------------|-------------------|-----------------
OpenCode REST service   SSE service          Local services
                                              |- Drift database
                                              |- secure storage
                                              |- files / recorder
                                              |- local voice engine
    |
WireGuard-reachable OpenCode server
```

The flow is inward to outward only. UI code never calls OpenCode, Drift, secure storage, or platform code directly.

## Project Layout

The layout is feature-first while retaining shared technical services in `core/`.

```text
lib/
  main.dart                    # composition root and runApp
  app/
    prompt_app.dart            # MaterialApp, theme, top-level shell
    app_scope.dart             # dependency construction with InheritedWidget
    router.dart                # small, explicit Navigator configuration
  core/
    async/                     # Result, Failure, cancellation, clocks
    network/                   # shared request policy, no OpenCode behavior
    platform/                  # conditional platform abstractions
    ui/                        # reusable non-product widgets and tokens
  features/
    connection/
      data/
      domain/
      presentation/
      connection.dart          # public feature facade
    sessions/
    chat/
    queue/
    review/
    providers/
    terminal/
    workspace/
    voice/
    settings/
    export/
  data/
    local/                     # Drift database, migrations, DAOs
    remote/                    # OpenCode REST and SSE services
    security/                  # secure credential service
```

`data/` contains concrete infrastructure shared by several features. A feature owns its repository implementation and mapping code when the infrastructure is specific to that feature. `core/` never contains OpenCode product rules, chat behavior, or queue logic.

The first version may keep files close together while small. Create subdirectories only when they improve discovery; do not create empty layers to satisfy a diagram.

## Layers

### Presentation

Each screen or coherent flow has a view and a view model.

- A view composes widgets, owns transient interaction state such as focus, scroll controllers, animation controllers, and expansion state, and renders a view-model state.
- A view model owns screen state and exposes commands such as `send`, `queue`, `sendNow`, `approve`, `retry`, and `dispose`.
- View models use `ValueNotifier` or another SDK primitive exposed through `InheritedNotifier`. State-management packages are not a default dependency.
- A view model has no `BuildContext`, HTTP client, Drift row, JSON map, `dart:io` import, or platform-channel call.

### Domain

Domain types are stable application concepts: `Session`, `Message`, `MessagePart`, `QueuedPrompt`, `PermissionRequest`, `ServerProfile`, and typed failures. They are not API payloads or database rows.

Use a local sealed `Result<T>` and sealed failure families for expected outcomes. Services may throw transport or platform exceptions; repositories translate them to failures. Unexpected programmer errors remain errors and must not be disguised as a user-facing failure.

Use cases are optional. Add one only if it composes repositories, coordinates a multi-step flow, or is genuinely reused. A use case that only forwards one repository method is prohibited.

### Data

Repositories are the source of truth for one application data type and own:

- mapping between domain entities and REST/Drift representations;
- reconciling SSE events with REST snapshots;
- retry and refresh policy;
- cache reads and writes;
- mapping external exceptions to typed failures.

Repository public signatures only contain domain values and `Result` values. JSON maps, OpenCode generated types, HTTP responses, Drift rows, browser objects, recorder objects, and Whisper types do not cross the repository boundary.

Services are stateless wrappers around one external concern. Examples are `OpenCodeApiService`, `OpenCodeEventService`, `PromptDatabase`, `SecureCredentialsService`, `FileSelectionService`, and `VoiceEngine`.

Repositories do not depend on each other. If data from several repositories must be coordinated, a view model or an explicit use case owns the orchestration.

## Composition Root and Dependencies

`main.dart` constructs the application dependencies once and passes them through `app_scope.dart`. `AppScope` is an `InheritedWidget` or `InheritedNotifier`; it is the only place that knows concrete implementations.

```text
main.dart -> build services -> build repositories -> build view models -> PromptApp
```

This makes dependencies inspectable and test replacement straightforward without adding a service-locator package. A feature exports only a small public facade from `features/<feature>/<feature>.dart`; cross-feature consumers do not import its `data/`, `domain/`, or `presentation/` internals.

## OpenCode Data Flow

### REST and SSE

- REST obtains initial snapshots and performs commands.
- A single SSE connection per server carries live events.
- `OpenCodeEventService` parses events but holds no feature state.
- Relevant repositories reduce events into domain updates and publish view-model-visible state.
- On reconnect, repositories fetch authoritative REST snapshots before declaring state synchronized.
- The app closes SSE when inactive. It never maintains a background connection or aggressive reconnect loop.
- Message history is cursor-paginated where the server supports it. Repositories never request an unbounded transcript or tool output to render a mobile screen.
- Pending permissions and questions are re-fetched before queued work resumes after reconnect or app restart.

### Prompt Queue

The queue is a durable client state machine, keyed by session.

```text
draft -> queued -> sending -> acknowledged
                 |            |
                 v            v
               paused <---- failed
```

- A new prompt or slash command queues when a session is generating. Queue
  records carry an operation type and command arguments, so commands never
  implicitly abort active generation.
- The queue sends only when the server session reaches a terminal, non-blocked state.
- A pending permission or question transitions queued work to `paused`.
- `send now` explicitly requests cancellation, waits for a terminal server state, then sends the chosen prompt.
- Reconnect and app restart reconcile the server state before any queued prompt is sent.
- Queue records are persisted in Drift. Sending must be idempotency-aware: do not retry blindly when it is unknown whether the server accepted a prompt.
- Attachments are sent as OpenCode `file` parts whose `url` is a `data:` URL
  carrying the bytes inline, which is the mechanism the official mobile client
  uses. A queued prompt stores its attachment bytes in the encrypted local
  database alongside its text, so an attached prompt survives a restart and a
  lifecycle transition exactly as a text prompt does.
- The composer's in-memory selection is released as soon as the queue record is
  written. Attachment bytes are never logged, exported, or written outside the
  encrypted database.
- Attachment bytes are removed from the queue record as soon as OpenCode
  definitively acknowledges the prompt. They remain only for unsent or
  submission-unknown work that may need a user-directed recovery.

## Local Storage and Secrets

Drift holds cacheable application data: server profile metadata, project/session indexes, message cache, message parts, queued prompt and command operations, UI preferences, and local-model metadata.

- Android and Linux open an encrypted, on-disk Drift/`NativeDatabase` using `sqlite3` (`^3.5.0`) with its native-asset build hook set to `source: sqlite3mc` (`pubspec.yaml`'s `hooks.user_defines.sqlite3`), which bundles SQLite3MultipleCiphers instead of plain SQLite. Before Drift issues any query, the executor's `setup` applies `PRAGMA cipher = 'chacha20'` (pinned explicitly rather than left to whatever the library currently defaults to), `PRAGMA temp_store = MEMORY` (so sort/temp b-tree spills never write unencrypted temp files to disk), and `PRAGMA key = 'raw:<hex>'` with the raw 32-byte key from `DatabaseKeyStore` (no passphrase key-derivation step, since the key is already random). See `lib/data/local/prompt_local_storage_native.dart`.
- `DatabaseKeyStore` (`lib/core/security/database_key_store.dart`), implemented by `SecureDatabaseKeyStore`, creates a random 32-byte key on first use and reuses it afterward, held only in `flutter_secure_storage` (Android Keystore, Linux libsecret). It never logs, prints, or otherwise surfaces the key; a read/write failure surfaces only as the typed `DatabaseKeyStoreUnavailable`/`DatabaseOpenFailure.keyStoreUnavailable`.
- Opening local storage fails typed (`DatabaseOpenFailure`) rather than silently degrading: an unavailable key store, a build without cipher support, a stored key that does not unlock the on-disk file, and — deliberately — an existing **legacy plaintext** database at Prompt's database path. Prompt does not attempt an automatic, unverified in-place migration of plaintext data; it reports `legacyPlaintextDetected` and leaves the file untouched.
- Web has no equivalent to SQLite3MultipleCiphers-at-rest encryption in this build. Its default is stricter than "conversation content only": Web never opens on-disk SQLite at all, for either queued prompts or server-profile metadata. Both back onto plain in-memory Dart state (`InMemoryQueuePromptsDao`, `InMemoryServerProfileStore`) that is discarded when the page is closed or reloaded. `lib/data/local/prompt_local_storage.dart` conditionally exports the Android/Linux and Web implementations behind one `openPromptLocalStorage()` function so the composition root never branches on platform itself.
- Android disables the system backup transport for the whole app (`android:allowBackup="false"`, `android:fullBackupContent="false"` in `AndroidManifest.xml`), so the encrypted database file is never swept into an unencrypted cloud/adb backup.
- Credentials and database keys use `flutter_secure_storage`, backed by Android Keystore, Linux libsecret, and browser-origin storage where applicable.
- Drift schema migrations are explicit, tested, and backward compatible for shipped versions.
- Raw audio is not a Drift value and is never retained after transcription.
- Attachment bytes exist only in the encrypted queue record while a prompt is
  unsent or its server acceptance is unknown. They are never a cache, log, or
  diagnostic value. Composer selections are released on removal, attempted
  submission, lifecycle inactivity, conversation exit, and disposal.

## Platform and Voice Boundaries

Shared code cannot import a platform-only library. Each cross-platform capability is an interface in shared Dart with conditional implementations.

```text
VoiceEngine
  |- Android/Linux: whisper_ggml / Whisper.cpp native implementation
  |- Web: Whisper.cpp WASM through dart:js_interop
  `- Optional private VPS transcription implementation
```

The local voice engine is preferred. VPS transcription is an explicit user choice and is reachable only over the configured private server route. Audio capture starts only from direct interaction, stops when the app is inactive, and reports a visible recording state.

The initial voice foundation exposes a `VoiceEngine` conditional platform
boundary and a `VoiceRepository` that owns and releases a memory-only capture.
Android uses `record`'s 16 kHz mono PCM stream with `whisper_ggml` live
transcription. A user selects an existing local multilingual GGML model once
from global Voice settings; that app-scoped configuration enables the Voice
input control beside Send in every conversation. The control is the only
permission-capable command and streams partial/final text into the composer.
One memory-only Whisper live session remains active for the whole voice mode.
Holding push-to-talk resumes only the recorder; releasing it pauses only the
recorder, without finalizing Whisper. Stop is the single action that drains and
closes Whisper. Changing sessions or leaving the foreground cancels and
releases the capture and model.
Prompt never invokes the package's model download API and no model is bundled
by this application. Linux and Web adapters remain typed unavailable stubs and
never start a recorder or Whisper session. Audio is
passed directly between the recorder and Whisper, never written to a path or retained after stop,
cancellation, failure, lifecycle inactivity, conversation teardown, or disposal.

The selected appearance mode (`system`, `light`, or `dark`) is a non-sensitive
UI preference stored through Flutter's `shared_preferences` platform adapter.
It is loaded at app startup and never shares storage with credentials, queue
content, transcripts, or the encrypted conversation database.

Session deletion remains an OpenCode API operation, never direct database
access. Prompt aborts and deletes every known descendant session from deepest
to shallowest before deleting the selected parent, allowing OpenCode's foreign
key cascades to remove each session's messages, parts, todos, and related rows.

Flutter Rust Bridge and Dart Native Assets are not part of the initial runtime architecture. They are valid Android/Linux-only build options should Prompt internalize the native voice engine. They do not solve Web, which requires a separate WASM build.

### Remote Terminal

`RemoteTerminal` is a first-class cross-platform feature, not an Electron-only imitation. Its repository creates and manages an experimental OpenCode PTY over REST, then asks the service for a short-lived, single-use connection ticket before opening a WebSocket. The terminal renderer receives only the ticketed stream; it never places the server password in a WebSocket URL.

The terminal emulator, special-key bar, clipboard, window resizing, and tab layout are presentation concerns. The repository owns PTY lifecycle, status events, reconnect policy, and explicit termination. Since the endpoint is experimental, the service is capability-gated and the UI clearly labels it experimental.

### Server Configuration, Sharing, and Experimental Capabilities

- Server configuration, provider setup, OAuth integration, MCP, LSP, and formatter controls are feature repositories over OpenCode APIs. They do not modify local client preferences unless the user chooses a client preference.
- The `share` feature is disabled by default. It requires an explicit, informed action because OpenCode sharing may upload a complete session to an external sharing service. Export is local and sanitized by default.
- Workspace, sync, project-copy, control-plane, and v2 APIs live behind `ServerCapabilities`. Views request a capability from a repository; they never check endpoint versions or feature flags themselves.
- The capability facade lets stable v1 behavior and experimental v2 behavior coexist without contaminating session, queue, or presentation code.

## Adaptive UI

Layout decisions use available width, height, pointer/keyboard capabilities, and current window state, not Android/Linux/Web checks.

- Narrow layouts show projects/sessions and contextual panels as routes, drawers, or modal sheets.
- Wide layouts present a three-pane shell: navigation, transcript, and contextual details.
- The conversation, queue, and permission prompt remain the primary flow at every size.
- Desktop and Web support keyboard shortcuts, focus traversal, text selection, pointer interactions, and resizable panes.
- Widgets expose meaningful semantics. Voice, permission, queue, and connection state must be announced without relying only on color or animation.

## Performance Budget

Prompt targets a smooth 60 Hz experience. Profile and release builds are the source of truth; debug performance is not accepted as a metric.

- Treat 16 ms per frame as the maximum 60 Hz budget, split across UI and raster work.
- Virtualize transcript, sessions, tool output, files, and diffs with lazy builders/slivers.
- Identify message parts stably and rebuild only the changed subtree.
- Batch rendering of token deltas. A fast network stream must not force one frame per token.
- Parse expensive Markdown, structured tool output, and large diffs outside the UI isolate when profiling demonstrates pressure.
- Avoid intrinsic layout calculations and costly compositing effects in scrolling rows unless measured and justified.
- Bound all caches by size and age. Do not prefetch large attachments, diffs, or tool output on mobile data.

## Security and Privacy Rules

- No telemetry, analytics, advertising SDK, third-party crash upload, or hidden network request by default.
- No secret, prompt, transcript, tool output, file content, raw audio, or authorization header in logs.
- The client never falls back from the configured private endpoint to a public route.
- The Web deployment requires HTTPS and a restrictive Content Security Policy because browser storage is exposed to same-origin script execution.
- Sensitive actions are visible in the conversation and governed by OpenCode permissions; Prompt does not silently approve server actions.
- Notifications contain only a generic state such as "Prompt needs your approval"; they never include a prompt, file name, command, transcript, or tool output.
- Local notifications are opt-in. The app requests notification permission only
  from the Notifications settings control, never at launch or after a server
  event. Prompt does not keep SSE alive while inactive, so it only notifies for
  completion or failure when a future lifecycle-safe source can establish that
  transition reliably; it never infers a background result.
- Web notification permissions require HTTPS and a direct browser user gesture;
  browsers do not support scheduled notifications. Linux delivery depends on
  the installed desktop notification server and has no runtime permission
  prompt. Neither limitation changes the generic-only notification content.
- Background networking and recording are disabled by default to protect battery and privacy.

## Testing Strategy

| Layer | Primary tests |
| --- | --- |
| Domain | queue transitions, Result/failure behavior, entity invariants |
| Repositories | REST/SSE reduction, reconciliation, failure mapping, cache behavior |
| View models | commands and complete UI-state transitions |
| Widgets | transcript streaming, queue controls, permissions, accessibility, adaptive layouts |
| Integration | real server connection, secure storage, Drift migration, recorder permissions, PTY ticket flow, provider OAuth polling, platform-specific voice |
| Performance | long transcripts, continuous streaming, large tool outputs/diffs, Android device and Web profile runs |

CI must run format checks, analyzer, unit/widget tests, and the applicable platform builds. Slower native voice and integration jobs run separately from fast Dart checks when CI is introduced.

## Decision Log

- MVVM with repositories/services is chosen over BLoC and a service locator to minimize dependencies and keep state explicit.
- Use cases are conditional rather than mandatory to avoid ceremony.
- Drift is the local database; secrets remain outside it.
- A local persistent prompt queue is required because OpenCode does not provide the desired non-interrupting multi-prompt UX itself.
- `whisper_ggml` is the native Android/Linux default; Web requires a separate Whisper WASM adapter.
- Android is the first delivery surface, but REST, SSE, terminal, configuration, sharing, export, and voice boundaries are platform-neutral from their first implementation.
- No implementation may compromise the Android/Linux/Web target set, privacy defaults, or streaming responsiveness without updating this document and `PLAN.md`.
