# Installation Flow

Backend setup must be an app flow, not a terminal checklist.

## First Launch Assistant

1. Welcome
2. Choose backend mode:
   - Simple: install recommended local backend
   - Advanced: choose models manually
   - External: connect to existing Docker, ComfyUI, or API server
3. Check system:
   - macOS version
   - Apple silicon or Intel
   - RAM
   - free disk space
   - Docker installed
   - Docker running
4. Install backend:
   - pull image
   - download model weights
   - create local data folders
   - start service
   - run health check
   - generate test sample
5. Confirm:
   - backend ready
   - default voice selected
   - output folder selected

## Backend Manager Responsibilities

- detect Docker
- detect Docker running state
- start backend containers
- stop backend containers
- pull or update backend images
- verify model files
- run health checks
- expose logs to UI
- report disk usage
- reset or reinstall backend

SwiftUI views must ask the backend manager or an app store for state. Views must not run shell commands directly.

## Current Implementation

- A native Backend Setup Assistant opens on first launch until setup is marked complete.
- The assistant supports Simple, Advanced, and External setup modes as persisted settings.
- `BackendManager` produces setup reports for Mac compatibility, local folders, Docker runtime, Docker image presence, model cache presence, and backend health.
- The assistant can start a short test voice generation through the normal generation queue, preserving the same history and no-overwrite guarantees as regular generation.
- Managed pull/update, model download, repair, and reset actions remain Phase 5 backend-manager operations.
