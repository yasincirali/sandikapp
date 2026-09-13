"""
Generates a 1024x1024 PNG for sandik_logo from scratch using only stdlib.
Matches the SVG: golden gradient rounded-rect + 3 wave layers.
"""
import struct, zlib, math

SIZE = 1024
RADIUS = int(90 / 512 * SIZE)   # proportional corner radius
PAD  = int(64 / 512 * SIZE)     # inset like the SVG clip

def lerp(a, b, t):
    return a + (b - a) * t

def hex_to_rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

TOP_COLOR    = hex_to_rgb('FCD35A')
BOT_COLOR    = hex_to_rgb('EAA12B')
WAVE1_COLOR  = hex_to_rgb('E2861F')
WAVE2_COLOR  = hex_to_rgb('C56314')
WAVE3_COLOR  = hex_to_rgb('993D0A')

def in_rounded_rect(x, y, rx, ry, rw, rh, r):
    """Returns True if pixel (x,y) is inside rounded rect."""
    if x < rx or x >= rx + rw or y < ry or y >= ry + rh:
        return False
    # corner checks
    cx, cy = None, None
    if x < rx + r and y < ry + r:
        cx, cy = rx + r, ry + r
    elif x >= rx + rw - r and y < ry + r:
        cx, cy = rx + rw - r, ry + r
    elif x < rx + r and y >= ry + rh - r:
        cx, cy = rx + r, ry + rh - r
    elif x >= rx + rw - r and y >= ry + rh - r:
        cx, cy = rx + rw - r, ry + rh - r
    if cx is not None:
        return (x - cx) ** 2 + (y - cy) ** 2 <= r * r
    return True

def wave_y(x, base_frac, amp_frac=None):
    """
    Mimics the SVG S-curve wave at a given base_y fraction.
    The SVG uses cubic bezier S-curves between x=0..512 with:
      anchors at x=0,128,256,384,512 and offset +50
    We approximate with a cosine.
    """
    base_y = base_frac * SIZE
    # amplitude = 50/512 * SIZE
    amp = 50 / 512 * SIZE
    # period = 256/512 * SIZE = SIZE/2
    period = SIZE / 2
    return base_y + amp * math.cos(2 * math.pi * x / period + math.pi)

# Build pixel array
pixels = bytearray(SIZE * SIZE * 4)

for y in range(SIZE):
    for x in range(SIZE):
        idx = (y * SIZE + x) * 4

        if not in_rounded_rect(x, y, PAD, PAD, SIZE - 2*PAD, SIZE - 2*PAD, RADIUS):
            # transparent
            pixels[idx:idx+4] = [0, 0, 0, 0]
            continue

        # gradient base
        t = (y - PAD) / (SIZE - 2*PAD)
        t = max(0.0, min(1.0, t))
        r = int(lerp(TOP_COLOR[0], BOT_COLOR[0], t))
        g = int(lerp(TOP_COLOR[1], BOT_COLOR[1], t))
        b = int(lerp(TOP_COLOR[2], BOT_COLOR[2], t))
        a = 255

        # wave layers (back to front)
        wy3 = wave_y(x, 280/512)
        wy2 = wave_y(x, 220/512)
        wy1 = wave_y(x, 160/512)

        if y >= wy3:
            r, g, b = WAVE3_COLOR
        elif y >= wy2:
            r, g, b = WAVE2_COLOR
        elif y >= wy1:
            r, g, b = WAVE1_COLOR

        pixels[idx:idx+4] = [r, g, b, a]

# Encode as PNG
def make_png(width, height, rgba_bytes):
    def adler32(data):
        return zlib.adler32(data) & 0xffffffff

    def chunk(name, data):
        c = name + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))

    raw_rows = bytearray()
    for row in range(height):
        raw_rows += b'\x00'  # filter type None
        raw_rows += rgba_bytes[row*width*4:(row+1)*width*4]

    compressed = zlib.compress(bytes(raw_rows), 9)
    idat = chunk(b'IDAT', compressed)
    iend = chunk(b'IEND', b'')
    return sig + ihdr + idat + iend

png_data = make_png(SIZE, SIZE, pixels)

out_path = r'c:\projects\PortfoyTakip\assets\images\sandik_icon.png'
with open(out_path, 'wb') as f:
    f.write(png_data)

print(f'Written {len(png_data)} bytes -> {out_path}')
