# Architecture

VibeVoiceBatch is evolving into a native macOS narration workstation for batch TTS generation with interchangeable model backends.

It is not a Docker wrapper, a VibeVoice-only app, or a Python script with buttons.

## Target Shape

```text
Native macOS App
  -> Project / Script / Batch / History UI
  -> Job Queue
  -> Engine Adapter Layer
  -> Backend Manager
  -> Docker / Local Python / ComfyUI / Future Native Engine
  -> Audio Outputs + Logs + Reproducible Metadata
```

## Ownership

- `Sources/VibeVoiceBatch`: native SwiftUI app, window structure, commands, Settings, and presentation state.
- `Sources/VibeVoiceBatchCore/Models`: durable product concepts such as backend profiles, jobs, records, session metadata, and statuses.
- `Sources/VibeVoiceBatchCore/Services`: orchestration, backend management, adapters, file stores, parsers, process clients, and audio inspection.
- `docker_overrides`: explicit, reviewed backend support files mounted into managed containers.
- `history`: generated session artifacts only. Root `input.txt` and `outputs/input_generated.wav` remain staging files.

## Current State

The current working vertical slice uses the VibeVoice Docker backend through the queue and adapter path:

```text
Generate action -> JobQueue -> EngineAdapter -> BackendManager/runtime -> GenerationRecord
```

`AppStore` remains the SwiftUI bridge for editor state, live ticker updates, playback, and history refresh. Backend-specific staging, Docker process execution, cancellation, final WAV archival, log writing, and metadata finalization belong to `VibeVoiceDockerAdapter`.

Backend readiness is represented by `BackendStatusSnapshot`. `BackendManager` owns runtime health checks and plain-language backend states; SwiftUI presents those states without exposing Docker commands as the primary interaction model.

## Migration Rule

Do not add new model-specific behavior to SwiftUI views. New backend-specific behavior belongs in an `EngineAdapter` implementation or a parser owned by the backend layer.

The existing VibeVoice path can remain operational while it is progressively moved behind `VibeVoiceDockerAdapter`.
