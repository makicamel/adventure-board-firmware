#!/usr/bin/env python3
"""Talk to an R2P2 board from WSL without babysitting the USB plumbing.

Two things make this tedious by hand. usbipd drops its attachment every time
the target resets -- and flashing resets it -- so the port disappears at the
worst moment. And the R2P2 shell is a full-screen line editor: it redraws the
prompt after every keystroke, so a naive read gives back a wall of escape
sequences with the answer buried in it.

    tools/r2p2dev.py run 'ls /lib' 'free'
    tools/r2p2dev.py reset
    tools/r2p2dev.py watch 20        # raw output, e.g. a boot log
    tools/r2p2dev.py port

Everything auto-attaches first, so a command right after a flash just works.

With R2P2_PORT set, the console is that tty instead of the board's USB -- the
UART side of a debug probe, for a firmware built with R2P2_CONSOLE_UART=1:

    R2P2_PORT=/dev/ttyACM0 tools/r2p2dev.py run 'ls /lib'
"""

import argparse
import glob
import os
import re
import select
import struct
import subprocess
import termios
import sys
import time
import zlib

USBIPD = "/mnt/c/Program Files/usbipd-win/usbipd.exe"
BY_ID = "/dev/serial/by-id"
# The R2P2 CDC descriptor; if00 is the shell console, if02/if04 are spare.
CONSOLE_GLOB = "usb-PicoRuby_R2P2_"
CONSOLE_IFACE = "-if00"
ANSI = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]")
PROMPT = re.compile(r"(?:^|\n)(?:\$|irb)> ?$")


def _usbipd(*args, check=True):
    return subprocess.run([USBIPD, *args], capture_output=True, text=True,
                          check=False)


# The board answers on the shared CDC vendor id; the Debug Probe is a
# Raspberry Pi CMSIS-DAP. Both get unplugged from WSL whenever the target
# resets, and flashing resets the target, so both are looked up the same way.
BOARD_VID = "16c0"
PROBE_ID = "2e8a:000c"
BOOTSEL_ID = "2e8a:000f"   # the RP2350 ROM bootloader


def find_device(vid_or_id):
    """(busid, rest-of-line) for the first device matching a vid or vid:pid."""
    for line in _usbipd("list").stdout.splitlines():
        m = re.match(r"^(\d+-\d+)\s+([0-9a-f]{4}:[0-9a-f]{4})\s+(.*)$",
                     line.strip())
        if m and m.group(2).startswith(vid_or_id):
            return m.group(1), m.group(3)
    return None, None


def find_busid():
    return find_device(BOARD_VID)


def attach_busid(busid, desc, verbose=True):
    if desc.rstrip().endswith("Attached"):
        return
    if "Shared" not in desc:
        # bind needs administrator, so this pops a UAC prompt on the desktop.
        if verbose:
            print(f"binding {busid} (approve the UAC prompt on Windows)",
                  file=sys.stderr)
        subprocess.run(["powershell.exe", "-NoProfile", "-Command",
                        f"Start-Process -FilePath '{USBIPD}' "
                        f"-ArgumentList 'bind','--busid','{busid}' "
                        f"-Verb RunAs -Wait -WindowStyle Hidden"],
                       capture_output=True, text=True, cwd="/mnt/c")
    r = _usbipd("attach", "--wsl", "--busid", busid)
    if verbose and r.returncode and r.stderr.strip():
        print(r.stderr.strip(), file=sys.stderr)


def attach_probe(verbose=True):
    """Put the CMSIS-DAP probe back on the WSL bus, for openocd."""
    busid, desc = find_device(PROBE_ID)
    if not busid:
        return False
    attach_busid(busid, desc, verbose)
    return True


def attach(verbose=True):
    """Make sure the board is visible in WSL. Returns the console tty path."""
    path = console_path()
    if path:
        return path
    # A reset takes the board off the USB bus for a moment, so it can be
    # missing from the list entirely for a second or two after openocd runs.
    end = time.time() + 10.0
    busid = None
    while time.time() < end:
        busid, desc = find_busid()
        if busid:
            break
        time.sleep(0.5)
    if not busid:
        die("No R2P2 board in `usbipd list`. Is it plugged in and running?")
    attach_busid(busid, desc, verbose)
    path = wait_for_console(10.0)
    if not path:
        die(f"Attached {busid} but no console appeared under {BY_ID}.")
    return path


def console_path():
    # A console that is not the board's own USB: the UART side of a debug
    # probe, for a board whose USB does not work. The path is fixed, so there
    # is nothing to attach or wait for.
    fixed = os.environ.get("R2P2_PORT")
    if fixed:
        return fixed
    try:
        names = os.listdir(BY_ID)
    except FileNotFoundError:
        return None
    for name in names:
        if name.startswith(CONSOLE_GLOB) and name.endswith(CONSOLE_IFACE):
            return os.path.realpath(os.path.join(BY_ID, name))
    return None


def wait_for_console(timeout):
    end = time.time() + timeout
    while time.time() < end:
        path = console_path()
        if path:
            time.sleep(0.3)   # let the tty settle before the first open
            return path
        time.sleep(0.2)
    return None


class Console:
    """A line-oriented view of the R2P2 shell.

    Opened non-blocking with clocal set: a wedged board then fails fast
    instead of hanging the open forever on carrier detect.
    """

    def __init__(self, path):
        self.path = path
        # O_NONBLOCK on the open and CLOCAL in the termios flags, both set
        # from here rather than by shelling out to stty: stty opens the port
        # itself and blocks on carrier detect, so a wedged board would hang
        # the tool before it ever got a chance to notice.
        self.fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        a = termios.tcgetattr(self.fd)
        a[0] = 0                                        # iflag: no translation
        a[1] = 0                                        # oflag: no post-processing
        a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
        a[3] = 0                                        # lflag: no echo, no canon
        a[4] = a[5] = termios.B115200
        a[6][termios.VMIN] = 0
        a[6][termios.VTIME] = 0
        termios.tcsetattr(self.fd, termios.TCSANOW, a)

    def close(self):
        os.close(self.fd)

    def _read(self, seconds, done=None):
        """Read until `done(stripped_text)` says so, or the time runs out."""
        chunk = ""
        end = time.time() + seconds
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.1)
            if not r:
                continue
            try:
                data = os.read(self.fd, 4096)
            except BlockingIOError:
                continue
            if not data:
                continue
            chunk += data.decode("utf-8", "replace")
            if done and done(ANSI.sub("", chunk)):
                break
        return chunk

    def _write(self, data, timeout=2.0):
        """Write every byte, waiting out a full device buffer.

        The fd is non-blocking so a board that is busy compiling stops
        draining and the write returns EAGAIN rather than blocking.
        """
        end = time.time() + timeout
        while data and time.time() < end:
            _, w, _ = select.select([], [self.fd], [], 0.1)
            if not w:
                continue
            try:
                n = os.write(self.fd, data)
            except BlockingIOError:
                continue
            data = data[n:]

    def command(self, cmd, wait=3.0, settle=0.006):
        """Send one line and return just what the board printed back.

        The board echoes each character, so the reply is whatever follows the
        last echo of the command itself.
        """
        for ch in cmd + "\r":
            self._write(ch.encode())
            time.sleep(settle)
        # The board redraws the whole prompt line after every keystroke, so a
        # bare "ends with a prompt" test fires in the middle of its own echo.
        # Wait for the echo of the complete command first, then for a prompt
        # after it.
        echo = re.compile(r"> " + re.escape(cmd) + r"\n")
        def done(text):
            m = echo.search(text)
            return bool(m) and bool(PROMPT.search(text[m.end():]))
        raw = self._read(wait, done=done)
        text = ANSI.sub("", raw).replace("\r\n", "\n").replace("\r", "\n")
        # The last redraw is the whole command sitting after a prompt and
        # followed by a newline. Anchoring on that keeps us from matching the
        # command's own word where it reappears in the output.
        echo = re.search(r"> " + re.escape(cmd) + r"\n", text)
        if echo:
            text = text[echo.end():]
        text = re.sub(r"\n?(?:\$|irb)> ?$", "", text)
        return text.strip("\n")

    def sync(self, timeout=8.0):  # noqa: C901
        """Get to a known prompt, leaving irb if we are in it.

        Right after a reset the board is still printing its banner, so this
        keeps nudging until a prompt actually comes back; without it the first
        command lands in the boot output and its reply is lost.
        """
        end = time.time() + timeout
        while time.time() < end:
            self._write(b"\x03")
            self._read(0.4)
            self._write(b"\r")
            out = self._read(0.8, done=lambda t: bool(PROMPT.search(t)))
            if PROMPT.search(ANSI.sub("", out)):
                return True
        return False

    def ask(self, cmd, wait=8.0):
        """command(), but printed the way a session reads."""
        print(f"$> {cmd}")
        out = self.command(cmd, wait=wait)
        if out:
            print(out)
        return out


def open_console(attempts=8):
    """A Console on the board, re-resolving the tty if it moved.

    A reboot re-enumerates the device, and for a moment /dev/serial/by-id
    still points at the node that went away: opening it succeeds and the
    first write comes back EIO. Resolve again and try once more.
    """
    last = None
    for _ in range(attempts):
        path = attach()
        con = None
        try:
            con = Console(path)
            # Getting a prompt back is the only proof the node is the live
            # one; a write alone can succeed against the node that is on its
            # way out and fail on the next call instead.
            if con.sync(timeout=6.0):
                return con
            last = "no prompt"
        except OSError as e:
            last = e
        if con:
            try:
                con.close()
            except OSError:
                pass
        # A board that has just been flashed takes a few seconds to come back,
        # and until it does the by-id link points at nothing.
        time.sleep(2.0)
    die(f"Cannot talk to the board: {last}")


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


def cmd_port(args):
    print(attach())


def cmd_watch(args):
    """Print whatever the board says for a while, without touching it.

    For boot logs: the shell's prompt dance is not needed, and sending
    anything while the target is coming up is what wedged the debug probe.
    """
    con = Console(attach())
    try:
        end = time.time() + args.seconds
        while time.time() < end:
            sys.stdout.write(con._read(0.5))
            sys.stdout.flush()
    finally:
        con.close()
    print()


def cmd_run(args):
    con = open_console()
    try:
        con.sync()
        for cmd in args.command:
            out = con.command(cmd, wait=args.wait)
            print(f"$> {cmd}")
            if out:
                print(out)
    finally:
        con.close()


def cmd_recover(args):
    """Erase the flash and reload from BOOTSEL, when SWD can no longer help.

    A hung VM can leave the chip in a state where openocd examines the cores
    but cannot read a single word of memory, so there is no way to reflash and
    no way to erase the filesystem. The ROM bootloader always answers.
    """
    busid, desc = find_device(BOOTSEL_ID)
    if not busid:
        die("No RP2350 bootloader on the bus.\n"
            "Hold BOOTSEL on the board while plugging its USB in, then retry.")
    attach_busid(busid, desc)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    images = sorted(glob.glob(f"{root}/dist/*/R2P2*.uf2"),
                    key=os.path.getmtime, reverse=True)
    if not images:
        die("No .uf2 under dist/. Build one first.")
    image = args.image or images[0]
    env = {**os.environ, "HOST_UID": str(os.getuid()),
           "HOST_GID": str(os.getgid())}
    compose = ["docker", "compose", "-f", f"{root}/docker/compose.yml", "run",
               "--rm", "--entrypoint", "picotool", "flash"]
    print(f"erasing the whole flash (this also clears the filesystem)")
    subprocess.run(compose + ["erase", "--all"], env=env,
                   stdout=subprocess.DEVNULL)
    inside = "/work" + image[len(root):]
    print(f"loading {os.path.basename(image)}")
    r = subprocess.run(compose + ["load", "-x", inside], env=env,
                       capture_output=True, text=True)
    if r.returncode:
        die(r.stderr.strip() or r.stdout.strip())
    print(attach())


def cmd_push(args):
    """Copy a local file onto the board through the shell's own `dfucli`.

    dfucli <path> puts the console in raw mode and takes a 19-byte DFU header
    followed by the file body, so this is binary-safe and needs nothing on the
    device beyond stock R2P2. The earlier version typed the file into irb a
    line at a time, which died of NoMemoryError on any line irb took for the
    start of a multi-line construct (`def`, `do`), and irb has little heap.

    The device's stdin ring buffer is 1KB and the receiver does not drain it
    promptly -- 256 bytes every 40ms lost everything past byte 1023 -- so the
    body goes out in small pieces with a long pause between. Slow, but a
    sample is a few KB.
    """
    data = open(args.local, "rb").read()
    kind = b"RITE" if args.local.endswith(".mrb") else b"RUBY"
    header = struct.pack(">4sB4sIIH", b"DFU\0", 1, kind, len(data),
                         zlib.crc32(data) & 0xffffffff, 0)
    con = open_console()
    try:
        con.sync()
        con._write(f"dfucli {args.remote}\r".encode())
        out = con._read(5.0, done=lambda t: "reading header" in t)
        if "reading header" not in out:
            die(f"dfucli did not start:\n{ANSI.sub('', out).strip()[-400:]}")
        payload = header + data
        # Short pieces: the board's stdin ring is 1 KB and the reader is Ruby.
        # 256 bytes at a time was lost now and then over the probe's UART, and
        # what dfucli did not take went to the shell as commands.
        for i in range(0, len(payload), 64):
            con._write(payload[i:i + 64])
            time.sleep(0.04)
        out = con._read(15.0, done=lambda t: "DFU: " in t)
        text = ANSI.sub("", out)
        m = re.search(r"DFU: .*", text)
        if not m or "error" in m.group(0):
            die(f"push failed:\n{text.strip()[-600:]}")
        print(f"{args.local} -> {args.remote} ({len(data)} bytes)")
    finally:
        con.close()
def cmd_attach(args):
    attach_probe()
    print(attach())


# A full chip reset, driven through the watchdog rather than openocd's own
# `reset`. openocd resets the core with SYSRESETREQ, which leaves the
# peripherals -- USB among them -- exactly as they were, and R2P2 starting up
# against a half-live USB device hangs before it reaches a prompt. Every board
# that went silent on us went silent right after one of those. This is the
# sequence watchdog_reboot() runs on the device: tell the power-on state
# machine to reset everything but the oscillators, clear the scratch register
# that would otherwise redirect the boot, and pull the trigger.
WATCHDOG_CTRL = 0x400d8000
WATCHDOG_SCRATCH4 = 0x400d801c
PSM_WDSEL = 0x40018008
PSM_WDSEL_ALL_BUT_OSC = 0x01fffff3   # PSM_WDSEL_BITS & ~(ROSC | XOSC)
WATCHDOG_TRIGGER = 0x80000000


REBOOT_TCL = (f"mww {PSM_WDSEL:#x} {PSM_WDSEL_ALL_BUT_OSC:#x};"
              f" mww {WATCHDOG_SCRATCH4:#x} 0;"
              f" mww {WATCHDOG_CTRL:#x} {WATCHDOG_TRIGGER:#x};")

# The littlefs region on RP2350: FLASH_TARGET_OFFSET 0x00380000, 128 blocks of
# 4096. The firmware ends more than a megabyte below it.
LITTLEFS_ADDR = 0x10380000
LITTLEFS_SIZE = 0x00080000


def settle(timeout=25.0):
    """Wait until the board is sitting at a prompt.

    A board that has just been flashed is still booting, and this firmware
    writes files to flash on the way up. Erasing or halting through SWD while
    it is doing that leaves the filesystem half-written and, once, left the
    USB device unable to answer a descriptor request at all. Waiting for a
    prompt is proof that boot finished, which a sleep is not.
    """
    end = time.time() + timeout
    while time.time() < end:
        path = console_path()
        if path:
            con = None
            try:
                con = Console(path)
                if con.sync(timeout=4.0):
                    return True
            except OSError:
                pass
            finally:
                if con:
                    try:
                        con.close()
                    except OSError:
                        pass
        time.sleep(1.0)
    print("board never reached a prompt; continuing anyway", file=sys.stderr)
    return False


def _openocd(tcl):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return subprocess.run(
        ["docker", "compose", "-f", f"{root}/docker/compose.yml", "run",
         "--rm", "--entrypoint", "openocd", "flash",
         "-f", "interface/cmsis-dap.cfg", "-f", "target/rp2350.cfg",
         "-c", "adapter speed 5000", "-c", tcl],
        check=False, capture_output=True, text=True,
        env={**os.environ, "HOST_UID": str(os.getuid()),
             "HOST_GID": str(os.getgid())})


def cmd_reset(args):
    """Reboot the board the way its own firmware would, then reconnect."""
    attach_probe()
    attach()
    settle()
    _openocd("init; catch {halt}; " + REBOOT_TCL + " exit")
    print(attach())


def cmd_wipefs(args):
    """Erase the device filesystem, so the next boot rebuilds it.

    The firmware replaces a file it carries a newer copy of and leaves the
    samples alone once a board has them, so a change to an example only
    reaches a board this way.
    """
    attach_probe()
    attach()
    settle()
    r = _openocd(f"init; reset init;"
                 f" flash erase_address {LITTLEFS_ADDR:#x} {LITTLEFS_SIZE:#x};"
                 f" exit")
    if "erased" not in (r.stdout + r.stderr).lower():
        die((r.stdout + r.stderr).strip()[-800:] or "erase failed")
    print(f"erased {LITTLEFS_SIZE // 1024}KB at {LITTLEFS_ADDR:#x}")
    # Rebooting needs its own session: openocd leaves the target somewhere the
    # plain memory writes below cannot reach after a flash operation.
    _openocd("init; catch {halt}; " + REBOOT_TCL + " exit")
    print(attach())


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("port", help="print the console tty, attaching if needed")
    sub.add_parser("attach", help="put the probe and the board on the WSL bus")
    sub.add_parser("wipefs",
                   help="erase the device filesystem and reboot")
    rec = sub.add_parser("recover",
                         help="erase and reload from BOOTSEL (last resort)")
    rec.add_argument("image", nargs="?",
                     help="path to a .uf2 (default: newest under dist/)")
    u = sub.add_parser("push", help="copy a local file onto the board")
    u.add_argument("local")
    u.add_argument("remote")
    r = sub.add_parser("run", help="run shell commands on the board")
    r.add_argument("command", nargs="+")
    r.add_argument("--wait", type=float, default=3.0,
                   help="seconds to wait for each reply (default 3)")
    sub.add_parser("reset", help="reset the target over SWD and re-attach")
    w = sub.add_parser("watch", help="print raw console output for a while")
    w.add_argument("seconds", type=float, nargs="?", default=20.0)
    args = p.parse_args()
    {"port": cmd_port, "attach": cmd_attach, "push": cmd_push, "watch": cmd_watch,
     "run": cmd_run, "reset": cmd_reset, "wipefs": cmd_wipefs,
     "recover": cmd_recover}[args.cmd](args)


if __name__ == "__main__":
    main()
