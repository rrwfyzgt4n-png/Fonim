# Packaging

`script/package_app.sh` builds a shareable local macOS app bundle from the SwiftPM executable.

## Local Package

```sh
./script/package_app.sh
```

Outputs:

- `dist/Fonim.app`
- `dist/Fonim-0.13.0.zip`

The default package is ad-hoc signed. It is suitable for local testing and direct transfer between trusted Macs, but it is not notarized.

## Developer ID Build

Use a Developer ID Application certificate for a public direct-distribution build:

```sh
./script/package_app.sh --sign-identity "Developer ID Application: Your Name (TEAMID)"
```

The script signs with hardened runtime when a real identity is supplied. Submit the resulting archive for notarization before public distribution.

## Validation

The packaging script runs:

- `swift build -c release --product Fonim`
- app bundle assembly with `Info.plist`, `PkgInfo`, binary, and `AppIcon.icns`
- `codesign --verify --deep --strict`
- `plutil -lint`
- zip archive creation

Gatekeeper can still reject ad-hoc local builds. That is expected. Use Developer ID signing and notarization for public distribution.

For a full release-candidate smoke test, run:

```sh
./script/smoke_test_release.sh
```

This builds, checks, launches, packages, validates bundle metadata, verifies signing, and confirms the package artifacts exist.

## Distribution Notes

- Docker and model backends remain external managed infrastructure.
- The package does not install Docker, privileged helpers, or model files silently.
- The app remains a direct-distribution candidate; App Store sandboxing needs a separate review because local backend orchestration may require permissions that are not App Store friendly.

## Backend Image Compatibility Notes

The local VibeVoice Docker image currently contains a container-only PyTorch compatibility shim for VibeVoice voice-preset loading. The shim is documented in `BACKENDS.md` and in the Dockerfile. It forces `torch.load(..., weights_only=False)` inside the managed image because current upstream VibeVoice voice-preset loading is not yet compatible with PyTorch's safer default loading behavior.

Distribution rule: do not hide this workaround in release notes, backend setup copy, or support docs. It is acceptable for a local managed image, but it must not be described as a general-purpose safe model-loading environment. Remove it when upstream VibeVoice no longer needs the override.
