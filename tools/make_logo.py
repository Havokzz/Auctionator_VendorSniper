"""Draws the add-on's logo (media/logo.png): a coin pouch, coins and a gavel as 40x40 pixel art, scaled x10,
on a transparent background so it blends in wherever CurseForge shows it."""
import sys

import numpy as np
from PIL import Image

OUT = sys.argv[1] if len(sys.argv) > 1 else "media/logo.png"
G = 40
EMPTY = (1, 2, 3)  # a colour the art never uses: what's left of it becomes transparent
img = np.zeros((G, G, 3), np.uint8)
img[:, :] = EMPTY


def rgb(h):
    h = h.lstrip("#")
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


LIGHT = np.array([-0.55, -0.75])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16

def draw(shape, color_of, outline):
    """shape: set of (x, y). Draws a 1px outline around it, then the shape coloured by color_of."""
    ring = set()
    for x, y in shape:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            p = (x + dx, y + dy)
            if p not in shape:
                ring.add(p)
    for x, y in ring:
        if 0 <= x < G and 0 <= y < G:
            img[y, x] = rgb(outline)
    for x, y in shape:
        if 0 <= x < G and 0 <= y < G:
            img[y, x] = rgb(color_of(x, y))


def sphere_tone(x, y, cx, cy, rx, ry, tones, bias=0.0):
    nx, ny = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
    nz = np.sqrt(max(0.0, 1 - nx * nx - ny * ny))
    b = nx * LIGHT[0] + ny * LIGHT[1] + nz * 0.55 + bias
    edges = [-0.05, 0.35, 0.75, 1.05]
    i = sum(b > e for e in edges)
    return tones[min(i, len(tones) - 1)]


# --- pouch ---------------------------------------------------------------------------------------
LEATHER = ["#4a2312", "#6e3a1d", "#995429", "#c27a3e", "#e3a868"]
LEATHER_OUT = "#1c0c06"
CX, CY, RX, RY = 19.0, 23.5, 10.5, 9.5
body = {(x, y) for x in range(G) for y in range(G) if ((x + 0.5 - CX) / RX) ** 2 + ((y + 0.5 - CY) / RY) ** 2 <= 1}
neck = {(x, y) for y in range(12, 16) for x in range(15 - (y - 12) // 2, 24 + (y - 12) // 2)}
draw(body | neck, lambda x, y: sphere_tone(x, y, CX, CY, RX, RY, LEATHER), LEATHER_OUT)
# light bounced back from the ground along the lower right edge, for roundness
for x, y in body:
    edge = any(p not in body for p in ((x + 1, y), (x, y + 1), (x + 1, y + 1)))
    nx, ny = (x + 0.5 - CX) / RX, (y + 0.5 - CY) / RY
    if edge and nx * 0.45 + ny * 0.9 > 0.55:
        img[y, x] = rgb(LEATHER[2])
# a small shine where the light hits
for x, y in ((13, 18), (14, 18), (12, 19), (13, 19)):
    img[y, x] = rgb("#f4cf98")
# folds running down from the tie
for x, y in ((22, 16), (23, 17), (23, 18), (24, 19), (24, 20)):
    img[y, x] = rgb(LEATHER[0])
# stitched seam round the bottom
for x in range(11, 28, 2):
    y = int(round(CY + RY * 0.6 * np.sqrt(max(0, 1 - ((x + 0.5 - CX) / (RX * 0.8)) ** 2))))
    img[y, x] = rgb("#ecc98f")

# ruffled top above the tie
top = set()
for y, half in ((7, 5), (8, 6), (9, 5), (10, 5), (11, 4)):
    for x in range(19 - half, 20 + half):
        top.add((x, y))
draw(top, lambda x, y: (LEATHER[4] if y == 7 and x < 21 else LEATHER[3]) if x < 17 or (y == 7 and x < 21)
     else (LEATHER[2] if x < 22 else LEATHER[1]), LEATHER_OUT)
for x in range(14, 25):
    img[8, x] = rgb("#1c0c06")  # the opening
for x, c in ((16, "#e0aa2c"), (17, "#fff0a8"), (18, "#f2cf5a"), (20, "#f2cf5a"), (21, "#e0aa2c")):
    img[8, x] = rgb(c)  # gold inside

# twine tie and its loose end
TWINE = ["#7d6130", "#d2b375"]
for x in range(14, 25):
    for y in (12, 13):
        img[y, x] = rgb(TWINE[(x + y) % 2])
    img[14, x] = rgb("#2a1c0a")
for x, y in ((23, 14), (24, 15), (24, 16), (23, 17)):
    img[y, x] = rgb(TWINE[1])

# --- gavel at the right: head across the pouch's shoulder, handle down to the corner -------------
WOOD = ["#2a1007", "#4c2210", "#743a1c", "#a4602f"]
WOOD_OUT = "#0e0503"
BRASS = ["#7a5414", "#d6a840", "#fae39a"]
HX, HY = 28.0, 20.0
handle = set()
for t in range(2, 11):
    handle |= {(int(HX) + t, int(HY) + t), (int(HX) + t + 1, int(HY) + t)}
draw(handle, lambda x, y: "#c07a42" if x - y == int(HX) - int(HY) else "#87461f", WOOD_OUT)
head = set()
for x in range(G):
    for y in range(G):
        u = ((x + 0.5 - HX) - (y + 0.5 - HY)) / np.sqrt(2)  # along the head ("/")
        v = ((x + 0.5 - HX) + (y + 0.5 - HY)) / np.sqrt(2)  # across it
        if abs(u) <= 5.3 and abs(v) <= 2.3:
            head.add((x, y))


def head_color(x, y):
    u = ((x + 0.5 - HX) - (y + 0.5 - HY)) / np.sqrt(2)
    v = ((x + 0.5 - HX) + (y + 0.5 - HY)) / np.sqrt(2)
    if 3.0 <= abs(u) <= 4.0:
        return BRASS[2] if v < -0.8 else (BRASS[1] if v < 1 else BRASS[0])
    return WOOD[3] if v < -0.7 else (WOOD[2] if v < 0.4 else (WOOD[1] if v < 1.3 else WOOD[0]))


draw(head, head_color, WOOD_OUT)

# --- coins at the front left ---------------------------------------------------------------------
GOLD_OUT = "#2e1a03"
GOLD_SIDE = ["#7a4a08", "#a8721a"]
GOLD_TOP = ["#d49a22", "#f0c440", "#fde07e", "#fff8d6"]


def coin(cx, cy):
    """A flat coin: an ellipse top 9 wide with a 2px edge below it."""
    topf = {(x, y) for x in range(G) for y in range(G)
            if ((x + 0.5 - cx) / 4.6) ** 2 + ((y + 0.5 - cy) / 2.1) ** 2 <= 1}
    side = {(x, y + d) for x, y in topf for d in (1, 2)} - topf

    def color(x, y):
        if (x, y) in side:
            return GOLD_SIDE[1] if x < cx - 1 else GOLD_SIDE[0]
        if y < cy - 0.5:
            return GOLD_TOP[2] if x < cx else GOLD_TOP[1]
        return GOLD_TOP[0]
    draw(topf | side, color, GOLD_OUT)
    for x, y in topf:
        if (x - 1, y) not in topf or (x + 1, y) not in topf or (x, y - 1) not in topf:
            img[y, x] = rgb(GOLD_TOP[0] if x > cx else GOLD_TOP[1])  # rim
    img[int(cy) - 1, int(cx) - 2] = rgb(GOLD_TOP[3])


def round_coin(sx, sy, sr, mark=True):
    """A coin standing on its edge, seen face on."""
    face = {(x, y) for x in range(G) for y in range(G) if (x + 0.5 - sx) ** 2 + (y + 0.5 - sy) ** 2 <= sr * sr}
    tones = [GOLD_SIDE[0], GOLD_TOP[0], GOLD_TOP[1], GOLD_TOP[2], GOLD_TOP[3]]
    draw(face, lambda x, y: sphere_tone(x, y, sx, sy, sr, sr, tones, 0.1), GOLD_OUT)
    for x, y in face:
        r = np.hypot(x + 0.5 - sx, y + 0.5 - sy)
        if sr - 1.9 <= r <= sr - 1.1:
            img[y, x] = rgb(GOLD_SIDE[1])  # raised rim
    if mark:
        cx, cy = int(sx), int(sy)
        for dx, dy in ((0, -2), (-1, -1), (1, -1), (0, 0), (-1, 0), (1, 0), (0, 1)):
            img[cy + dy, cx + dx] = rgb(GOLD_SIDE[1])


round_coin(17.0, 32.8, 3.8, mark=False)  # behind
round_coin(9.0, 25.0, 5.2)               # leaning on the pouch
round_coin(9.5, 32.3, 4.3, mark=False)   # in front
for x, y, c in ((5, 18, "#fff8d6"), (5, 17, "#fde07e"), (5, 19, "#fde07e"), (4, 18, "#fde07e"), (6, 18, "#fde07e")):
    img[y, x] = rgb(c)

# --- transparent background, the art centred -----------------------------------------------------
alpha = np.any(img != EMPTY, axis=2)
ys, xs = np.nonzero(alpha)
out = np.zeros((G, G, 4), np.uint8)
dx = (G - (xs.max() - xs.min() + 1)) // 2 - xs.min()
dy = (G - (ys.max() - ys.min() + 1)) // 2 - ys.min()
out[ys + dy, xs + dx, :3] = img[ys, xs]
out[ys + dy, xs + dx, 3] = 255
img = out

Image.fromarray(img, "RGBA").resize((400, 400), Image.NEAREST).save(OUT)
print("saved", OUT)
