# Video Pedal

A loop pedal for your webcam, native for macOS.

Hold the pedal key: the live camera keeps going out to the call while the frames are
recorded. Release it: the recording plays on a loop to the call instead of the live feed.
Press the live key once: the loop dissolves into the live feed.

This is a full Swift/Xcode rewrite of the original Python prototype. It has **zero
third-party dependencies** — only Apple frameworks (AVFoundation, CoreMediaIO, CoreImage) —
and feeds OBS Studio's already-approved "OBS Virtual Camera" system extension rather than
publishing its own. Any app that can pick a webcam (Zoom, Meet, Teams, Discord, FaceTime, ...)
sees "OBS Virtual Camera" as an ordinary camera once OBS Studio is installed and running once.

## How it's built

| Piece | What it does |
|---|---|
| `VideoPedal` (app) | SwiftUI host app: permission wizard, camera capture (AVFoundation), the loop-pedal state machine, the global hotkey listener, a preview window, and the bridge that writes frames into OBS's virtual camera device. |
| `OBSVirtualCamera.mm` | Objective-C++ bridge around OBS's CoreMediaIO virtual camera device (`CVPixelBufferPool`-backed, one pool reused for the lifetime of the connection to avoid per-frame allocation). |

Frames flow: physical webcam → `AVCaptureVideoDataOutput` → `PedalEngine` (record / loop /
crossfade, using Core Image for blending and JPEG-in-RAM for the recording buffer, same idea
as the Python prototype's `JpegCodec`) → `OBSOutputClient` writes each frame into OBS's virtual
camera device via CoreMediaIO.

We previously experimented with publishing our own `CMIOExtensionProvider`-based system
camera extension (a `VideoPedalCameraExtension` target), but dropped it: activating a new,
non-Developer-ID-signed system extension can silently fail on managed/MDM'd Macs (corporate
security policies validate and reject the request before it ever reaches the user-approval
step, with no error surfaced to the app) even when the extension's own code signature and
entitlements are otherwise correct. Feeding OBS's already-installed, already-approved virtual
camera sidesteps that whole class of problem and matches what the original Python prototype
did.

## Requirements to build & run

- Xcode 15+ (this repo was generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
  from `project.yml`; the checked-in `VideoPedal.xcodeproj` is ready to open as-is, but if you
  change `project.yml` run `xcodegen generate` to regenerate it).
- [OBS Studio](https://obsproject.com) installed, with its Virtual Camera started/approved at
  least once (System Settings → Privacy & Security will prompt you to approve OBS's camera
  extension the first time you start its Virtual Camera from within OBS).
- macOS 14 (Sonoma) or later, both to build and to run.

### First-time setup

1. Open `VideoPedal.xcodeproj`, select the `VideoPedal` target → **Signing & Capabilities**,
   and set your Team.
2. Build and run (from Xcode, or move the built app to `/Applications`).
3. Launch the app. The in-app wizard walks through the one-time permissions:
   - **Camera access** (`AVCaptureDevice.requestAccess`)
   - **Connect OBS Virtual Camera** — make sure OBS Studio has been started at least once so
     its virtual camera device is registered with the system.
4. Pick "OBS Virtual Camera" as the camera in your call app.

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

