# HIG Checklist

The app should feel like a Mac narration workstation, not a terminal frontend.

## Native Structure

- Sidebar for Projects, Scripts, Batches, Voices, Presets, History, generation sessions, Outputs, and Backends.
- Toolbar for primary context actions.
- Inspector for voice, model, inference settings, export settings, and metadata.
- Real Settings window for backend and generation defaults.
- Standard macOS keyboard shortcuts for common actions.

Current implementation note:

- The core data model supports Projects, Scripts, and Batches separately from History.
- The main window uses a native source-list sidebar for workstation destinations while keeping generation sessions directly selectable beneath History in the left library sidebar.
- History’s section row returns to the current editor; individual generation rows open session detail, playback, duplicate, and folder actions.
- Outputs has its own housekeeping browser for archived WAV files, with Finder reveal, Quick Look, path copy, sharing, project filing, drag-out support, and archive-first cleanup.
- Voices and Presets are library surfaces backed by workspace records, with native apply/save actions instead of model-specific terminal concepts.
- Backends can show additional registered profiles, including unavailable ones, with plain-language status rather than terminal errors.
- Core actions are available from native menus and keyboard shortcuts, including New Text, Save Draft, Generate WAV, Cancel Generation, Refresh History, Refresh Backend Status, and Apply Default Generation Settings.
- Settings and the Backend Setup Assistant open as proper auxiliary windows rather than main-window destinations.

## Progressive Disclosure

Normal users see:

- text
- voice
- generate
- output

Advanced users can reveal:

- backend
- model
- inference steps
- temperature
- seed
- backend logs
- parser details

Current implementation:

- The editor surface now stays focused on text, text metrics, and Generate.
- The right-side inspector exposes voice, model, inference, export, and contextual metadata controls.
- Voices and Presets let users apply reusable profiles without exposing backend command details.
- Inspector visibility is a window-scoped preference and can be toggled from the toolbar.
- The Batches destination exposes queued, running, completed, failed, and cancelled jobs with row-level cancel, retry, and duplicate actions.

## Status States

The app must show plain-language states for:

- Docker missing
- Docker stopped
- backend installing
- model downloading
- backend ready
- generation running
- generation failed
- output complete

Current implementation:

- A native status strip shows the selected backend, runtime state, and a plain-language message.
- Missing or stopped Docker states include a recovery suggestion behind Details.
- Generation preflights backend readiness before creating a session.
- Running queue rows show elapsed time, parsed progress when available, estimated remaining time when available, and the session identifier once created.

## Settings

Current implementation:

- The app uses a real macOS Settings scene rather than treating preferences as a main-window destination.
- Settings are grouped into Backends, Models, Voices, Output, and Advanced panes.
- Backend details remain plain-language in normal settings, with raw details available only through Show Details.
- Backend install, update, prepare, stop, repair, and reset are native Settings actions backed by `BackendManager` operations.
- Disk usage is summarized in Settings without making the user inspect folders manually.

## Setup Assistant

Current implementation:

- First launch opens a native Backend Setup Assistant until setup is completed.
- The assistant shows plain-language checks for Mac compatibility, local folders, Docker runtime, backend image, model cache, and health.
- The assistant can install, repair, and prepare the selected backend without sending the user to Terminal.
- Test voice generation goes through the normal queue and no-overwrite history behavior.

## Error Presentation

- Primary errors must be plain-language.
- Technical details belong behind "Show Details".
- Raw stack traces must never be the primary user experience.
- Every failed generation keeps a record, log, and metadata.
- Error alerts include a Copy Details action.
- Session input, log, and metadata panes include copy actions for diagnosis and handoff.

## Accessibility

Current implementation:

- Icon-only generation and backend controls include accessibility labels.
- Sidebar generation rows and icon-only housekeeping/queue buttons use stable hit areas and accessibility labels.
- The text editor has a named accessibility label.
- Status and ticker surfaces combine their important state into readable accessibility labels.

## File Behavior

- User chooses output folders.
- Generated files can be revealed in Finder.
- Generated audio can be played in app.
- Generated audio can be dragged out of the output browser.
- Quick Look is available from output rows and details through the native macOS preview panel.

## Distribution

Current implementation:

- The app can be packaged as a real macOS `.app` bundle with app metadata and icon resources.
- Local packages are ad-hoc signed and verified for trusted direct transfer.
- Public distribution requires Developer ID signing and notarization.
