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
- `workspace`: editable product records for Projects, Scripts, Batches, Voices, and Presets. These records can point to generation history, but they do not replace or mutate history sessions.

## Current State

The current working vertical slice uses the VibeVoice Docker backend through the queue and adapter path:

```text
Generate action -> JobQueue -> EngineAdapter -> BackendManager/runtime -> GenerationRecord
```

`AppStore` remains the SwiftUI bridge for editor state, live ticker updates, playback, and history refresh. Backend-specific staging, Docker process execution, cancellation, final WAV archival, log writing, and metadata finalization belong to `VibeVoiceDockerAdapter`.

Main-window navigation is represented by `WorkstationSelection` and a native `NavigationSplitView`. `SidebarView` presents workstation destinations only: Projects, Scripts, Batches, Voices, Presets, History, Outputs, and Backends. Individual generation sessions are selected inside `HistoryWorkspaceView`, which owns the current-text editor state, history list, session detail, playback, duplicate, and folder actions without turning session records into sidebar destinations.

Outputs are represented as a browser over immutable history sessions that have an archived `output.wav`. `OutputBrowserView` owns browsing, search, selection, drag providers, and output detail presentation. `AppStore` owns playback, Finder reveal, path copy, Quick Look preview, and duplicate-as-new actions so output handling stays native and history-backed.

Voice and generation presets are represented by `NarrationVoicePreset` and `NarrationGenerationPreset`. `WorkspaceFileStore` persists custom presets under `workspace/presets/voices` and `workspace/presets/generation` while seeding backend-neutral built-ins from backend/model/voice identifiers. SwiftUI views apply presets through `AppStore`, which updates current editor settings and durable defaults without calling backend-specific code.

Inspector state is window-scoped. `InspectorPanelView` owns the right-side desktop inspector surface for voice, model, inference, export, and contextual metadata controls. The editor stays focused on text and generation while advanced controls move into the inspector.

Generation queue state is visible in the Batches destination. `AppStore` owns app-level `QueuedGenerationItem` presentation state, retry, duplicate, and cancel routing; actual work still enters through `JobQueue -> EngineAdapter`. The queue drains one job at a time for the current VibeVoice backend and keeps terminal queue rows visible so users can retry or duplicate without modifying original history sessions.

Backend readiness is represented by `BackendStatusSnapshot`. `BackendManager` owns runtime health checks and plain-language backend states; SwiftUI presents those states without exposing Docker commands as the primary interaction model.

Additional backend expansion is represented by `BackendProfiles.kokoroTTS` and `UnavailableEngineAdapter`. Kokoro can be selected in native Settings, Backends, and Inspector surfaces, but it reports an unavailable state until managed install and generation support are implemented. This proves the profile and adapter route without faking backend capability.

Durable app preferences are represented by `AppSettings` and persisted by `SettingsStore`. The native macOS Settings scene edits backend, model, voice, output, and advanced defaults while generation continues to enter through `JobQueue -> EngineAdapter`.

Backend setup is represented by `BackendSetupReport` and `BackendSetupCheck`. `BackendManager` owns system, runtime, image, model-cache, and health checks; the SwiftUI setup assistant presents those checks and routes test generation through the existing safe generation path.

Backend operations are represented by `BackendOperationKind`, `BackendOperationResult`, and `BackendDiskUsageReport`. `BackendManager` owns install, update, prepare, stop, health check, repair, reset, and disk usage operations; SwiftUI calls those operations through observable stores and never runs runtime commands directly.

Packaging is handled by `script/package_app.sh`. The script builds the SwiftPM app in release mode, assembles `dist/VibeVoiceBatch.app`, copies `Resources/AppIcon.icns`, writes bundle metadata, signs ad-hoc by default, verifies the signature and plist, and creates a zip archive for trusted local distribution. Developer ID signing and notarization remain explicit public-distribution steps.

Projects, scripts, batches, voices, and presets are represented by `NarrationProject`, `NarrationScript`, `NarrationBatch`, `NarrationBatchItem`, `NarrationVoicePreset`, and `NarrationGenerationPreset`. `WorkspaceFileStore` persists them under `workspace/projects`, `workspace/scripts`, `workspace/batches`, and `workspace/presets`. A script can reference multiple `history/<session_id>` generations, which lets one editable script produce many immutable generation records without overwriting earlier input, audio, logs, or metadata.

## Migration Rule

Do not add new model-specific behavior to SwiftUI views. New backend-specific behavior belongs in an `EngineAdapter` implementation or a parser owned by the backend layer.

The existing VibeVoice path can remain operational while it is progressively moved behind `VibeVoiceDockerAdapter`.
