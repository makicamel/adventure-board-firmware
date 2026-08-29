# Build environment for picorubykaigi01-board firmware (PicoRuby / R2P2, RP2350A).
#
# Prerequisites are taken from mrbgems/picoruby-r2p2/README.md:
#   git, Ruby (CRuby 3.4+) + Bundler, cmake >= 3.22, arm-none-eabi-gcc,
#   arm-linux-gnueabihf-gcc, qemu-arm-static
# plus picotool, which pico-sdk 2.x needs to emit .uf2 images. Building it into
# the image keeps `rake r2p2:...` from fetching and compiling it on every fresh
# build directory.

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
      zip \
      unzip \
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
# refuses to run in such a tree without this.
RUN git config --global --add safe.directory '*'

# Bundler writes here; docker/compose.yml keeps it in a named volume.
ENV BUNDLE_PATH=/usr/local/bundle
ENV PICO_SDK_PATH=/work/mrbgems/picoruby-r2p2/lib/pico-sdk

WORKDIR /work
CMD ["bash"]
