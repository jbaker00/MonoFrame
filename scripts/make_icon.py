#!/usr/bin/env python3
"""Generate the MonoFrame icon: 1-bit dithered moonlit mountains in a frame."""
import math
from PIL import Image, ImageDraw

SIZE = 1024
FRAME = 88          # black frame border
MATTE = 26          # white matte between frame and picture
INNER = SIZE - 2 * (FRAME + MATTE)
LOWRES = 120        # scene resolution before dithering (chunky pixels)

# --- 1. draw the scene in grayscale at low res ---
s = LOWRES
scene = Image.new("L", (s, s))
px = scene.load()

def clamp(v): return max(0, min(255, int(v)))

moon_x, moon_y, moon_r = s * 0.30, s * 0.24, s * 0.13
crater_offset = moon_r * 0.42   # crescent: dark disk offset toward upper-right

def ridge1(x):  # far ridge
    return s * (0.58 + 0.07 * math.sin(x * 0.08 + 2.4) + 0.03 * math.sin(x * 0.21 + 0.7))

def ridge2(x):  # near ridge, jagged peaks
    base = s * (0.76 + 0.08 * math.sin(x * 0.055 + 5.1))
    jag = s * 0.045 * abs(math.sin(x * 0.35))
    return base - jag

for y in range(s):
    for x in range(s):
        # night sky: dark at the top, brightening toward the horizon so the
        # mountain silhouettes read after dithering
        v = 55 + (y / s) * 165
        # sparse stars
        if (x * 7 + y * 13) % 97 == 0 and y < ridge1(x) - 3:
            v = 255
        # moon: bright disk with crescent shadow
        d = math.hypot(x - moon_x, y - moon_y)
        ds = math.hypot(x - (moon_x + crater_offset), y - (moon_y - crater_offset * 0.4))
        if d < moon_r:
            v = 250 if ds > moon_r * 0.95 else 55
        elif d < moon_r + 1.8:
            v = 255   # crisp rim
        else:
            v += 70 * math.exp(-((d - moon_r) / (s * 0.09)) ** 2)
        # ridges: far = mid gray speckle, near = nearly solid, with snow caps
        if y > ridge2(x):
            v = 5
        elif y > ridge1(x):
            v = 60
        px[x, y] = clamp(v)

# lake at the bottom with moonlight track
water_top = int(s * 0.88)
for y in range(water_top, s):
    for x in range(s):
        v = 20
        if (y - water_top) % 3 == 1:
            v = 130
        if abs(x - moon_x) < s * 0.08 and (x + y) % 3 < 2:
            v = 255   # broken moon reflection track
        px[x, y] = clamp(v)

# --- 2. Floyd-Steinberg dither to 1-bit, upscale with hard pixels ---
dithered = scene.convert("1")  # PIL uses FS dithering by default
art = dithered.convert("L").resize((INNER, INNER), Image.NEAREST)

# --- 3. map to warm e-paper palette ---
PAPER = (244, 241, 232)
INK = (24, 23, 22)
art_rgb = Image.new("RGB", art.size)
ap = art.load(); rp = art_rgb.load()
for y in range(art.size[1]):
    for x in range(art.size[0]):
        rp[x, y] = PAPER if ap[x, y] > 127 else INK

# --- 4. compose: black frame, matte, picture ---
icon = Image.new("RGB", (SIZE, SIZE), INK)
draw = ImageDraw.Draw(icon)
draw.rectangle([FRAME, FRAME, SIZE - FRAME - 1, SIZE - FRAME - 1], fill=PAPER)
gap = FRAME + MATTE - 8
draw.rectangle([gap, gap, SIZE - gap - 1, SIZE - gap - 1], outline=(120, 116, 108), width=2)
icon.paste(art_rgb, (FRAME + MATTE, FRAME + MATTE))

out = "Sources/MonoFrame/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png"
icon.save(out)
print("saved", out)
