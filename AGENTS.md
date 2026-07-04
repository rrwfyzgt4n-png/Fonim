# AGENTS.md - Fonim

## Project Overview
- App name: Fonim.
- Repository: `rrwfyzgt4n-png/VibeVoiceBatch`.
- Product shape: native macOS narration workstation for batch text-to-speech generation with interchangeable backend engines.
- Current source package name: `Fonim`.
- User-facing executable/app bundle name: `Fonim`.
- Internal legacy target names still use `VibeVoiceBatch`; do not rename targets, bundle identifiers, settings keys, or history paths unless explicitly requested.
- Target user: Mac users who want a native, guided workstation for scripts, batches, voices, presets, output housekeeping, and reproducible narration history.
- Product direction: Fonim is not a Docker wrapper, not a VibeVoice-only app, and not a Python script with buttons.

## Required Context Before Editing
Read these files before non-trivial changes:
- `CODEX.md` for product direction and architecture questions.
- `ARCHITECTURE.md` for ownership boundaries and current vertical slice.
- `MODEL_ADAPTER_SPEC.md` before touching generation, queues, adapters, models, voices, or backend behavior.
- `BACKENDS.md` before touching Docker, backend setup, health checks, runtime operations, or model-specific behavior.
- `ERROR_HANDLING.md` before changing error surfaces, recovery behavior, archive behavior, or reset behavior.
- `HIG_CHECKLIST.md` before changing visible UI.
- `ACCEPTANCE.md` before considering work complete.
- `PACKAGING.md` before changing bundle metadata, signing, release, or distribution scripts.

## Tech Stack
- Language: Swift.
- Package manager: Swift Package Manager.
- Manifest: `Package.swift` with `// swift-tools-version: 5.9`.
- Platform: macOS 13+ as declared in `Package.swift` and scripts.
- UI: SwiftUI first, with AppKit only for macOS-specific integration such as `NSApplicationDelegate`, activation, pasteboard/Finder/Quick Look, and native panels.
- App lifecycle: SwiftUI `@main` app in `Sources/VibeVoiceBatch/App/VibeVoiceBatchApp.swift`.
- State: current code uses `ObservableObject`, `@StateObject`, `@EnvironmentObject`, `@Published`, `@State`, `@SceneStorage`, and async tasks. Preserve this style unless a broader migration is explicitly requested.
- Persistence: file-backed history and workspace records through core services. Do not introduce SwiftData, Core Data, SQLite, or new production dependencies without explicit approval.
- Backends: `EngineAdapter` abstraction with current adapters for VibeVoice Docker, Kokoro HTTP, Chatterbox HTTP, and unavailable future profiles.

## Project Structure
```text
Sources/
  VibeVoiceBatch/
    App/                  # SwiftUI app entry, scenes, commands, AppKit lifecycle bridge
    Views/                # SwiftUI views and native macOS surfaces
    Stores/               # MainActor app, settings, workspace, backend setup/operation stores
    Coordinators/         # App-level coordination for playback, output, queue, progress, status
    Models/               # UI-facing presentation models
    Services/             # App-only services such as Quick Look preview
    Support/              # App-only support helpers and notifications
  VibeVoiceBatchCore/
    Models/               # Durable product concepts and backend/profile/settings models
    Services/             # Engine adapters, managers, stores, process runners, parsers
    Support/              # Shared formatting, defaults, codecs, shell quoting, text metrics
  VibeVoiceBatchCoreChecks/
    main.swift            # Lightweight acceptance checks
Resources/
  AppIcon.icns
  media_runtimes.csv
script/
  build_and_run.sh        # default local build/run/verify path
  package_app.sh          # local app bundle and zip packaging
  smoke_test_release.sh   # release-candidate smoke test
docker_overrides/         # reviewed backend support files only
```

## Architecture Rules
- Keep UI code backend-neutral. SwiftUI views must not call model-specific generation, Docker, Python, or HTTP service code directly.
- Generation must flow through `JobQueue -> EngineAdapter`.
- Backend-specific defaults, runtime quirks, progress parsing, output normalization, and model-service contracts belong in adapter or backend service code.
- `AppStore` is the SwiftUI bridge for editor state, history refresh, playback, output actions, backend status, and queue presentation.
- Durable history sessions are immutable product records. Do not overwrite `input.txt`, `log.txt`, `metadata.json`, or `output.wav`.
- Projects, scripts, batches, voices, and presets live as workspace records and can reference history sessions. They must not mutate history session folders.
- Generated-output cleanup must archive by moving folders into `recovered/deleted_sessions`; never delete history or output folders in place.
- Backend reset must not delete history, generated audio, logs, metadata, or model cache.
- Docker and Python are managed infrastructure, not the product identity.

## Swift And SwiftUI Conventions
- Prefer small, native SwiftUI views with logic in stores, coordinators, models, or core services.
- Use `NavigationSplitView`, toolbar items, menus, Settings scenes, auxiliary windows, inspectors, and standard macOS shortcuts where appropriate.
- Use `@Environment(\.openWindow)` and `@Environment(\.dismiss)` for SwiftUI window and sheet flow.
- Keep state ownership explicit. Do not introduce global singleton state for app behavior.
- Mark UI stores and UI mutations `@MainActor` or route updates through `MainActor.run`.
- Use `async/await`; do not block with task waits or semaphores on UI paths.
- Use typed recoverable errors where the app can explain the failure.
- User-visible errors must be plain language first, with technical detail available for copying or disclosure.
- Use SF Symbols and system colors by default.
- Add accessibility labels or hints to icon-only and non-obvious interactive controls.
- Comments should explain why a non-obvious decision exists, not restate what the code does.

## Mac-Specific Product Rules
- The app must feel like a native Mac narration workstation, not a terminal frontend.
- Keep Settings as a real macOS Settings scene, not a main-window destination.
- Keep the Backend Setup Assistant as an auxiliary guided window.
- Keep main-window structure aligned with the current workstation model: sidebar, detail area, toolbar, right-side inspector, status/ticker surfaces.
- Normal users should see text, voice, generate, output, progress, and recovery states. Backend commands, raw logs, parser details, and model-specific parameters belong behind progressive disclosure.
- Finder reveal, Quick Look, path copy, drag-out, sharing, and playback should use native macOS integrations.
- Do not introduce iOS-only patterns, UIKit, simulator assumptions, or mobile-specific workflows.

## Backend Rules
- Registered backend profiles live in the core model layer.
- Current production adapters are `VibeVoiceDockerAdapter`, `KokoroHTTPAdapter`, and `ChatterboxHTTPAdapter`.
- `UnavailableEngineAdapter` is the correct pattern for selectable future profiles that are not implemented yet.
- VibeVoice runs as managed Docker infrastructure and currently uses a container-scoped PyTorch compatibility shim. Keep that workaround documented and scoped to the managed VibeVoice image only.
- Kokoro and Chatterbox are HTTP adapters. Keep service URL, health path, voice catalog, model catalog, and output normalization concerns in backend/core code, not SwiftUI views.
- Backend install, update, prepare, stop, health check, repair, reset, and disk usage operations belong to backend manager/store layers.

## Vibe Coding Principles
- Ship the smallest complete change that preserves the current architecture.
- Prefer a working vertical slice through existing stores, coordinators, and adapters over a parallel architecture.
- Keep user-facing UI polished and Mac-native even for prototypes.
- Preserve current public behavior, file formats, session history, settings keys, bundle identifier, and app data unless explicitly asked to migrate them.
- If a feature creates technical debt, call it out and keep the debt local and reversible.

## Do
- Do explain how non-trivial changes fit the long-term architecture before implementing.
- Do preserve multi-backend support when adding generation features.
- Do update docs when changing product architecture, backend behavior, packaging, or acceptance expectations.
- Do keep build/run changes in `script/build_and_run.sh` and Codex run-button config in `.codex/environments/environment.toml`.
- Do use `Resources/AppIcon.icns` and keep bundle resources copied by scripts when packaging.
- Do keep acceptance checks focused and extend `VibeVoiceBatchCoreChecks` for core invariants.
- Do expose backend and file-operation failures with recovery suggestions.

## Don't
- Don't import UIKit.
- Don't call Docker, Python, curl, or backend HTTP services directly from SwiftUI views.
- Don't add a new TTS backend by branching UI on model names.
- Don't silently ignore file, backend, or generation errors.
- Don't delete generated sessions, logs, metadata, output audio, model cache, or recovered archive folders.
- Don't overwrite session `output.wav`; preserve and recover instead.
- Don't add production dependencies, migrations, signing changes, entitlements, hardened runtime exceptions, or deployment changes without explicit approval.
- Don't rename `VibeVoiceBatch` targets or `local.vibevoice.batch` identifiers casually; they preserve local settings and history continuity during the Fonim product rename.
- Don't expose Docker as the primary normal-user workflow.

## Build, Run, Test, Package
- Build: `swift build`
- Build app product: `swift build --product Fonim`
- Core checks: `swift run VibeVoiceBatchCoreChecks`
- Build and launch app bundle: `./script/build_and_run.sh`
- Verify launch process: `./script/build_and_run.sh --verify`
- Stream app logs: `./script/build_and_run.sh --logs`
- Stream telemetry logs: `./script/build_and_run.sh --telemetry`
- Local package: `./script/package_app.sh`
- Release smoke test: `./script/smoke_test_release.sh`

The Phase 14 automated gate in `ACCEPTANCE.md` is:
```sh
swift build
swift run VibeVoiceBatchCoreChecks
./script/build_and_run.sh --verify
```

## GitHub And Local Workflow
- Work from the local checkout when available.
- The GitHub repository is private and accessible as `rrwfyzgt4n-png/VibeVoiceBatch`.
- Keep local changes uncommitted unless the user asks for a commit, push, or PR.
- Do not commit generated `dist/`, `.build/`, history, workspace, model cache, or local runtime artifacts unless the repo explicitly tracks a specific fixture.
- Check `git status --short` before editing and before summarizing work.
