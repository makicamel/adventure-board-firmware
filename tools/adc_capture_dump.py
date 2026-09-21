#!/usr/bin/env python3
"""Read the picoruby-adc-capture ring out of a running board over SWD.

usage: adc_capture_dump.py ADDR OLDEST [out.npy]      (the numbers T23 prints)

Reads 32768 bytes at ADDR with openocd (memory reads work without halting),
rotates them so that index 0 is the oldest sample, and saves volts as .npy.
"""
import subprocess, sys, os
import numpy as np

SIZE = 32768
addr, oldest = int(sys.argv[1], 0), int(sys.argv[2], 0)
out = sys.argv[3] if len(sys.argv) > 3 else "tmp/adc_capture.npy"
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
raw = os.path.join(root, "tmp", "adc_capture.bin")
subprocess.run(
    ["docker", "compose", "-f", "docker/compose.yml", "run", "--rm", "--entrypoint", "openocd", "flash",
     "-f", "interface/cmsis-dap.cfg", "-f", "target/rp2350.cfg", "-c", "adapter speed 1000",
     "-c", f"init; dump_image /work/tmp/adc_capture.bin {addr:#x} {SIZE}; exit"],
    cwd=root, check=True, capture_output=True)
d = np.frombuffer(open(raw, "rb").read(), dtype=np.uint8)
v = np.roll(d, -oldest).astype(np.float32) * (3.3 / 256)
np.save(out, v)
print(f"{out}: {len(v)} samples, min {v.min():.3f} V, max {v.max():.3f} V, mean {v.mean():.3f} V")
