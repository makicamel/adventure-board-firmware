# Build environment for picorubykaigi01-board firmware (PicoRuby / R2P2, RP2350A).
#
# Prerequisites are taken from mrbgems/picoruby-r2p2/README.md:
#   git, Ruby (CRuby 3.4+) + Bundler, cmake >= 3.22, arm-none-eabi-gcc,
#   arm-linux-gnueabihf-gcc, qemu-arm-static
# plus picotool, which pico-sdk 2.x needs to emit .uf2 images. Building it into
# the image keeps `rake r2p2:...` from fetching and compiling it on every fresh
# build directory.

# openocd is built from Raspberry Pi's fork because Debian's 0.12.0 predates
# RP2350 and has no target/rp2350.cfg. sdk-2.0.0 is the branch the Pico SDK
# documentation points at. It is built in a stage of its own so that autotools
# and texinfo do not end up in the image that flashes the board.
FROM ruby:3.4-slim-bookworm AS openocd

ARG OPENOCD_BRANCH=sdk-2.0.0

RUN apt-get update && apt-get install -y --no-install-recommends \
      autoconf \
      automake \
      build-essential \
      ca-certificates \
      git \
      libftdi1-dev \
      libhidapi-dev \
      libtool \
      libusb-1.0-0-dev \
      pkg-config \
      texinfo \
    && rm -rf /var/lib/apt/lists/*

# CMSIS-DAP v2 (bulk) is what a Debug Probe and current picoprobe firmware
# speak; v1 (HID, via hidapi) covers older picoprobe builds.
RUN git clone --depth 1 --branch "${OPENOCD_BRANCH}" https://github.com/raspberrypi/openocd.git /tmp/openocd \
    && cd /tmp/openocd \
    && ./bootstrap \
    && ./configure --prefix=/opt/openocd --enable-cmsis-dap --enable-cmsis-dap-v2 --disable-werror \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /tmp/openocd


FROM ruby:3.4-slim-bookworm

ARG PICO_SDK_TAG=2.3.0
ARG PICOTOOL_TAG=2.3.0

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      cmake \
      ninja-build \
      git \
      python3 \
      pkg-config \
      gcc-arm-none-eabi \
      binutils-arm-none-eabi \
      libnewlib-arm-none-eabi \
      libstdc++-arm-none-eabi-newlib \
      gcc-arm-linux-gnueabihf \
      qemu-user-static \
      libusb-1.0-0-dev \
      libssl-dev \
      libftdi1-2 \
      libhidapi-hidraw0 \
      libhidapi-libusb0 \
      zip \
      unzip \
      brotli \
    && rm -rf /var/lib/apt/lists/*

# picotool needs the SDK headers to configure. The SDK copy here is only for
# that; the firmware build uses the pico-sdk submodule inside the repository.
RUN git clone --depth 1 --branch "${PICO_SDK_TAG}" https://github.com/raspberrypi/pico-sdk.git /opt/pico-sdk \
    && git clone --depth 1 --branch "${PICOTOOL_TAG}" https://github.com/raspberrypi/picotool.git /tmp/picotool \
    && cmake -S /tmp/picotool -B /tmp/picotool/build -G Ninja \
         -DPICO_SDK_PATH=/opt/pico-sdk \
         -DCMAKE_INSTALL_PREFIX=/usr/local \
         -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /tmp/picotool/build --target install \
    && rm -rf /tmp/picotool /opt/pico-sdk

# The repository is bind-mounted from the host, so its files are not owned by
# the container user. `rake r2p2:check_pico_sdk` shells out to git, which
# refuses to run in such a tree without this. It goes into the system config
# rather than a global one because the container runs as the host's uid/gid
# (see docker/compose.yml), which has no passwd entry and therefore no home.
RUN git config --system --add safe.directory '*'

# That uid has no home directory either, so point HOME at a writable path
# instead of letting Docker default it to /.
ENV HOME=/tmp

# Bundler writes here; docker/compose.yml keeps it in a named volume. The
# named volume is seeded from the image, so the permissions have to be opened
# up here for an arbitrary uid to install into it.
ENV BUNDLE_PATH=/usr/local/bundle
RUN mkdir -p "$BUNDLE_PATH" && chmod -R a+rwX "$BUNDLE_PATH"
ENV PICO_SDK_PATH=/work/mrbgems/picoruby-r2p2/lib/pico-sdk

# openocd locates its scripts relative to the binary, so the whole prefix is
# copied over as one. docker/flash.sh drives it; see the `flash` service in
# docker/compose.yml for how the probe is reached.
COPY --from=openocd /opt/openocd /opt/openocd
ENV PATH=/opt/openocd/bin:$PATH

WORKDIR /work
CMD ["bash"]
