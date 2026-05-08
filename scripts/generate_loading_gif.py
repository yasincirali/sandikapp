#!/usr/bin/env python3
"""Generate a loading GIF based on the PortfoyTakip app icon."""

import math
from PIL import Image, ImageDraw

SIZE = 200
CORNER_RADIUS = 44
NUM_FRAMES = 36
DURATION = 55  # ms per frame

# Icon colors (top to bottom layers)
COLORS = [
    (246, 200,  66),  # golden yellow  - layer 0 (top)
    (232, 149,  58),  # amber          - layer 1
    (196,  99,  42),  # dark orange    - layer 2
    (139,  46,   0),  # dark brown     - layer 3 (bottom fill)
]

BG_COLOR = COLORS[3]


def rounded_rect_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def wave_y(x, offset, amplitude, period, base_y):
    """Return y position of wave at pixel x."""
    return base_y + amplitude * math.sin(2 * math.pi * (x / period + offset))


def draw_wave_layer(draw, color, base_y, amplitude, period, offset, size):
    """Fill everything below a sine wave with the given color."""
    points = []
    for x in range(size + 1):
        y = wave_y(x, offset, amplitude, period, base_y)
        points.append((x, y))
    # close polygon at bottom
    points.append((size, size))
    points.append((0, size))
    draw.polygon(points, fill=color)


def make_frame(t):
    """t in [0,1) — animation progress."""
    # Fill background with golden yellow
    img = Image.new("RGBA", (SIZE, SIZE), COLORS[0] + (255,))
    draw = ImageDraw.Draw(img)

    # Wave layers drawn top-to-bottom (each darker layer fills below its wave)
    # (base_y_frac, amplitude, period, phase_speed, color)
    wave_layers = [
        (0.35, 20, SIZE * 0.85, 1.0,  COLORS[1]),  # amber
        (0.52, 18, SIZE * 0.80, 0.7,  COLORS[2]),  # dark orange
        (0.67, 16, SIZE * 0.75, 0.45, COLORS[3]),  # dark brown
    ]

    for base_frac, amp, period, speed, color in wave_layers:
        base_y = base_frac * SIZE
        offset = -(t * speed)
        draw_wave_layer(draw, color, base_y, amp, period, offset, SIZE)

    # Apply rounded-rect mask
    mask = rounded_rect_mask(SIZE, CORNER_RADIUS)
    result = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    result.paste(img, mask=mask)
    return result


def main():
    frames = []
    for i in range(NUM_FRAMES):
        t = i / NUM_FRAMES
        frame = make_frame(t).convert("RGBA")

        # Convert to P mode with transparency for GIF
        bg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        bg.paste(frame, mask=frame.split()[3])
        frames.append(bg.convert("RGB"))

    out_path = "/home/user/PortfoyTakip/assets/images/loading.gif"
    frames[0].save(
        out_path,
        save_all=True,
        append_images=frames[1:],
        loop=0,
        duration=DURATION,
        optimize=False,
    )
    print(f"Saved {NUM_FRAMES}-frame GIF to {out_path}")


if __name__ == "__main__":
    main()
