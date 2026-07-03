# MonoFrame

iOS app + cloud backend + ESP32 firmware for a black & white e-ink picture
frame. Pick a photo, the app dithers it to 1-bit (Floyd–Steinberg, 400×300)
and pushes it to the cloud; the frame pulls it on its next 30-minute wake.

Public, multi-user successor to `~/code/EinkPictureFrameApp` — every frame
gets its own frame ID + secret token, so users never see each other's
pictures and no service-account key ships in the app.

## Pieces

| Piece            | Location                          | Notes                                    |
|------------------|-----------------------------------|------------------------------------------|
| iOS app          | `Sources/MonoFrame/`              | SwiftUI, iOS 17+, XcodeGen project       |
| Backend          | `backend/functions/index.js`      | Firebase project `monoframe-app` (Blaze) |
| Firmware         | `firmware/MonoFrameDisplay/`      | Elecrow CrowPanel ESP32-S3 4.2"          |
| Web flasher      | `flasher/` (GitHub Pages)         | ESP Web Tools; `scripts/build_firmware.sh` regenerates `monoframe-fw.bin` |
| Icon generator   | `scripts/make_icon.py`            | Regenerates the 1024px app icon          |

## How it works

1. **Flash once**: user flashes the frame from the web flasher page
   (Chrome/Edge + USB) — one shared binary, nothing user-specific in it.
2. **Guided setup in the app** (My Frames → Add a Frame): the app registers a
   frame on the backend (`POST /registerFrame` → `{frameId, token}`), joins
   the frame's `MonoFrame-XXXX` setup hotspot
   (`NEHotspotConfiguration(ssidPrefix:)`), and POSTs the user's WiFi
   credentials + frameId + token to `192.168.4.1/provision`. The frame stores
   everything in NVS and reboots; the app confirms success by polling
   `frameStatus` until the frame's first `getFrame` stamps `lastSeen`.
   The wizard's "No frame yet? Try a demo" button pairs a simulated frame
   (device steps faked, backend registration and uploads real) so App Store
   reviewers — and the curious — can walk the whole flow without hardware.
3. **Multiple frames**: credentials for every paired frame live in the
   Keychain (`FrameStore`); the main screen gets a frame picker and a
   "Send to All Frames" action.
4. Send to Frame → dither → `POST /uploadFrame?id=…` (Bearer token) →
   `gs://monoframe-app-frames/frames/{frameId}/current.bin`.
5. Device wakes every 30 min → `GET /getFrame?id=…` (same token) → renders →
   deep sleep. 5+ consecutive WiFi failures put it back in setup mode.

Firestore `frames/{frameId}` stores only `sha256(token)` + `lastSeen`. All
functions are publicly invokable but check the Bearer token themselves
(new functions need `gcloud run services add-iam-policy-binding <name>
--member allUsers --role roles/run.invoker` after first deploy).

While awake, frames advertise `_monoframe._tcp` over mDNS; the app's
optional "Find frames on my network" scan lists them (sleeping frames won't
appear).

## Build the app

```bash
cd ~/code/MonoFrame
xcodegen generate      # regenerate .xcodeproj after project.yml/Swift changes
open MonoFrame.xcodeproj
```

The setup wizard's device steps are simulated in the iOS Simulator
(`NEHotspotConfiguration` only works on hardware) — test real pairing on an
iPhone.

## Deploy the backend

```bash
cd backend
firebase deploy --only functions --project monoframe-app
```

## Rebuild the flasher firmware

```bash
scripts/build_firmware.sh   # arduino-cli compile + esptool merge → flasher/monoframe-fw.bin
```

The flasher page is served by GitHub Pages from `flasher/`.

## Ads

**Debug builds use Google's published TEST ad units; Release builds use the
real ones** (`AdConfig` in `Sources/MonoFrame/AdManager.swift`; the real app
ID lives in `Sources/MonoFrame/Resources/Info.plist`). Banner at the bottom
of the main screen; interstitial on **Send to Frame**, frequency-capped:
never on the session's first send, then at most one per 3 minutes. The setup
wizard shows no ads.

The ATT prompt is handled by `AdsManager.activate()`, fired on scene-active
transitions only. The Ads SDK does not start and no ad is requested until
ATT resolves, and an undisplayable prompt (`.notDetermined` after the
request) retries on the next activation instead of wedging.

## Before a real App Store release

- Add Google UMP consent flow (required for personalized ads in the EEA;
  the iOS ATT prompt is already implemented).
- Consider Firebase App Check on `registerFrame` to deter abuse.
- Register the app + name in App Store Connect.
