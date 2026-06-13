# Model Adapter Spec

UI code must not call model-specific generation logic directly.

Bad:

```text
GenerateButton -> VibeVoiceDockerServer.generate()
```

Correct:

```text
GenerateButton -> JobQueue -> EngineAdapter.generate(job)
```

## EngineAdapter Interface

The Swift contract lives in `Sources/VibeVoiceBatchCore/Services/EngineAdapter.swift`.

Required capabilities:

- `profile`
- `healthCheck()`
- `listVoices()`
- `listModels()`
- `generate(job)`
- `cancel(jobID)`
- `getProgress(jobID)`
- `normalizeOutput()`

## Adapter Rules

- Adapters own model-specific defaults, runtime quirks, progress parsing, and output normalization.
- Adapters must emit plain-language errors with optional technical detail.
- Adapters should not mutate UI state.
- Adapters should not assume a particular SwiftUI view exists.
- Adapters must produce or contribute to a reproducible generation record.

## Current Adapter

`VibeVoiceDockerAdapter` is the first adapter. It owns the VibeVoice Docker session lifecycle behind the queue: session creation, staging-file preparation, stale WAV recovery, process execution, cancellation, log streaming, output archival, metadata finalization, and progress reporting.

`UnavailableEngineAdapter` is used for registered profiles whose runtime integration is not complete. It implements the same `EngineAdapter` contract, reports unavailable health, and returns plain-language operation errors so UI code can switch profiles without calling model-specific logic or pretending unsupported generation works.

## Current Queue Behavior

The SwiftUI app may present multiple queued generation requests, but execution still flows through `JobQueue.submit(_:)` and the selected `EngineAdapter`. UI queue rows are presentation records; durable generation records remain the immutable `history/<session_id>` sessions produced by the adapter.

## Presets

Voice and generation presets store backend, model, voice, settings, and output-format choices as reusable workspace records. Applying a preset prepares a `GenerationJob` configuration; adapters still own backend-specific execution and normalization.
