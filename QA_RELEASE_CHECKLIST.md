# QA Release Checklist

Use this checklist before handing off a release candidate.

## Automated

- Run `./script/smoke_test_release.sh`.
- Confirm `dist/VibeVoiceBatch.app` exists.
- Confirm `dist/VibeVoiceBatch-0.13.0.zip` exists.
- Confirm code signing verification passes.
- Confirm no app source references the legacy Python GUI.

## Manual App Pass

- Launch the packaged app.
- Confirm app icon appears in Finder and Dock.
- Confirm sidebar sections appear: Projects, Scripts, Batches, Outputs, Voices, Presets, History, Backends, Settings.
- Confirm Settings opens as a native Settings window.
- Confirm Inspector can be toggled.
- Confirm Backend Setup Assistant opens.
- Confirm backend status shows a plain-language state.
- Confirm Kokoro can be selected and reports unavailable without pretending generation works.

## Workflow Pass

- New clears the editor and drafts unsaved text first.
- Save Draft creates a timestamped history session without audio.
- Duplicate as New loads prior text without modifying the original session.
- Generate WAV creates a unique session and archives output as `output.wav`.
- Cancel marks the active generation as cancelled and preserves partial logs.
- Queue can show waiting/running/completed/failed/cancelled items.
- Output browser can play, reveal, Quick Look, copy path, drag, and duplicate.

## Safety Pass

- Existing `input.txt` is treated only as staging.
- Existing `outputs/input_generated.wav` is recovered before generation.
- No history input, WAV, log, or metadata is overwritten.
- Failed and cancelled sessions keep their folders.
- Backend reset does not delete history, generated audio, logs, metadata, or model cache.

## Distribution Pass

- For local trusted sharing, use the ad-hoc signed zip from `script/package_app.sh`.
- For public direct distribution, rebuild with Developer ID signing and notarize.
- Do not claim App Store readiness until sandbox/backend orchestration has been reviewed separately.
