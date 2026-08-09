# Prompt

A fast, private, Android-first Flutter client for a personal OpenCode server.

Prompt targets Android, Linux, and Web. It connects only to a user-controlled
server reachable through WireGuard and is designed around a non-interrupting
prompt queue, responsive streaming, and local-first voice transcription.

## Voice status

Voice input is configured once from **Voice settings**. After selecting a local
multilingual Whisper model, the conversation composer shows a Voice input
button beside Send. It streams local transcription into the draft and requests
microphone permission only from that direct action. Audio and transcripts are
never sent remotely or retained on disk. Android currently provides the native
engine; Linux and Web truthfully remain unavailable until their native/WASM
adapters are bundled.

The product scope is in [PLAN.md](PLAN.md); the binding implementation rules
are in [ARCHITECTURE.md](ARCHITECTURE.md) and [AGENTS.md](AGENTS.md).

Read [the private server setup guide](docs/private-server-setup.md) before
running OpenCode remotely. The OpenCode port must remain WireGuard-only because
it can access workspace files and provider/source-control credentials.

## Development

This repository pins Flutter 3.44.6 through FVM.

```sh
fvm flutter pub get
fvm flutter analyze
fvm flutter test
```

## Android APK

```sh
fvm flutter build apk --debug
```

The debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.
