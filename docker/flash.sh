#!/usr/bin/env bash
# Flashes an already-built R2P2 image onto the board over SWD, through a
# CMSIS-DAP probe (Raspberry Pi Debug Probe, or a Pico running picoprobe
# firmware), using the openocd built into the image.
#
# openocd programs an ELF, not the .uf2 that BOOTSEL drag-and-drop takes, so
# this picks the .elf of the requested target.
#
# Override the target with environment variables, e.g.
#   docker compose -f docker/compose.yml run --rm -e BOARD=pico2_w flash
set -euo pipefail

VM="${VM:-picoruby}"
BOARD="${BOARD:-pico2}"
MODE="${MODE:-prod}"
ADAPTER_SPEED="${ADAPTER_SPEED:-5000}"

case "$BOARD" in
  pico|pico_w)   target_cfg=target/rp2040.cfg ;;
  pico2|pico2_w) target_cfg=target/rp2350.cfg ;;
  *) echo "Unknown BOARD: $BOARD" >&2; exit 1 ;;
esac

elf="${ELF:-}"
if [ -z "$elf" ]; then
  # dist/ is what docker/build.sh publishes; build/ is where cmake wrote it and
  # is the only one populated by a bare `rake r2p2:...`. Newest of the two wins.
  shopt -s nullglob
  candidates=(
    "/work/dist/${VM}-${BOARD}-${MODE}"/R2P2*.elf
    "/work/build/r2p2/${VM}/${BOARD}/${MODE}"/R2P2*.elf
  )
  if [ ${#candidates[@]} -eq 0 ]; then
    echo "No R2P2 .elf for ${VM}/${BOARD}/${MODE}." >&2
    echo "Build it first: rake docker:r2p2:${VM}:${BOARD}:${MODE}" >&2
    exit 1
  fi
  # shellcheck disable=SC2012  # the names are ours and contain no newlines
  elf=$(ls -t "${candidates[@]}" | head -1)
fi

if [ ! -r "$elf" ]; then
  echo "Cannot read ELF: $elf" >&2
  exit 1
fi

echo "Flashing $elf (${BOARD}, ${target_cfg})"

exec openocd \
  -f interface/cmsis-dap.cfg \
  -f "$target_cfg" \
  -c "adapter speed ${ADAPTER_SPEED}" \
  -c "program \"${elf}\" verify reset exit"
