#!/usr/bin/env python3
"""Draws the Blaze Raw app icon (1024x1024 PNG, no transparency - the App Store requires that).

Usage: python3 scripts/make_icon.py
Needs: pip install pillow
"""
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 1024
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "App", "BlazeRaw",
                   "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def main():
    # Background: deep purple at the top fading to near-black at the bottom.
    img = Image.new("RGB", (SIZE, SIZE))
    d = ImageDraw.Draw(img)
    top, bottom = (58, 16, 84), (10, 6, 22)
    for y in range(SIZE):
        d.line([(0, y), (SIZE, y)], fill=lerp(top, bottom, y / (SIZE - 1)))

    # A soft warm glow behind the bars, added on top of the background.
    glow = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    ImageDraw.Draw(glow).ellipse((170, 300, SIZE - 170, SIZE - 220), fill=(110, 28, 66))
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    img = ImageChops.add(img, glow)

    # A row of rounded "sound wave" bars, orange to pink, tall in the middle like a waveform.
    d = ImageDraw.Draw(img)
    bars, bar_w, gap = 13, 46, 22
    total = bars * bar_w + (bars - 1) * gap
    x0 = (SIZE - total) // 2
    cy = SIZE // 2 + 10
    for i in range(bars):
        t = i / (bars - 1)
        envelope = math.sin(math.pi * t) ** 1.4
        ripple = 0.75 + 0.25 * math.sin(i * 1.7)
        h = 90 + 560 * envelope * ripple
        x = x0 + i * (bar_w + gap)
        d.rounded_rectangle((x, cy - h / 2, x + bar_w, cy + h / 2), radius=bar_w // 2,
                            fill=lerp((255, 158, 28), (255, 46, 99), t))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.convert("RGB").save(OUT, "PNG")
    print("wrote", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
