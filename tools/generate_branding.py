#!/usr/bin/env python3
"""Generates FitArcade's launch branding from the app's own design tokens.

Outputs (project/branding/):
  splash.png               Godot boot splash: stripes + "FITARCADE" wordmark (onboarding style)
  icon.png                 Project icon (512)
  launcher_main_192.png    Android legacy launcher icon; also what Android 12+ shows on its own splash
  launcher_fg_432.png      Android adaptive icon foreground (transparent, inside the safe zone)
  launcher_bg_432.png      Android adaptive icon background (ink + faint stripes)
  launcher_mono_432.png    Android 13+ themed-icon silhouette
  splash_blank.png         Fully transparent. Android 12+ always draws an icon on its own system splash and
                           would otherwise scale the 192px launcher icon up ~5x (blurry). A transparent icon on
                           the dark splash background means that first screen is just a blank dark frame that
                           hands off seamlessly to splash.png, so there is a single visible splash.

Run from the repo root:   python tools/generate_branding.py
Needs Pillow. Uses project/fonts/Anton/Anton-Regular.ttf, the app's display font.
Colors and the diagonal stripe texture match project/ui/Tokens.gd and the onboarding screen.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "project" / "fonts" / "Anton" / "Anton-Regular.ttf"
OUT = ROOT / "project" / "branding"

INK = (0x0B, 0x0B, 0x0C, 255)
VOLT = (0xD4, 0xFF, 0x3A, 255)
WHITE = (255, 255, 255, 255)
LINE = (0x2A, 0x2A, 0x2E, 255)

SS = 4                      # supersampling factor for smooth edges
CAP = 0.87                  # Anton's cap height as a fraction of the font size (measured in the app)


def font(px):
    return ImageFont.truetype(str(FONT), int(round(px)))


def stripes(img, scale):
    """The app's backdrop texture: -45deg lines, 12px pitch, 2px wide, white@0.03 (at a 390px base)."""
    w, h = img.size
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    pitch, width = 12 * scale, max(1, round(2 * scale))
    x = -h
    while x < w + h:
        d.line([(x, h), (x + h, 0)], fill=(255, 255, 255, round(255 * 0.03)), width=width)
        x += pitch
    img.alpha_composite(layer)


def text_width(text, f):
    return f.getlength(text)


def draw_text_centered_baseline(d, cx, baseline, text, f, fill):
    d.text((cx, baseline), text, font=f, fill=fill, anchor="ms")


# ---------------------------------------------------------------------------------------
# Splash: stripes + [line  FITARCADE  line], like the app's Wordmark component
# ---------------------------------------------------------------------------------------
def make_splash(w=1080, h=2340):
    s = w / 390.0                           # design units are the app's 390px-wide layout
    img = Image.new("RGBA", (w * SS, h * SS), INK)
    stripes(img, s * SS)
    d = ImageDraw.Draw(img)

    size = 54 * s * SS
    f = font(size)
    fit_w, arcade_w = text_width("FIT", f), text_width("ARCADE", f)
    total = fit_w + arcade_w
    cx, cy = w * SS / 2, h * SS / 2
    left = cx - total / 2
    baseline = cy + size * CAP / 2
    d.text((left, baseline), "FIT", font=f, fill=WHITE, anchor="ls")
    d.text((left + fit_w, baseline), "ARCADE", font=f, fill=VOLT, anchor="ls")

    # hairlines either side, 20px screen padding and 12px from the word (as in Wordmark.gd)
    gap, pad, thick = 14 * s * SS, 20 * s * SS, max(1, round(1 * s * SS))
    ly = cy
    d.rectangle([pad, ly - thick / 2, left - gap, ly + thick / 2], fill=LINE)
    d.rectangle([left + total + gap, ly - thick / 2, w * SS - pad, ly + thick / 2], fill=LINE)
    return img.resize((w, h), Image.LANCZOS)


# ---------------------------------------------------------------------------------------
# Icon: stacked FIT / ARCADE. Laid out in a 432-unit square (Android's adaptive-icon canvas)
# ---------------------------------------------------------------------------------------
def draw_stack(d, canvas, scale, fit_fill, arcade_fill, ss=SS):
    """`scale` multiplies the layout (1.0 keeps it inside the 288-unit adaptive safe circle)."""
    u = canvas / 432.0 * scale * ss
    arcade_px, fit_px = 78 * u, 104 * u
    fa, ff = font(arcade_px), font(fit_px)
    gap = 12 * u
    fit_cap, arcade_cap = fit_px * CAP, arcade_px * CAP
    block = fit_cap + gap + arcade_cap
    cx, top = canvas * ss / 2, canvas * ss / 2 - block / 2
    d.text((cx, top + fit_cap), "FIT", font=ff, fill=fit_fill, anchor="ms")
    d.text((cx, top + fit_cap + gap + arcade_cap), "ARCADE", font=fa, fill=arcade_fill, anchor="ms")


def square_icon(size, radius_frac, scale):
    img = Image.new("RGBA", (size * SS, size * SS), INK)
    stripes(img, size / 432.0 * 1.6 * SS)
    d = ImageDraw.Draw(img)
    draw_stack(d, size, scale, WHITE, VOLT)
    img = img.resize((size, size), Image.LANCZOS)
    if radius_frac > 0:
        mask = Image.new("L", (size * SS, size * SS), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, size * SS - 1, size * SS - 1], radius=size * SS * radius_frac, fill=255)
        mask = mask.resize((size, size), Image.LANCZOS)
        out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        out.paste(img, (0, 0), mask)
        return out
    return img


def adaptive_foreground(size=432, mono=False):
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if mono:
        draw_stack(d, size, 1.0, WHITE, WHITE)
    else:
        draw_stack(d, size, 1.0, WHITE, VOLT)
    return img.resize((size, size), Image.LANCZOS)


def adaptive_background(size=432):
    img = Image.new("RGBA", (size * SS, size * SS), INK)
    stripes(img, size / 432.0 * 1.6 * SS)
    return img.resize((size, size), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    make_splash().convert("RGB").save(OUT / "splash.png", optimize=True)
    # Legacy/project icons are full-bleed squares, so the wordmark can be larger than the adaptive safe zone
    square_icon(512, 0.22, 1.32).save(OUT / "icon.png", optimize=True)
    square_icon(192, 0.22, 1.32).save(OUT / "launcher_main_192.png", optimize=True)
    adaptive_foreground().save(OUT / "launcher_fg_432.png", optimize=True)
    adaptive_background().convert("RGB").save(OUT / "launcher_bg_432.png", optimize=True)
    adaptive_foreground(mono=True).save(OUT / "launcher_mono_432.png", optimize=True)
    Image.new("RGBA", (288, 288), (0, 0, 0, 0)).save(OUT / "splash_blank.png", optimize=True)
    print("wrote", ", ".join(sorted(p.name for p in OUT.glob("*.png"))))


if __name__ == "__main__":
    main()
