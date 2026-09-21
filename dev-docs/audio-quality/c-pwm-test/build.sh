#!/usr/bin/env bash
# リポジトリの根で: docker compose -f docker/compose.yml run --rm shell dev-docs/audio-quality/c-pwm-test/build.sh
# 成果物: tmp/c-pwm-test/c_pwm_test.uf2（BOOTSEL でドラッグ&ドロップ）と .elf（SWD）
set -euo pipefail
src="$(cd "$(dirname "$0")" && pwd)"
out=/work/tmp/c-pwm-test
cmake -S "$src" -B "$out" -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build "$out"
ls -la "$out"/c_pwm_test.uf2 "$out"/c_pwm_test.elf
