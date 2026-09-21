# PicoRuby を通さない PWM の確認用（report.md A-9）。pico-sdk だけで組む。
# ビルドは build.sh（Docker の中で）。
cmake_minimum_required(VERSION 3.22)
set(PICO_BOARD pico2)
include($ENV{PICO_SDK_PATH}/external/pico_sdk_import.cmake)
project(c_pwm_test C CXX ASM)
set(CMAKE_C_STANDARD 11)
pico_sdk_init()

add_executable(c_pwm_test main.c)
target_link_libraries(c_pwm_test pico_stdlib hardware_pwm hardware_clocks)
# USB も UART も使わない。音の経路以外を動かさないため
pico_enable_stdio_usb(c_pwm_test 0)
pico_enable_stdio_uart(c_pwm_test 0)
pico_add_extra_outputs(c_pwm_test)
