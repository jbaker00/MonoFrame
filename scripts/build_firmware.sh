#!/usr/bin/env bash
# Builds the MonoFrameDisplay firmware and merges it into a single
# flasher/monoframe-fw.bin for the ESP Web Tools flasher page.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SKETCH="$REPO/firmware/MonoFrameDisplay"
OUT="$REPO/flasher/monoframe-fw.bin"
FQBN="esp32:esp32:esp32s3:PSRAM=opi,FlashSize=8M,PartitionScheme=min_spiffs"

[ -f "$SKETCH/config.h" ] || cp "$SKETCH/config.h.template" "$SKETCH/config.h"

echo "== Compiling =="
arduino-cli compile --fqbn "$FQBN" --export-binaries "$SKETCH"

BUILD="$SKETCH/build/esp32.esp32.esp32s3"
APP="$BUILD/MonoFrameDisplay.ino.bin"
BOOTLOADER="$BUILD/MonoFrameDisplay.ino.bootloader.bin"
PARTITIONS="$BUILD/MonoFrameDisplay.ino.partitions.bin"

CORE_DIR="$(ls -d "$HOME/Library/Arduino15/packages/esp32/hardware/esp32/"*/ | sort -V | tail -1)"
BOOT_APP0="$CORE_DIR/tools/partitions/boot_app0.bin"

ESPTOOL="$(ls "$HOME/Library/Arduino15/packages/esp32/tools/esptool_py/"*/esptool 2>/dev/null | sort -V | tail -1)"
if [ -z "$ESPTOOL" ]; then
  echo "esptool not found under Arduino15; install the esp32 core first" >&2
  exit 1
fi

echo "== Merging =="
# ESP32-S3 layout: bootloader @0x0, partition table @0x8000, boot_app0 @0xe000, app @0x10000.
"$ESPTOOL" --chip esp32s3 merge_bin -o "$OUT" \
  --flash_mode dio --flash_freq 80m --flash_size 8MB \
  0x0 "$BOOTLOADER" \
  0x8000 "$PARTITIONS" \
  0xe000 "$BOOT_APP0" \
  0x10000 "$APP"

echo "Wrote $OUT ($(stat -f %z "$OUT") bytes)"
