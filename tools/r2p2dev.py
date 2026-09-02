#!/usr/bin/env python3
"""Talk to an R2P2 board from WSL without babysitting the USB plumbing.

Two things make this tedious by hand. usbipd drops its attachment every time
the target resets -- and flashing resets it -- so the port disappears at the
worst moment. And the R2P2 shell is a full-screen line editor: it redraws the
prompt after every keystroke, so a naive read gives back a wall of escape
sequences with the answer buried in it.

    tools/r2p2dev.py run 'ls /lib' 'free'
    tools/r2p2dev.py reset
    tools/r2p2dev.py port

Everything auto-attaches first, so a command right after a flash just works.
"""

import argparse
import glob
import os
import re
import select
import subprocess
import termios
import sys
import time

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

    def sync(self, timeout=8.0):
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


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


def cmd_port(args):
    print(attach())


def cmd_run(args):
    con = Console(attach())
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
    """Copy a local file onto the board, a line at a time through irb.

    Slow, but it needs nothing on the device beyond File, which means it works
    on a stock R2P2. For anything big, put the file in the firmware instead.
    """
    con = Console(attach())
    try:
        con.sync()
        con.command("irb", wait=4.0)
        con.command(f'f = File.open("{args.remote}", "w")', wait=4.0)
        with open(args.local) as fh:
            for line in fh:
                body = (line.rstrip("\n")
                        .replace("\\", "\\\\")
                        .replace('"', '\\"')
                        .replace("#", "\\#"))
                out = con.command(f'f.write "{body}\\n"', wait=3.0)
                if "Error" in out:
                    die(f"push failed on: {line.rstrip()}\n{out}")
        con.command("f.close", wait=3.0)
        con.command("quit", wait=3.0)
        print(f"{args.local} -> {args.remote}")
    finally:
        con.close()


def cmd_attach(args):
    attach_probe()
    print(attach())


def cmd_reset(args):
    """Reset over SWD, then put the board back on the USB bus."""
    attach_probe()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    subprocess.run(
        ["docker", "compose", "-f", f"{root}/docker/compose.yml", "run",
         "--rm", "--entrypoint", "openocd", "flash",
         "-f", "interface/cmsis-dap.cfg", "-f", "target/rp2350.cfg",
         "-c", "adapter speed 5000", "-c", "init; reset run; exit"],
        check=False, capture_output=True, text=True,
        env={**os.environ, "HOST_UID": str(os.getuid()),
             "HOST_GID": str(os.getgid())})
    print(attach())


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("port", help="print the console tty, attaching if needed")
    sub.add_parser("attach", help="put the probe and the board on the WSL bus")
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
    args = p.parse_args()
    {"port": cmd_port, "attach": cmd_attach, "push": cmd_push,
     "run": cmd_run, "reset": cmd_reset,
     "recover": cmd_recover}[args.cmd](args)


if __name__ == "__main__":
    main()
