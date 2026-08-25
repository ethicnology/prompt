# Prompt

A remote mobile-friendly client for OpenCode.

Prompt targets Android, Linux, and Web. It connects only to a user-controlled
server reachable through WireGuard or Tailscale and is designed around a non-interrupting
prompt queue, responsive streaming, and local-first voice transcription.

## Voice status

Voice input is configured once from **Voice settings**. Prompt uses
`sherpa_onnx` 1.13.5 (Apache-2.0) with two explicit-language streaming Zipformer
INT8 models, one French and one English. One explicit Install action downloads
the four files from pinned Hugging Face revisions, verifies their SHA-256
digests, stores them privately, and selects the language model. One recognizer is loaded in a dedicated isolate for voice mode;
each segment gets a new stream. There is no automatic language mode or final
Whisper pass. Audio is memory-only; the transcript stays local until the user
explicitly sends the prompt.
Android and Linux use the native engine; Web remains a typed unavailable
implementation.

The product scope is in [PLAN.md](PLAN.md); the binding implementation rules
are in [ARCHITECTURE.md](ARCHITECTURE.md) and [AGENTS.md](AGENTS.md).

Read [the private server setup guide](docs/private-server-setup.md) before
running OpenCode remotely. The OpenCode port must remain private-VPN-only because
it can access workspace files and provider/source-control credentials.

## Development

This repository pins Flutter 3.44.9 through FVM.

```sh
fvm flutter pub get --enforce-lockfile
fvm flutter analyze
fvm flutter test
```

## Android APK

```sh
fvm flutter build apk --debug
```

The debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.
