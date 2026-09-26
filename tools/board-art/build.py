#!/usr/bin/env python3
"""The simulator's picture of the board, rendered by KiCad from the board file.

    rake sim:board_art

runs this inside the kicad/kicad:9.0-full image (the one with the 3D models)
and writes

    sim/board/board.webp    top view of the assembled board
    sim/board_layout.rb     where things are on it, in millimetres from the
                            picture's top-left corner

Both come from the same .kicad_pcb, so a board revision is one re-run.

    build.py BOARD_DIR SIM_DIR
"""

import glob
import math
import os
import re
import shutil
import subprocess
import sys

from PIL import Image

# The board file leaves the mask and silk colours unset, which KiCad renders
# as a dull olive. These go into a copy of the stackup before rendering.
MASK_COLOR = "#0E5C2AE8"
SILK_COLOR = "White"

# Pixels per millimetre in the picture. 20 keeps the breadboard's 2.54 mm
# pitch at about 50 px when it is shown enlarged.
PX_PER_MM = 20
MARGIN_MM = 4  # parts that overhang the edge (USB-C) stay in the picture


# --- a small s-expression reader -----------------------------------------
def parse(text):
    tokens = re.findall(r'\(|\)|"(?:\\.|[^"\\])*"|[^\s()]+', text)
    stack = [[]]
    for t in tokens:
        if t == "(":
            stack.append([])
        elif t == ")":
            done = stack.pop()
            stack[-1].append(done)
        elif t.startswith('"'):
            stack[-1].append(t[1:-1])
        else:
            stack[-1].append(t)
    return stack[0][0]


def children(node, key):
    return [c for c in node if isinstance(c, list) and c and c[0] == key]


def child(node, key):
    found = children(node, key)
    return found[0] if found else None


def xy(node):
    return float(node[1]), float(node[2])


def footprints(root):
    out = {}
    for fp in children(root, "footprint"):
        ref = next(p[2] for p in children(fp, "property") if p[1] == "Reference")
        at = child(fp, "at")
        rot = float(at[3]) if len(at) > 3 else 0.0
        pads = {}
        for pad in children(fp, "pad"):
            px, py = xy(child(pad, "at"))
            # Pad positions are in the footprint's frame, turned with it.
            r = math.radians(-rot)
            wx = float(at[1]) + px * math.cos(r) - py * math.sin(r)
            wy = float(at[2]) + px * math.sin(r) + py * math.cos(r)
            net = child(pad, "net")
            pads[pad[1]] = (wx, wy, net[2] if net else None)
        out[ref] = {"x": float(at[1]), "y": float(at[2]), "pads": pads}
    return out


def edge_bbox(root):
    xs, ys = [], []
    for kind in ("gr_line", "gr_arc"):
        for g in children(root, kind):
            if child(g, "layer")[1] != "Edge.Cuts":
                continue
            for key in ("start", "mid", "end"):
                p = child(g, key)
                if p:
                    xs.append(float(p[1]))
                    ys.append(float(p[2]))
    return min(xs), min(ys), max(xs), max(ys)


# --- rendering --------------------------------------------------------------
def render(board_dir, work, bbox):
    """Render a coloured copy of the board in a scratch project directory, so
    the board's own checkout is only read."""
    pcb = glob.glob(f"{board_dir}/*.kicad_pcb")[0]
    pro = pcb[: -len(".kicad_pcb")] + ".kicad_pro"
    os.makedirs(work, exist_ok=True)
    # Footprints find their 3D models through ${KIPRJMOD}/libs, and a few
    # through paths relative to the project (lib/easyeda2kicad/...), so the
    # scratch project sees everything the board's checkout has.
    for name in os.listdir(board_dir):
        if not name.startswith(".") and not name.endswith((".kicad_pcb", ".kicad_pro")) \
                and not os.path.exists(f"{work}/{name}"):
            os.symlink(f"{board_dir}/{name}", f"{work}/{name}")
    shutil.copy(pro, f"{work}/board.kicad_pro")
    text = open(pcb).read()
    text = text.replace('(type "Top Silk Screen")', f'(type "Top Silk Screen")\n(color "{SILK_COLOR}")', 1)
    text = text.replace('(type "Top Solder Mask")', f'(type "Top Solder Mask")\n(color "{MASK_COLOR}")', 1)
    # U1 names its model the KiCad 5 way: through ${KISYS3DMOD}, which 9 no
    # longer sets, and as .wrl, which 9's library ships only as .step.
    text = re.sub(r'\$\{KISYS3DMOD\}/([^"]+)\.wrl"', r'${KICAD9_3DMODEL_DIR}/\1.step"', text)
    open(f"{work}/board.kicad_pcb", "w").write(text)

    # KiCad fits the board into the frame with a margin of its own; render
    # generously and measure where the board landed afterwards. "basic", not
    # "high": the ray tracer casts a dark shadow around the breadboard.
    w_mm, h_mm = bbox[2] - bbox[0], bbox[3] - bbox[1]
    width = int(w_mm * PX_PER_MM * 1.2)
    height = int(h_mm * PX_PER_MM * 1.2)
    out = f"{work}/render.png"
    subprocess.run(
        ["kicad-cli", "pcb", "render", "--side", "top", "--quality", "basic",
         "--width", str(width), "--height", str(height), "-o", out, f"{work}/board.kicad_pcb"],
        check=True, stdout=subprocess.DEVNULL)
    return Image.open(out).convert("RGBA")


def measure(img, bbox):
    """Where the board's edge is in the render: pixels per millimetre and the
    pixel of the board file's (0, 0). Scans lines that cross only bare edge —
    the middle of each side, clear of the connectors that overhang it."""
    alpha = img.getchannel("A")
    w, h = img.size

    def first(line):
        for i, a in enumerate(line):
            if a > 128:
                return i
        raise SystemExit("board not found in the render")

    mid_row = [alpha.getpixel((x, h // 2)) for x in range(w)]
    left, right = first(mid_row), w - 1 - first(mid_row[::-1])
    scale = (right - left) / (bbox[2] - bbox[0])
    # Top and bottom through the middle column, which the outline crosses at
    # the board's full height.
    col = [alpha.getpixel((w // 2, y)) for y in range(h)]
    top = first(col)
    return scale, left - bbox[0] * scale, top - bbox[1] * scale


# --- where things are ------------------------------------------------------
BUTTONS = [  # silk names; the xlsx names are wrong (see CLAUDE.md)
    ("SW1", "UP", 17), ("SW2", "LEFT", 18), ("SW3", "RIGHT", 19),
    ("SW4", "DOWN", 20), ("SW5", "B", 21), ("SW6", "A", 22),
]


def layout_rb(fps, origin, size, image_px):
    ox, oy = origin

    def p(x, y):
        return f"[{x - ox:.2f}, {y - oy:.2f}]"

    leds = [v for k, v in fps.items() if re.fullmatch(r"LED\d+", k)]
    if len(leds) != 256:
        raise SystemExit(f"expected 256 matrix LEDs, found {len(leds)}")
    xs = [v["x"] for v in leds]
    ys = [v["y"] for v in leds]
    bb = fps["BB1"]
    j1 = fps["J1"]

    lines = [
        "# Generated by tools/board-art/build.py from the board's .kicad_pcb.",
        "# Do not edit; run `rake sim:board_art`. Millimetres from the top-left",
        "# corner of sim/board/board.webp, x to the right and y down.",
        "module BoardLayout",
        f"  SIZE = [{size[0]:.2f}, {size[1]:.2f}]",
        f"  IMAGE_PX = [{image_px[0]}, {image_px[1]}]",
        "",
        "  # Centre of the top-left LED, and the spacing. 16 x 16.",
        f"  MATRIX_ORIGIN = {p(min(xs), min(ys))}",
        f"  MATRIX_PITCH = {(max(xs) - min(xs)) / 15:.2f}",
        "",
        "  # Mini breadboard BB1, 47 x 35 mm. 17 columns; each column is two",
        "  # strips of 5 holes (a-e above the groove, f-j below), with one missing",
        "  # row's worth of groove between e and f. Holes are at the centre plus",
        "  # (column - 8, row) pitches, rows counted from the groove.",
        f"  BREADBOARD_CENTER = {p(bb['x'], bb['y'])}",
        "  BREADBOARD_SIZE = [47.0, 35.0]",
        "  BREADBOARD_PITCH = 2.54",
        "  BREADBOARD_COLUMNS = 17",
        "  BREADBOARD_ROWS = [-5, -4, -3, -2, -1, 1, 2, 3, 4, 5]  # a..j",
        "",
        "  # J1, the 2 x 10 socket beside the breadboard: pin => [x, y, net].",
        "  J1_PINS = {",
    ]
    for num in sorted(j1["pads"], key=int):
        x, y, net = j1["pads"][num]
        lines.append(f"    {num} => [{x - ox:.2f}, {y - oy:.2f}, \"{net}\"],")
    lines += ["  }", "", "  # Buttons: [name, GPIO, centre].", "  BUTTONS = ["]
    for ref, name, pin in BUTTONS:
        f = fps[ref]
        lines.append(f"    [\"{name}\", {pin}, {p(f['x'], f['y'])}],  # {ref}")
    lines += [
        "  ]",
        "",
        f"  STATUS_LED = {p(fps['D3']['x'], fps['D3']['y'])}  # D3, green, GPIO16",
        f"  POWER_LED = {p(fps['D2']['x'], fps['D2']['y'])}   # D2, red, always on",
        "end",
        "",
    ]
    return "\n".join(lines)


def main():
    board_dir, sim_dir = sys.argv[1:3]
    pcb = glob.glob(f"{board_dir}/*.kicad_pcb")[0]
    root = parse(open(pcb).read())
    bbox = edge_bbox(root)

    img = render(board_dir, "/tmp/board-art", bbox)
    scale, x0, y0 = measure(img, bbox)

    # Crop to the board plus a margin, then bring it to PX_PER_MM.
    left_mm, top_mm = bbox[0] - MARGIN_MM, bbox[1] - MARGIN_MM
    size = (bbox[2] - bbox[0] + 2 * MARGIN_MM, bbox[3] - bbox[1] + 2 * MARGIN_MM)
    box = (round(x0 + left_mm * scale), round(y0 + top_mm * scale),
           round(x0 + (left_mm + size[0]) * scale), round(y0 + (top_mm + size[1]) * scale))
    px = (round(size[0] * PX_PER_MM), round(size[1] * PX_PER_MM))
    img = img.crop(box).resize(px, Image.LANCZOS)

    os.makedirs(f"{sim_dir}/board", exist_ok=True)
    img.save(f"{sim_dir}/board/board.webp", quality=85, method=6)
    with open(f"{sim_dir}/board_layout.rb", "w") as f:
        f.write(layout_rb(footprints(root), (left_mm, top_mm), size, px))
    kb = os.path.getsize(f"{sim_dir}/board/board.webp") // 1024
    print(f"rendered at {scale:.2f} px/mm; wrote sim/board/board.webp ({px[0]}x{px[1]}, {kb} KB) and sim/board_layout.rb")


if __name__ == "__main__":
    main()
