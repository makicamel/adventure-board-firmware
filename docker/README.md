# Docker build environment

Firmware for **picorubykaigi01-board** (RP2350A, no wireless) is built inside a
container so the toolchain does not have to be installed on the host.

## Prerequisites

- Docker Desktop with the WSL2 backend, with integration enabled for the
  Ubuntu distro.
- **The working copy must live on the WSL2 ext4 filesystem** (e.g.
  `~/dev/picorubykaigi01-board-firmware`), not under `/mnt/c`. picoruby tracks
  symlinks -- `mrblib`, `mrbgems/picoruby-mbedtls/lib/mbedtls`,
  `mrbgems/picoruby-socket/lib/lwip` and others -- and a Windows checkout
  materialises them as plain text files containing the target path, which
  breaks the build. Editing from Windows still works through VS Code's
  Remote-WSL extension, or via `\\wsl.localhost\Ubuntu\home\<user>\dev\...`.

## Build the image

```console
docker compose -f docker/compose.yml build
```

The image installs the prerequisites listed in
`mrbgems/picoruby-r2p2/README.md` (Ruby 3.4, cmake, `arm-none-eabi-gcc`,
`arm-linux-gnueabihf-gcc`, `qemu-arm-static`) plus **picotool**, which pico-sdk
2.x needs in order to emit `.uf2` images.

## Build the firmware

```console
docker compose -f docker/compose.yml run --rm build
```

Artifacts land in `dist/picoruby-pico2-prod/` on the host (git-ignored).

Override the target with environment variables:

```console
# debug build (also produces the .elf for Picoprobe/gdb)
docker compose -f docker/compose.yml run --rm -e MODE=debug build

# mruby/c VM instead of the mruby VM
docker compose -f docker/compose.yml run --rm -e VM=femtoruby build
```

Valid values follow the upstream rake tasks `r2p2:{VM}:{BOARD}:{MODE}` —
`VM` is `picoruby` or `femtoruby`, `BOARD` is `pico`/`pico_w`/`pico2`/`pico2_w`,
`MODE` is `prod` or `debug`.

## Interactive shell

```console
docker compose -f docker/compose.yml run --rm shell
```

From there the ordinary upstream commands work, e.g. `rake r2p2:picoruby:pico2:prod`
or `rake` for the host build.

## Flashing

Flashing is done from Windows, not from the container: hold BOOTSEL while
plugging the board in, then copy the `.uf2` from `dist/` onto the `RPI-RP2`
drive.

## Notes

- Compiler output stays in the working tree (`build/`, `bin/`), both
  git-ignored upstream; `docker/build.sh` additionally copies the finished
  artifacts to `dist/`. Only the bundled gems live in a Docker volume -- drop
  it with `docker compose -f docker/compose.yml down -v`.
- `BOARD=pico2` uses the stock Raspberry Pi Pico 2 board definition from
  pico-sdk. picorubykaigi01-board is a custom RP2350A design (W25Q32/W25Q64
  flash, 12 MHz crystal), so a dedicated board header under
  `mrbgems/picoruby-r2p2/lib/pico-sdk/src/boards/include/boards/` — or a
  `PICO_BOARD_HEADER_DIRS` entry pointing at one kept in this repository — is
  still to be added.
