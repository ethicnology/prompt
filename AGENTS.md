# Prompt Agent Guide

Instructions for coding agents and contributors working in this repository.

## Documentation Map

- `README.md`: product overview and setup once the application exists.
- `PLAN.md`: complete product scope and delivery sequence.
- `ARCHITECTURE.md`: binding architecture, data-flow, security, performance, and testing rules.
- `AGENTS.md`: this file; implementation and verification conventions.

The repository contains a substantial implementation that continues to evolve. Do not claim a package, command, directory, endpoint, or behavior exists before checking the worktree.

## Project Constraints

- Flutter targets Android, Linux, and Web from one codebase.
- OpenCode is accessed only through the user's WireGuard-reachable server.
- The application must be private, battery-conscious, data-conscious, and responsive under continuous streaming.
- Prefer the Flutter and Dart SDKs over packages. Every direct dependency needs a concrete cross-platform requirement.
- Do not add a state-management, routing, SSE, icon, cache, analytics, or design-system package by default.
- The queue is a product guarantee: a prompt submitted during a generation queues by default and never silently aborts the active run.

## Architecture Rules

Read `ARCHITECTURE.md` before adding a feature.

- Follow the one-way dependency direction: `view -> view model -> repository -> service`.
- Views contain rendering, local widget state, accessibility, and simple navigation only. They do not call services or own business rules.
- View models expose UI state and commands. They do not import HTTP, Drift, platform APIs, or Web interop.
- Repositories are the only source of truth for an app data type. They reconcile REST, SSE, Drift, retries, and cache state.
- Services wrap exactly one external concern: OpenCode REST, SSE transport, Drift, secure storage, files, recorder, or a platform voice engine.
- Add a use case only when it composes repositories, contains non-trivial orchestration, or is shared by multiple view models. Do not create forwarding-only use cases.
- Repository public APIs use app entities and failures, never JSON, HTTP responses, Drift rows, package types, or platform types.
- Keep one feature isolated from another. A feature may import another feature only through its public facade once one exists; never import another feature's internals.
- `core/` contains reusable technical primitives only. Product-specific behavior belongs in its feature.

## State, Errors, and Async Work

- Use `setState` for widget-local state. Use `ValueNotifier` and `InheritedNotifier` for shared view-model state unless a demonstrated need requires more.
- Keep one view model focused on one screen or coherent flow. Dispose controllers, stream subscriptions, timers, and notifiers deterministically.
- Model expected, user-recoverable failures as typed values. Map transport, storage, and platform exceptions at the repository boundary. Do not show raw exception text to users.
- Do not use a boolean such as `isLoading` as the only async state. Represent idle, loading, ready, empty, failed, and streaming states distinctly where the UI needs them.
- Do not hold a `BuildContext` in a view model, repository, or service.
- Cancel SSE subscriptions and in-flight work when their owning scope is disposed or the app becomes inactive.

## Privacy and Security

- Never log, print, serialize for diagnostics, or put in analytics: prompts, messages, tool output, file contents, paths containing user data, credentials, authorization headers, local model audio, or audio transcripts.
- Store credentials and encryption keys only with `flutter_secure_storage`. Never put secrets in Drift, preferences, application state, assets, or source control.
- Audio is memory-only and must be released on success, failure, cancellation, lifecycle pause, and restart cleanup.
- Treat browser storage as weaker than Android Keystore and Linux libsecret. Web conversation-content caching is opt-in, never the default.
- New network routes must use the configured private server origin. Do not introduce third-party network calls without explicit user approval.
- Request microphone or file access only from a direct user action and handle denial as a normal state.

## Performance and UX

- Profile performance in profile or release mode, never use debug timings as evidence.
- Preserve 60 fps during streaming. Rebuild only the changed message part, not an entire transcript or screen.
- Use lazy lists and slivers for unbounded sessions, files, tool output, and diffs.
- Batch visual updates from token/SSE deltas. Parse large Markdown, JSON, and diffs away from the UI isolate when measurement shows UI pressure.
- Keep `const` widgets where practical; keep state changes scoped to the smallest subtree.
- Do not use expensive visual effects, intrinsic layout passes, or `saveLayer()`-triggering effects in scrolling conversation rows without profiling evidence.
- Build layouts from available width and input capabilities using `LayoutBuilder` and `MediaQuery.sizeOf`; do not branch on a presumed device type or lock orientation.
- All primary desktop/web flows must work with keyboard, mouse, touch, visible focus, and screen readers.

## Platform Boundaries

- Shared Dart code must compile for all targets. Do not import `dart:io` from code reachable by Web.
- Put Android/Linux/Web implementation differences behind a small interface and conditional imports.
- Prompt's native voice engine uses `sherpa_onnx` 1.13.5 (Apache-2.0) on Android/Linux with explicitly selected French or English streaming Zipformer INT8 models. Web voice remains a typed unavailable implementation; do not add a WASM or Whisper strategy without an explicit architecture decision.
- Dart Native Assets do not support Web. Do not design a Web feature around FFI or Native Assets.
- HTTPS is mandatory for the Web client because microphone and secure browser APIs require a secure context, even over WireGuard.

## Dependencies and Generated Code

- Before adding a dependency, verify current maintenance, license, Android/Linux/Web support, transitive cost, and whether the SDK already solves the need.
- Prefer published, maintained packages with compatible permissive licenses. Do not add GPL-licensed runtime dependencies without explicit approval.
- Use normal caret constraints for published packages. Update dependencies deliberately and run `dart pub outdated` regularly.
- Commit `pubspec.lock` for this application. Verify dependency integrity in CI with `dart pub get --enforce-lockfile`.
- Keep generated code reproducible. Never hand-edit Drift or other generated output; run the owning generator and commit its intended output.

## Testing and Verification

- Add or update tests with behavioral changes.
- Unit-test view models, repositories, prompt-queue transitions, failure mapping, and SSE event reduction.
- Widget-test conversation streaming, permissions, queued prompts, accessibility labels, and adaptive layouts.
- Integration-test real critical flows on Android, Linux, and Web as platform support is added.
- Test the queue against ordering, reconnect, cancellation, permission pause, app restart, and server error cases.
- Run formatting, analysis, and relevant tests before declaring work complete. Once scaffolded, the baseline commands are:

```sh
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

Use project Makefile or task-runner commands once they exist rather than inventing alternate command sequences.

When an APK is built for user testing, expose it through the machine's
configured private-only sharing mechanism, verify the downloaded size and
checksum, and return the working URL. Never bind a debug artifact server to a
public interface.

## Working Practices

- Read existing code and the relevant documentation before editing. Preserve unrelated user changes.
- Make the smallest correct change. Do not combine unrelated refactors with a feature or bug fix.
- Update `ARCHITECTURE.md` when a boundary, persistent schema, security posture, platform strategy, or data-flow decision changes.
- Update `PLAN.md` when the product scope or a settled product decision changes.
- Do not bypass hooks, weaken lint rules, suppress analyzer warnings, or lower test expectations to make a change pass.
- Do not commit credentials, local databases, model files, audio files, generated build artifacts, or user content.
