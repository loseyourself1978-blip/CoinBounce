#!/usr/bin/env python3
"""iOS 27 creative assets: header 21:9 (3840x1646) and search results 3:2 (3840x2560).
RGB, no alpha. Machine render centered, short phrase above it. usage: compose_creative.py machine.png out_root"""
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
FONT_EN = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"
FONT_ZH = ("/System/Library/Fonts/Hiragino Sans GB.ttc", 1)
PHRASE = {"en": "Satisfying 3D coin physics", "zh": "爽快 3D 推币，金币哗哗落"}
SIZES = {"header_21x9": (3840, 1646), "search_3x2": (3840, 2560)}

def font(lang, size):
    return ImageFont.truetype(FONT_EN, size) if lang == "en" else ImageFont.truetype(FONT_ZH[0], size, index=FONT_ZH[1])

def background(w, h):
    top, bot = (58, 10, 70), (12, 4, 30)
    bg = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(bg)
    for y in range(h):
        t = y / (h - 1); d.line([(0, y), (w, y)], fill=tuple(int(top[i] * (1 - t) + bot[i] * t) for i in range(3)))
    glow = Image.new("L", (w, h), 0); ImageDraw.Draw(glow).ellipse([w*0.25, h*0.2, w*0.75, h*1.1], fill=110)
    glow = glow.filter(ImageFilter.GaussianBlur(h * 0.12))
    return Image.composite(Image.new("RGB", (w, h), (255, 170, 60)), bg, glow)

def machine_crop(src):
    m = Image.open(src).convert("RGBA")          # rendered with a clear background
    return m.crop(m.split()[-1].getbbox())

def compose(machine, lang, w, h):
    img = background(w, h); d = ImageDraw.Draw(img)
    text_h = int(h * 0.16)
    f = font(lang, int(text_h * 0.62))
    while d.textlength(PHRASE[lang], font=f) > w * 0.6: f = font(lang, int(f.size * 0.92))
    tw = d.textlength(PHRASE[lang], font=f); tx = (w - tw) / 2; ty = int(h * 0.05)
    d.text((tx, ty + 10), PHRASE[lang], font=f, fill=(40, 0, 20))
    d.text((tx, ty), PHRASE[lang], font=f, fill=(255, 236, 160), stroke_width=4, stroke_fill=(120, 40, 0))
    avail_h = h - (ty + text_h) - int(h * 0.04)
    s = avail_h / machine.height
    mm = machine.resize((int(machine.width * s), avail_h), Image.LANCZOS)
    mm = mm if mm.width <= w * 0.9 else mm.resize((int(w * 0.9), int(mm.height * w * 0.9 / mm.width)), Image.LANCZOS)
    mx = (w - mm.width) // 2; my = ty + text_h
    sh = Image.new("L", (w, h), 0); sh.paste(mm.split()[-1], (mx, my + 30))
    img = Image.composite(Image.new("RGB", (w, h), (0, 0, 0)), img, sh.filter(ImageFilter.GaussianBlur(30)).point(lambda v: v * 0.6))
    img.paste(mm.convert("RGB"), (mx, my), mm.split()[-1])
    return img

if __name__ == "__main__":
    machine = machine_crop(sys.argv[1]); root = sys.argv[2]
    for lang in ("en", "zh"):
        os.makedirs(f"{root}/{lang}", exist_ok=True)
        for name, (w, h) in SIZES.items():
            out = f"{root}/{lang}/{name}.png"
            im = compose(machine, lang, w, h); assert im.mode == "RGB" and im.size == (w, h)
            im.save(out, optimize=True); print(out, im.size, os.path.getsize(out))
