#!/usr/bin/env python3
"""Convert a DS100 oscilloscope screenshot (4-bit RLE BMP with a wrong bfSize) to PNG.
usage: ds100bmp.py IN.BMP [OUT.png]   (default: same name, .png, 2x upscaled)"""
import struct, sys
from PIL import Image

def decode(path):
    d = open(path, 'rb').read()
    off = struct.unpack('<I', d[10:14])[0]
    hs, w, h, _pl, bpp, comp = struct.unpack('<IiiHHI', d[14:34])
    ncol = struct.unpack('<I', d[46:50])[0] or (1 << bpp)
    pal = [tuple(d[54 + 4 * i:54 + 4 * i + 3][::-1]) for i in range(ncol)]
    assert bpp == 4 and comp == 2, (bpp, comp)
    px = [[0] * w for _ in range(h)]
    x = y = 0
    i = off
    while i + 1 < len(d) and y < h:
        n, c = d[i], d[i + 1]; i += 2
        if n > 0:
            for k in range(n):
                if x < w and y < h:
                    px[y][x] = (c >> 4) if k % 2 == 0 else (c & 15)
                x += 1
        elif c == 0:
            x = 0; y += 1
        elif c == 1:
            break
        elif c == 2:
            x += d[i]; y += d[i + 1]; i += 2
        else:
            for k in range(c):
                b = d[i + k // 2]
                if x < w and y < h:
                    px[y][x] = (b >> 4) if k % 2 == 0 else (b & 15)
                x += 1
            i += (c + 1) // 2
            i += i % 2  # word align
    im = Image.new('RGB', (w, h))
    im.putdata([pal[px[h - 1 - yy][xx]] for yy in range(h) for xx in range(w)])
    return im

if __name__ == '__main__':
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else src.rsplit('.', 1)[0] + '.png'
    im = decode(src)
    im.resize((im.width * 2, im.height * 2), Image.NEAREST).save(dst)
    print(dst)
