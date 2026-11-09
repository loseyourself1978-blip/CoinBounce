#!/usr/bin/env python3
"""App Store screenshots (v11.7): caption band on top, the game screenshot below it scaled down whole
(no cropping, no retouching), gold frame. Output: exactly 1320×2868 RGB PNG (no alpha) + a contact sheet.

usage: compose.py <candidates dir> <out dir> [set.json]   (frame choices: PICKS below, or the set file)
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1320, 2868
BAND = 600            # caption band height
MARGIN_BOTTOM = 70
FRAME = 8             # gold frame around the game image
FONT_EN = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"
FONT_ZH = ("/System/Library/Fonts/Hiragino Sans GB.ttc", 1)   # W6

CAPTIONS = {
    "en": ["Push the pile,\ncatch the cascade", "Thread the BONUS gate\nto spin", "Watch the coins pour\nover the edge",
           "Light all seven,\npick your reward", "Knock out the BOSS\nfor bonus coins"],
    "zh": ["推平金币堆\n接住金币雨", "穿过 BONUS\n转动滚轴", "看金币哗哗落下", "点亮七果\n翻卡领奖", "击倒 BOSS\n赢额外金币"],
}
# candidate frames chosen by eye from the capture runs (capture.sh): scene → file stem
PICKS = {
    "en": ["s1_en_13", "s2_en_35", "s3_en_13", "s4_en_06", "s5_en_05"],
    "zh": ["s1_zh-Hans_35", "s2_zh-Hans_35", "s3_zh-Hans_09", "s4_zh-Hans_06", "s5_zh-Hans_01"],
}

def background():
    bg = Image.new("RGB", (W, H))
    top, bottom = (150, 22, 92), (32, 6, 22)          # game's magenta → dark plum
    d = ImageDraw.Draw(bg)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    # soft light behind the caption
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse([-200, -350, W + 200, BAND + 150], fill=110)
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    bg = Image.composite(Image.new("RGB", (W, H), (255, 190, 80)), bg, glow.point(lambda v: v // 3))
    return bg

def font(lang, size):
    if lang == "zh":
        return ImageFont.truetype(FONT_ZH[0], size, index=FONT_ZH[1])
    return ImageFont.truetype(FONT_EN, size)

def caption(img, text, lang):
    d = ImageDraw.Draw(img)
    size = 118 if lang == "zh" else 104
    while True:
        f = font(lang, size)
        box = d.multiline_textbbox((0, 0), text, font=f, spacing=size * 0.28, align="center")
        if box[2] - box[0] <= W - 140 or size < 60:
            break
        size -= 4
    tw, th = box[2] - box[0], box[3] - box[1]
    x, y = (W - tw) / 2 - box[0], (BAND - th) / 2 - box[1] + 30
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).multiline_text((x, y + 8), text, font=f, fill=(40, 0, 20, 200), spacing=size * 0.28, align="center")
    img.paste(Image.alpha_composite(img.convert("RGBA"), shadow.filter(ImageFilter.GaussianBlur(6))).convert("RGB"))
    d = ImageDraw.Draw(img)
    d.multiline_text((x, y), text, font=f, fill=(255, 236, 160), spacing=size * 0.28, align="center",
                     stroke_width=5, stroke_fill=(120, 40, 0))

def compose(src, text, lang):
    shot = Image.open(src).convert("RGB")
    assert shot.size == (W, H), (src, shot.size)
    gh = H - BAND - MARGIN_BOTTOM - 2 * FRAME
    gw = round(gh * W / H)
    game = shot.resize((gw, gh), Image.LANCZOS)
    out = background()
    gx, gy = (W - gw) // 2, BAND
    ImageDraw.Draw(out).rounded_rectangle([gx - FRAME, gy - FRAME, gx + gw + FRAME - 1, gy + gh + FRAME - 1], radius=18, fill=(232, 178, 64))
    out.paste(game, (gx, gy))
    caption(out, text, lang)
    assert out.size == (W, H) and out.mode == "RGB"
    return out

def main(cand, out_dir):
    tiles = []
    for lang in ("en", "zh"):
        os.makedirs(os.path.join(out_dir, lang), exist_ok=True)
        for i, (stem, text) in enumerate(zip(PICKS[lang], CAPTIONS[lang]), 1):
            img = compose(os.path.join(cand, stem + ".png"), text, lang)
            p = os.path.join(out_dir, lang, f"{i:02d}.png")
            img.save(p, "PNG", optimize=True)
            tiles.append(img)
    tw, th = 330, 717
    sheet = Image.new("RGB", (5 * tw + 6 * 20, 2 * th + 3 * 20), (24, 8, 18))
    for k, im in enumerate(tiles):
        sheet.paste(im.resize((tw, th), Image.LANCZOS), (20 + (k % 5) * (tw + 20), 20 + (k // 5) * (th + 20)))
    sheet.save(os.path.join(out_dir, "总览.png"))

if __name__ == "__main__":
    # optional 3rd argument: a JSON file {"captions": {"en": [...5], "zh": [...5]}, "picks": {"en": [...5], "zh": [...5]}}
    # for another set (for example a Custom Product Page); without it the main store set above is made
    if len(sys.argv) > 3:
        import json
        cfg = json.load(open(sys.argv[3], encoding="utf-8"))
        CAPTIONS.update(cfg["captions"]); PICKS.update(cfg["picks"])
    main(sys.argv[1], sys.argv[2])
