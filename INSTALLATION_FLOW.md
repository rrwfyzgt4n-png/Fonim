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
