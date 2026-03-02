#!/usr/bin/env python3
"""Validates a cropped Garmin watch face screenshot (264x264 PNG).

The watch face circle is assumed to be centered at (132, 132) with display
radius 130px — matching the fr255's 260x260 circular display at 1:1 scale.

Usage:
  validate_screen.py content  <watch_face.png>
      Exit 0 = content visible, 1 = blank/missing

  validate_screen.py overflow <watch_face.png>
      Exit 0 = nothing outside boundary, 1 = overflow detected

  validate_screen.py scroll   <before.png> <after.png>
      Exit 0 = screenshots differ (scroll worked), 1 = identical

All commands print a JSON result to stdout.
"""

import sys, struct, zlib, math, json

# Display circle parameters within the 264x264 crop
CX, CY = 132, 132   # center of watch face display
DR = 130            # display radius (device is 260x260, radius=130)


# ── PNG decoder (stdlib only) ─────────────────────────────────────────────────

def read_png(path):
    """Decode a PNG file to a list of rows, each row a list of (R, G, B) tuples.
    Handles color types: 0=Grayscale, 2=RGB, 3=Indexed, 4=Gray+Alpha, 6=RGBA.
    Only supports bit_depth=8.
    """
    with open(path, 'rb') as f:
        data = f.read()

    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError("Not a PNG file: " + path)

    pos = 8
    width = height = color_type = 0
    idat_parts = []
    palette = []

    while pos + 8 <= len(data):
        length = struct.unpack('>I', data[pos:pos+4])[0]
        ctype  = data[pos+4:pos+8]
        cdata  = data[pos+8:pos+8+length]
        pos   += 12 + length

        if ctype == b'IHDR':
            width, height = struct.unpack('>II', cdata[:8])
            color_type = cdata[9]
        elif ctype == b'PLTE':
            palette = [tuple(cdata[i:i+3]) for i in range(0, len(cdata), 3)]
        elif ctype == b'IDAT':
            idat_parts.append(cdata)
        elif ctype == b'IEND':
            break

    raw = zlib.decompress(b''.join(idat_parts))

    bpp = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(color_type, 3)
    stride = width * bpp
    rows = []
    prev = bytes(stride)

    for y in range(height):
        base  = y * (stride + 1)
        ftype = raw[base]
        row   = bytearray(raw[base+1:base+1+stride])

        if ftype == 1:    # Sub
            for i in range(bpp, stride):
                row[i] = (row[i] + row[i-bpp]) & 0xFF
        elif ftype == 2:  # Up
            for i in range(stride):
                row[i] = (row[i] + prev[i]) & 0xFF
        elif ftype == 3:  # Average
            for i in range(stride):
                a = row[i-bpp] if i >= bpp else 0
                row[i] = (row[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:  # Paeth
            for i in range(stride):
                a  = row[i-bpp] if i >= bpp else 0
                b  = prev[i]
                c  = prev[i-bpp] if i >= bpp else 0
                p  = a + b - c
                pa, pb, pc = abs(p-a), abs(p-b), abs(p-c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                row[i] = (row[i] + pr) & 0xFF

        # Convert to RGB tuples
        row_rgb = []
        for x in range(width):
            o = x * bpp
            if color_type in (2,):     # RGB
                row_rgb.append((row[o], row[o+1], row[o+2]))
            elif color_type in (6,):   # RGBA
                row_rgb.append((row[o], row[o+1], row[o+2]))
            elif color_type in (0,4):  # Grayscale / Gray+Alpha
                v = row[o]; row_rgb.append((v, v, v))
            elif color_type == 3:      # Indexed
                row_rgb.append(tuple(palette[row[o]][:3]) if palette else (0,0,0))
            else:
                row_rgb.append((row[o], row[o+1], row[o+2]))
        rows.append(row_rgb)
        prev = bytes(row)

    return width, height, rows


def luma(r, g, b):
    """Perceived brightness 0-255."""
    return (r * 299 + g * 587 + b * 114) // 1000


# ── checks ────────────────────────────────────────────────────────────────────

def check_content(path, min_bright_frac=0.01, bright_threshold=30):
    """Verify that at least min_bright_frac of pixels inside the display circle
    have brightness > bright_threshold (i.e. the screen is not blank)."""
    w, h, rows = read_png(path)
    inside = bright = 0

    for y in range(h):
        for x in range(w):
            if (x-CX)**2 + (y-CY)**2 <= DR*DR:
                inside += 1
                if luma(*rows[y][x]) > bright_threshold:
                    bright += 1

    frac = bright / inside if inside else 0
    ok   = frac >= min_bright_frac
    return {
        'pass':           ok,
        'bright_pixels':  bright,
        'total_pixels':   inside,
        'bright_fraction': round(frac, 4),
        'reason': '' if ok else
            f'Only {bright}/{inside} ({frac*100:.1f}%) pixels are lit — screen appears blank',
    }


def check_overflow(path, inner_r=DR+2, outer_r=DR+15, bright_threshold=100):
    """Check for app-rendered content just outside the display boundary.

    Only pixels in the narrow band (inner_r < r ≤ outer_r) are checked.
    This avoids false positives from the simulator's watch bezel decoration
    which appears at r > 145 with brightness < 100.

    Band calibration for fr255 simulator crop (264x264):
      r = 130-135: always 0 bright pixels (display edge is clean)
      r = 135-145: bezel inner edge, max brightness ~92
      r = 145+:    bezel labels ("LIGHT", "START", etc.), brightness up to ~219
    → Checking r = 132-145 with threshold=100 catches only true app overflow.
    """
    w, h, rows = read_png(path)
    violations = []

    for y in range(h):
        for x in range(w):
            dist = ((x-CX)**2 + (y-CY)**2) ** 0.5
            if inner_r < dist <= outer_r:
                b = luma(*rows[y][x])
                if b > bright_threshold:
                    violations.append({'x': x, 'y': y, 'brightness': b,
                                       'dist': round(dist, 1)})

    ok = len(violations) == 0
    return {
        'pass':       ok,
        'violations': len(violations),
        'sample':     violations[:5],
        'reason': '' if ok else
            f'{len(violations)} bright pixel(s) in boundary band (r={inner_r}-{outer_r}) — '
            f'possible UI overflow outside circular display',
    }


def check_scroll(before_path, after_path, min_diff_frac=0.005):
    """Verify that two screenshots differ inside the display circle.
    A non-zero diff means the DOWN key actually scrolled content."""
    w1, h1, rows1 = read_png(before_path)
    w2, h2, rows2 = read_png(after_path)

    if (w1, h1) != (w2, h2):
        return {'pass': True, 'diff_fraction': 1.0,
                'reason': 'Images have different sizes — assumed different'}

    inside = diff_px = 0
    for y in range(h1):
        for x in range(w1):
            if (x-CX)**2 + (y-CY)**2 <= DR*DR:
                inside += 1
                r1,g1,b1 = rows1[y][x]
                r2,g2,b2 = rows2[y][x]
                if abs(r1-r2) + abs(g1-g2) + abs(b1-b2) > 20:
                    diff_px += 1

    frac = diff_px / inside if inside else 0
    ok   = frac >= min_diff_frac
    return {
        'pass':          ok,
        'diff_pixels':   diff_px,
        'total_pixels':  inside,
        'diff_fraction': round(frac, 4),
        'reason': '' if ok else
            'Screenshots are identical — scroll may not have changed content',
    }


# ── main ──────────────────────────────────────────────────────────────────────

def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__); sys.exit(1)

    cmd = args[0]
    try:
        if cmd == 'content' and len(args) >= 2:
            result = check_content(args[1])
        elif cmd == 'overflow' and len(args) >= 2:
            result = check_overflow(args[1])
        elif cmd == 'scroll' and len(args) >= 3:
            result = check_scroll(args[1], args[2])
        else:
            print(__doc__); sys.exit(1)
    except Exception as e:
        result = {'pass': False, 'reason': f'Error: {e}'}

    print(json.dumps(result))
    sys.exit(0 if result['pass'] else 1)


if __name__ == '__main__':
    main()
