#!/bin/sh
# Builds the PSG renderer for the host and runs envelope_rate.c. Needs only cc.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
out=${TMPDIR:-/tmp}/psg_envelope_rate
cc -O1 -Wall -o "$out" "$here/envelope_rate.c" "$root/mrbgems/picoruby-psg/ports/common/psg.c"
"$out"
