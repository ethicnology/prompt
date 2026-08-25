# STT Lab

This Android-only laboratory validates Prompt's local streaming speech-to-text
path without retaining audio or transcripts after a run. The current product
path is Sherpa only; older Whisper comparisons remain historical measurements.

## Variants

| Variant | Live path | Final path |
| --- | --- | --- |
| Sherpa streaming | Language-specific Zipformer in a dedicated isolate | Streaming flush |
| Sherpa INT8 | Explicit French or English Zipformer INT8 model, one recognizer isolate | Streaming flush |

## Required Models

Open an official Sherpa archive explicitly and select these four files together
for French:

- `encoder-epoch-29-avg-9-with-averaged-model.int8.onnx`
- `decoder-epoch-29-avg-9-with-averaged-model.onnx`
- `joiner-epoch-29-avg-9-with-averaged-model.int8.onnx`
- `tokens.txt`

For English streaming, use
`sherpa-onnx-streaming-zipformer-en-2023-06-26` with its matching INT8 encoder,
decoder, INT8 joiner, and `tokens.txt`. There is no automatic language mode or
final Whisper pass. Pixel 5/6a measurements found Sherpa INT8 better than
Whisper and FP32; FP32 did not improve WER and cost size/memory, while
Omnilingual offline was not viable.

## Repeatable Tests

Select a mono PCM16 16 kHz WAV file and enter its expected transcript. The app
replays the fixture at real-time speed and reports first-text latency,
finalization latency, update count, revised words, and word error rate.

Do not commit voice fixtures, model files, or exported user transcripts.
