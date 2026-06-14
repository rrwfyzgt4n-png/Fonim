# Release Notes

## 0.13.0 Release Candidate

This release candidate completes the native macOS narration workstation roadmap.

### Highlights

- Native SwiftUI macOS app with sidebar, editor, inspector, history, outputs, backends, settings, and setup assistant.
- Safe no-overwrite generation sessions under `history/<session_id>`.
- VibeVoice Docker generation through `JobQueue -> EngineAdapter -> BackendManager`.
- Live ticker-style generation progress with parsed VibeVoice progress and final summary metrics.
- Durable metadata, logs, input text, and archived `output.wav`.
- Queue view with cancel, retry, and duplicate actions.
- Output browser with playback, Finder reveal, Quick Look, path copy, and drag-out support.
- Voice and generation preset records under `workspace/presets`.
- Backend profile abstraction with VibeVoice active and Kokoro registered as an unavailable placeholder profile.
- Backend operations for install, update, prepare, stop, health check, repair, reset, and disk usage.
- Local macOS packaging script with app icon, bundle metadata, ad-hoc signing, validation, and zip archive.

### Distribution Status

- Local trusted distribution: ready via `./script/package_app.sh`.
- Public direct distribution: requires Developer ID signing and notarization.
- App Store distribution: not yet assessed; local backend orchestration and sandboxing need a separate review.

### Known Limits

- Kokoro is registered as a backend profile but cannot generate yet.
- VibeVoice remains the only active generation backend.
- Docker Desktop is still external managed infrastructure.
- The default local package is ad-hoc signed, so Gatekeeper will not accept it as a public notarized app.
