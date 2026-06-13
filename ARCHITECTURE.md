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
- `workspace`: editable product records for Projects, Scripts, and Batches. These records can point to generation history, but they do not replace or mutate history sessions.

## Current State

The current working vertical slice uses the VibeVoice Docker backend through the queue and adapter path:

```text
Generate action -> JobQueue -> EngineAdapter -> BackendManager/runtime -> GenerationRecord
```

`AppStore` remains the SwiftUI bridge for editor state, live ticker updates, playback, and history refresh. Backend-specific staging, Docker process execution, cancellation, final WAV archival, log writing, and metadata finalization belong to `VibeVoiceDockerAdapter`.

Backend readiness is represented by `BackendStatusSnapshot`. `BackendManager` owns runtime health checks and plain-language backend states; SwiftUI presents those states without exposing Docker commands as the primary interaction model.

Durable app preferences are represented by `AppSettings` and persisted by `SettingsStore`. The native macOS Settings scene edits backend, model, voice, output, and advanced defaults while generation continues to enter through `JobQueue -> EngineAdapter`.

Backend setup is represented by `BackendSetupReport` and `BackendSetupCheck`. `BackendManager` owns system, runtime, image, model-cache, and health checks; the SwiftUI setup assistant presents those checks and routes test generation through the existing safe generation path.

Backend operations are represented by `BackendOperationKind`, `BackendOperationResult`, and `BackendDiskUsageReport`. `BackendManager` owns install, update, prepare, stop, health check, repair, reset, and disk usage operations; SwiftUI calls those operations through observable stores and never runs runtime commands directly.

Projects, scripts, and batches are represented by `NarrationProject`, `NarrationScript`, `NarrationBatch`, and `NarrationBatchItem`. `WorkspaceFileStore` persists them under `workspace/projects`, `workspace/scripts`, and `workspace/batches`. A script can reference multiple `history/<session_id>` generations, which lets one editable script produce many immutable generation records without overwriting earlier input, audio, logs, or metadata.

## Migration Rule

Do not add new model-specific behavior to SwiftUI views. New backend-specific behavior belongs in an `EngineAdapter` implementation or a parser owned by the backend layer.

The existing VibeVoice path can remain operational while it is progressively moved behind `VibeVoiceDockerAdapter`.
