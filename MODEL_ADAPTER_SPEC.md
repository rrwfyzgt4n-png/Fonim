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
