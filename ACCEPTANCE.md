# Acceptance

## Phase 14 Automated Gate

Required checks:

- `swift build`
- `swift run VibeVoiceBatchCoreChecks`
- `./script/build_and_run.sh --verify`

`VibeVoiceBatchCoreChecks` covers:

- project-level output filing and idempotent repeat filing
- legacy project JSON migration
- multi-session archive into `recovered/deleted_sessions`
- context-aware toolbar policy
- Outputs inspector aggregation
- assistant step locking
- assistant check-list presentation contract
- no-overwrite session, recovered WAV, and output WAV behavior

## Product Acceptance

- Outputs is the housekeeping workspace for filing, sharing, revealing, previewing, and archiving generated WAV sessions.
- History remains the place to inspect a generation's input text, logs, metadata, and playback.
- The Setup Assistant is a guided window with locked future steps and scrollable check results.
- Settings and Setup Assistant are auxiliary windows, not main-window destinations.
- Normal generation and setup flows describe managed backends without making Docker the first user-facing concept.
