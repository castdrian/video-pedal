# Video Pedal

A loop pedal for your webcam, native for macOS.

Hold the pedal key: the live camera keeps going out to the call while the frames are
recorded. Release it: the recording plays on a loop to the call instead of the live feed.
Press the live key once: the loop dissolves into the live feed.

This is a full Swift/Xcode rewrite of the original Python prototype. It has **zero
third-party dependencies** — only Apple frameworks (AVFoundation, CoreMediaIO, CoreImage,
SystemExtensions, IOSurface) — and publishes a real, system-level virtual camera via a
[Camera Extension](https://developer.apple.com/documentation/coremediaio/creating-a-camera-extension-with-core-media-i-o),
not a third-party OBS/DAL plugin. Any app that can pick a webcam (Zoom, Meet, Teams, Discord,
FaceTime, ...) sees "Video Pedal" as an ordinary camera.

## How it's built

| Piece | What it does |
|---|---|
| `VideoPedal` (app) | SwiftUI host app: permission wizard, camera capture (AVFoundation), the loop-pedal state machine, the global hotkey listener, and a preview window. |
| `VideoPedalCameraExtension` (system extension) | A `CMIOExtensionProvider` that publishes the "Video Pedal" camera device/stream. Receives already-processed frames from the app over XPC and hands them to whichever app is watching. |
| `Shared/` | The tiny bit both targets compile directly: the XPC protocol and a few shared constants (bundle IDs, device/stream UUIDs). No framework, just shared source. |

Frames flow: physical webcam → `AVCaptureVideoDataOutput` → `PedalEngine` (record / loop /
crossfade, using Core Image for blending and JPEG-in-RAM for the recording buffer, same idea
as the Python prototype's `JpegCodec`) → sent as an `IOSurface` over XPC (zero-copy, no
per-frame serialization) → the extension wraps it in a `CMSampleBuffer` and calls
`CMIOExtensionStream.send`.

## Requirements to build & run

- Xcode 15+ (this repo was generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
  from `project.yml`; the checked-in `VideoPedal.xcodeproj` is ready to open as-is, but if you
  change `project.yml` run `xcodegen generate` to regenerate it).
- A paid Apple Developer Program membership. System extensions must be signed with a real
  Developer ID (or a Team ID during local development) — an unpaid personal team cannot
  activate them on another machine, and even locally you need a Team selected in
  Signing & Capabilities for both targets.
- macOS 14 (Sonoma) or later, both to build and to run.

### First-time setup

1. Open `VideoPedal.xcodeproj`, select the `VideoPedal` target → **Signing & Capabilities**,
   and set your Team. Do the same for the `VideoPedalCameraExtension` target. Both must use
   **the same Team**.
2. Build and run. **Camera extensions only activate from an app in `/Applications`** — if you
   run straight from Xcode's DerivedData, the install step in the wizard will fail silently.
   Archive and move the app to `/Applications`, or use Xcode's "Copy Debug Build to
   /Applications" habit while iterating.
3. During development, unsigned/local iteration is easier with system extension developer mode:
   ```sh
   systemextensionsctl developer on
   ```
   (reboot if prompted). See Apple's
   [Debugging and testing system extensions](https://developer.apple.com/documentation/driverkit/debugging-and-testing-system-extensions).
4. Launch the app from `/Applications`. The in-app wizard walks through the three one-time
   permissions:
   - **Camera access** (`AVCaptureDevice.requestAccess`)
   - **Input Monitoring** (`IOHIDCheckAccess`/`IOHIDRequestAccess`) — required so the pedal key
     works while another app is focused
   - **Install the virtual camera** (`OSSystemExtensionRequest.activationRequest`) — macOS will
     prompt you to approve it in System Settings → Privacy & Security the first time.
5. Pick "Video Pedal" as the camera in your call app.

## Using it

- Hold the pedal key (default: right Option) to record; release to loop it.
- Tap the live key (default: right Command) once to dissolve back to the live camera, or to
  cancel a recording in progress.
- The app window also has Record/Go-live buttons and shows the same status HUD, loop
  progress bar, and a settings panel (camera picker, pedal/live key pickers, max length,
  minimum hold, crossfade seconds, preview ghost opacity) that the Python version exposed as
  CLI flags.

## Why a fork, and why still similar in spirit

This is a full Swift/Xcode rewrite of the original Python/OpenCV/pyvirtualcam prototype
(`haxybaxy/video-pedal`). It uses OBS Studio's already-approved macOS Camera Extension as the
virtual-camera output, matching the original Python backend without installing another system
extension.
