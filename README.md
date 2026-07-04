# MonoFrame

iOS app + cloud backend + ESP32 firmware for a black & white e-ink picture
frame. Pick a photo, the app dithers it to 1-bit (Floyd–Steinberg) and pushes
it to the cloud; the frame pulls it on its next 30-minute wake — or
immediately when you press the button on its back.

Open source under the [MIT license](LICENSE). You flash the firmware onto
your own hardware with a standard ESP32 tool ([flashing
guide](https://jbaker00.github.io/MonoFrame/flasher/)); binaries are published
on [GitHub Releases](https://github.com/jbaker00/MonoFrame/releases). Want a
different frame supported? [Open a frame support
request](https://github.com/jbaker00/MonoFrame/issues/new?template=frame-support-request.yml).

## Pieces

| Piece            | Location                          | Notes                                    |
|------------------|-----------------------------------|------------------------------------------|
| iOS app          | `Sources/MonoFrame/`              | SwiftUI, iOS 17+, XcodeGen project       |
| Backend          | `backend/functions/index.js`      | Firebase project `monoframe-app` (Blaze) |
| Firmware         | `firmware/MonoFrameDisplay/`      | Elecrow CrowPanel ESP32-S3 4.2" & 5.79"  |
| Flashing guide   | `flasher/` (GitHub Pages)         | How to flash with esptool / browser / Espressif GUI |
| Icon generator   | `scripts/make_icon.py`            | Regenerates the 1024px app icon          |

## How it works

1. **Flash once**: flash `monoframe-fw-42.bin` or `monoframe-fw-579.bin`
   (chip ESP32-S3, offset 0x0) using any ESP32 flashing tool — see the
   [guide](https://jbaker00.github.io/MonoFrame/flasher/). One shared binary,
   nothing user-specific in it.
2. **Guided setup in the app** (My Frames → Add a Frame): the app registers a
   frame on the backend (`POST /registerFrame` → `{frameId, token}`), joins
   the frame's `MonoFrame-XXXX` setup hotspot — WPA2-protected by a code
   shown on the frame's e-ink screen — and POSTs the user's WiFi credentials
   + frameId + token to `192.168.4.1/provision`. The frame stores everything
   in NVS and reboots; the app confirms success by polling `frameStatus`
   until the frame's first `getFrame` stamps `lastSeen`. If the frame runs
   older firmware, the wizard first pushes the app-bundled OTA image to the
   frame's `/update` endpoint (phone-to-frame only, no computer involved).
   The wizard's "No frame yet? Try a demo" button pairs a simulated frame
   (device steps faked, backend registration and uploads real) so anyone can
   walk the whole flow without hardware.
3. **Multiple frames**: credentials for every paired frame live in the
   Keychain (`FrameStore`); the main screen gets a frame picker and a
   "Send to All Frames" action.
4. Send to Frame → dither → `POST /uploadFrame?id=…` (Bearer token) →
   `gs://monoframe-app-frames/frames/{frameId}/current.bin`.
5. Device wakes every 30 min — or on a BOOT-button press — and fetches over
   TLS validated against the pinned Google Trust Services roots
   (`gts_roots.h`), renders, and deep-sleeps. 5+ consecutive failures put it
   back in setup mode.

Firestore `frames/{frameId}` stores only `sha256(token)` + `lastSeen`. All
functions are publicly invokable but check the Bearer token themselves
(new functions need `gcloud run services add-iam-policy-binding <name>
--member allUsers --role roles/run.invoker` after first deploy).

While awake, frames advertise `_monoframe._tcp` over mDNS; the app's
optional "Find frames on my network" scan lists them (sleeping frames won't
appear).

## Build the app

```bash
xcodegen generate      # regenerate .xcodeproj after project.yml/Swift changes
open MonoFrame.xcodeproj
```

The setup wizard's device steps are simulated in the iOS Simulator
(`NEHotspotConfiguration` only works on hardware) — test real pairing on an
iPhone.

## Build the firmware

```bash
scripts/build_firmware.sh
```

Compiles both panel variants with arduino-cli and produces:
- `flasher/monoframe-fw-{42,579}.bin` — complete images (bootloader +
  partitions + app) for USB flashing at offset 0x0; these are what gets
  attached to GitHub Releases.
- `Sources/MonoFrame/Resources/Firmware/monoframe-ota-{42,579}.bin` —
  app-only images the iOS app bundles for phone-to-frame OTA updates.

Note: a USB flash of the full image wipes the frame's NVS (WiFi credentials
and pairing); OTA updates through the app preserve it.

## Deploy the backend

```bash
cd backend
firebase deploy --only functions --project monoframe-app
```

## Security model

- Frames authenticate to the backend with a per-frame 256-bit bearer token;
  the backend stores only its hash. TLS is validated on-device against the
  GTS roots after an NTP clock sync on cold boot.
- The setup hotspot is WPA2-protected with a random 8-character code shown
  on the e-ink screen (persisted in NVS), so provisioning secrets never
  cross the air in cleartext and joining requires physically seeing the
  frame. The `/update` OTA endpoint is only reachable on that hotspot.
- WiFi credentials sit unencrypted in NVS — anyone with physical USB access
  to the frame can read them. That's the standard trade-off for hobbyist
  hardware; treat a discarded frame like a sticky note with your WiFi
  password on it.

## License

MIT — see [LICENSE](LICENSE). Provided as-is, without warranty; you flash
your own hardware at your own risk.
