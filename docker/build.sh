#!/usr/bin/env bash
# Builds the R2P2 firmware inside the container and copies the artifacts to
# /work/dist, which is on the bind mount and therefore visible from the host.
#
# Override the target with environment variables, e.g.
#   docker compose -f docker/compose.yml run --rm -e MODE=debug build
set -euo pipefail

VM="${VM:-picoruby}"
BOARD="${BOARD:-pico2}"
MODE="${MODE:-prod}"

cd /work

bundle check >/dev/null 2>&1 || bundle install

# The cmake build compiles the Ruby sources with ${PICORUBY_ROOT}/bin/mrbc, but
# `rake r2p2:...` only builds the cross target and its own internal mrbc under
# build/mrbc/. bin/mrbc comes from the host build, so run that first. It is
# incremental, and rake's build_host helper cleans build/host by itself when the
# VM variant changes.
rake "${VM}:${MODE}"

rake "r2p2:${VM}:${BOARD}:${MODE}"

out="/work/build/r2p2/${VM}/${BOARD}/${MODE}"
dist="/work/dist/${VM}-${BOARD}-${MODE}"
mkdir -p "$dist"

shopt -s nullglob
artifacts=("$out"/R2P2*.uf2 "$out"/R2P2*.elf)
if [ ${#artifacts[@]} -eq 0 ]; then
  echo "No R2P2 artifacts found in $out" >&2
  exit 1
fi
cp -v "${artifacts[@]}" "$dist/"

echo
echo "Artifacts copied to dist/${VM}-${BOARD}-${MODE}/ :"
ls -l "$dist"
