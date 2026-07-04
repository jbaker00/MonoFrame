# MonoFrameDisplay firmware

Arduino sketch for the **Elecrow CrowPanel ESP32-S3 e-paper** boards: the
4.2" (400×300 BW, default) and the 5.79" (792×272 BW — `#define PANEL_579`
in `config.h`).
Pairs with the MonoFrame iOS app: the app pushes a dithered 1-bit photo to the
cloud, this sketch pulls it every 30 minutes and deep-sleeps in between.

**No per-user configuration is baked into the firmware.** A freshly flashed
frame boots into **setup mode**: it shows instructions on the e-ink screen and
broadcasts a `MonoFrame-XXXX` WiFi hotspot. The MonoFrame app joins that
hotspot and sends the frame your WiFi credentials plus its frame ID and token
(`POST /provision`, stored in NVS flash). If WiFi later fails 5 wakes in a
row (e.g. you changed your router password), the frame falls back into setup
mode automatically.

## Easiest way to flash

Use the **web flasher** (Chrome or Edge, frame plugged in over USB) — see the
link in the root README. No tools to install.

## Flashing with arduino-cli

```bash
brew install arduino-cli          # or use the Arduino IDE
arduino-cli config init --overwrite
arduino-cli core update-index \
  --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli core install esp32:esp32 \
  --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli lib install "GxEPD2" "Adafruit GFX Library"
cp config.h.template config.h     # nothing to edit — just the backend URL
```

```bash
arduino-cli compile \
  --fqbn "esp32:esp32:esp32s3:PSRAM=opi,FlashSize=8M,PartitionScheme=min_spiffs" .
arduino-cli upload \
  --fqbn "esp32:esp32:esp32s3:PSRAM=opi,FlashSize=8M,PartitionScheme=min_spiffs,UploadSpeed=115200" \
  --port /dev/cu.usbserial-10 .
```

Upload at 115200 baud — the ESP32-S3 in this CrowPanel drops the connection at
921600. Your serial port name may differ (`arduino-cli board list`).

## Setup-mode HTTP API (192.168.4.1)

| Endpoint | Method | Notes |
|----------|--------|-------|
| `/info` | GET | `{model, mac, fw, name, provisioned}` |
| `/provision` | POST | form-encoded `ssid`, `pass`, `frameId`, `token`; saves to NVS and reboots |

While awake (setup mode or a normal wake) the frame advertises
`_monoframe._tcp` over mDNS so the app's network scan can find it.

## Pin map (identical on the 4.2" and 5.79" boards)

| Signal | GPIO |
|--------|------|
| PWR    | 7    |
| MOSI   | 11   |
| SCK    | 12   |
| CS     | 45   |
| DC     | 46   |
| RST    | 47   |
| BUSY   | 48   |
