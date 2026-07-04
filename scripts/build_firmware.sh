#!/usr/bin/env bash
# Builds the MonoFrameDisplay firmware for each supported panel and merges
# each into a single flasher/monoframe-fw-<panel>.bin for the ESP Web Tools
# flasher page.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SKETCH="$REPO/firmware/MonoFrameDisplay"
FQBN="esp32:esp32:esp32s3:PSRAM=opi,FlashSize=8M,PartitionScheme=min_spiffs"

[ -f "$SKETCH/config.h" ] || cp "$SKETCH/config.h.template" "$SKETCH/config.h"

CORE_DIR="$(ls -d "$HOME/Library/Arduino15/packages/esp32/hardware/esp32/"*/ | sort -V | tail -1)"
BOOT_APP0="$CORE_DIR/tools/partitions/boot_app0.bin"

ESPTOOL="$(ls "$HOME/Library/Arduino15/packages/esp32/tools/esptool_py/"*/esptool 2>/dev/null | sort -V | tail -1)"
if [ -z "$ESPTOOL" ]; then
  echo "esptool not found under Arduino15; install the esp32 core first" >&2
  exit 1
fi

build_variant() {
  local panel="$1" extra_flags="$2"
  local out="$REPO/flasher/monoframe-fw-$panel.bin"

  echo "== Compiling ($panel) =="
  arduino-cli compile --fqbn "$FQBN" --export-binaries \
    --build-property "compiler.cpp.extra_flags=$extra_flags" "$SKETCH"

  local build="$SKETCH/build/esp32.esp32.esp32s3"
  echo "== Merging ($panel) =="
  # ESP32-S3 layout: bootloader @0x0, partition table @0x8000, boot_app0 @0xe000, app @0x10000.
  "$ESPTOOL" --chip esp32s3 merge_bin -o "$out" \
    --flash_mode dio --flash_freq 80m --flash_size 8MB \
    0x0 "$build/MonoFrameDisplay.ino.bootloader.bin" \
    0x8000 "$build/MonoFrameDisplay.ino.partitions.bin" \
    0xe000 "$BOOT_APP0" \
    0x10000 "$build/MonoFrameDisplay.ino.bin"

  echo "Wrote $out ($(stat -f %z "$out") bytes)"
}

build_variant 42 ""
build_variant 579 "-DPANEL_579"
