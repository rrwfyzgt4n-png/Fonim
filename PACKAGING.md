# Packaging

`script/package_app.sh` builds a shareable local macOS app bundle from the SwiftPM executable.

## Local Package

```sh
./script/package_app.sh
```

Outputs:

- `dist/VibeVoiceBatch.app`
- `dist/VibeVoiceBatch-0.13.0.zip`

The default package is ad-hoc signed. It is suitable for local testing and direct transfer between trusted Macs, but it is not notarized.

## Developer ID Build

Use a Developer ID Application certificate for a public direct-distribution build:

```sh
./script/package_app.sh --sign-identity "Developer ID Application: Your Name (TEAMID)"
```

The script signs with hardened runtime when a real identity is supplied. Submit the resulting archive for notarization before public distribution.

## Validation

The packaging script runs:

- `swift build -c release --product VibeVoiceBatch`
- app bundle assembly with `Info.plist`, `PkgInfo`, binary, and `AppIcon.icns`
- `codesign --verify --deep --strict`
- `plutil -lint`
- zip archive creation

Gatekeeper can still reject ad-hoc local builds. That is expected. Use Developer ID signing and notarization for public distribution.

## Distribution Notes

- Docker and model backends remain external managed infrastructure.
- The package does not install Docker, privileged helpers, or model files silently.
- The app remains a direct-distribution candidate; App Store sandboxing needs a separate review because local backend orchestration may require permissions that are not App Store friendly.
