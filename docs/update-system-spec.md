# In-App Auto-Update System — Specification

Originating requirement for the Android APK in the BRO / PulseChat Flutter app.
This is the source of truth for the "Spec" axis of code reviews of the update system.

## Requirements

1. **Background check, throttled.** Check for a new version on the GitHub Releases
   API, but throttle the actual check to roughly once every 6 hours so the app
   does not hit the network on every launch/resume.

2. **Native dialog with details.** When an update is available, present a native
   dialog showing at least: the new version, the release notes, and the download
   size.

3. **User choice.** The user must be able to choose "update now" or "later".
   "Later" defers the check.

4. **ABI-specific APK.** Release builds are published as split-per-ABI APKs
   (`arm64-v8a`, `armeabi-v7a`, `x86_64`). The app must select and download the
   APK matching the device's ABI.

5. **Download with progress.** The APK download must surface progress so the
   user can see it working.

6. **Install permission handling.** The app must request/explain the
   `REQUEST_INSTALL_PACKAGES` permission path before handing off to the system
   installer.

7. **Version refresh on resume.** When the app returns to the foreground, it
   should reflect that it may have been updated (re-check version).

8. **NEVER silent install. Android retains control.** The app must never install
   the APK silently. It hands off to the Android system package installer
   (`ACTION_VIEW` with the package MIME type) and lets the OS drive the install
   and grant the user the final decision.

9. **Distribution channel: GitHub Releases.** Updates are distributed via the
   GitHub Releases API on repo `marvel-254/chat-app`. Each release is tagged
   `v$run_number`.

## Non-requirements / decisions taken

- No silent/auto install path. The OS always owns installation.
- Version identity comes from `package_info_plus` (versionCode via
  `BUILD_NUMBER` dart-define), ABI from `device_info_plus`.
- Dialog flow phases: prompt → downloading → verifying → failed → explaining →
  installing.
- A native Android `MethodChannel` (`brotools/updater`) bridges the Flutter UI
  to the OS installer via `FileProvider`.
