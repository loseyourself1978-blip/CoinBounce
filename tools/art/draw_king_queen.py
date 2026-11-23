#!/usr/bin/env python3
"""CoinBounce v12 king / queen / boss art. Original vector drawings, rendered to PNG."""
import sys, os
OL = "#2E141A"
SW = 11

DEFS = '''
<defs>
 <radialGradient id="skin" cx="38%" cy="30%" r="80%"><stop offset="0" stop-color="#FFF0E4"/><stop offset=".6" stop-color="#FCD3B8"/><stop offset="1" stop-color="#EFB08E"/></radialGradient>
 <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFF7B8"/><stop offset=".45" stop-color="#FFCC33"/><stop offset="1" stop-color="#D4820C"/></linearGradient>
 <linearGradient id="goldband" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFD24A"/><stop offset="1" stop-color="#B96C06"/></linearGradient>
 <linearGradient id="red" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FF6B66"/><stop offset=".5" stop-color="#DA2038"/><stop offset="1" stop-color="#8A0E24"/></linearGradient>
 <linearGradient id="redin" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#B3142C"/><stop offset="1" stop-color="#6A0A1C"/></linearGradient>
 <linearGradient id="teal" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#55E6D6"/><stop offset=".5" stop-color="#19B8AA"/><stop offset="1" stop-color="#0A6C70"/></linearGradient>
 <linearGradient id="hairK" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#A9713A"/><stop offset=".6" stop-color="#7A4A22"/><stop offset="1" stop-color="#522E12"/></linearGradient>
 <linearGradient id="hairQ" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFF3B5"/><stop offset=".5" stop-color="#FFD65E"/><stop offset="1" stop-color="#E2962A"/></linearGradient>
 <linearGradient id="hairQd" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F7C54E"/><stop offset="1" stop-color="#C97A1C"/></linearGradient>
 <linearGradient id="gown" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFA9CC"/><stop offset=".55" stop-color="#F0609C"/><stop offset="1" stop-color="#B42A6A"/></linearGradient>
 <linearGradient id="gownlight" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFE9F2"/><stop offset="1" stop-color="#FFB7D4"/></linearGradient>
 <linearGradient id="bodice" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F0469A"/><stop offset="1" stop-color="#8E155C"/></linearGradient>
 <linearGradient id="white" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E3DDEE"/></linearGradient>
 <linearGradient id="steel" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#FFFFFF"/><stop offset=".5" stop-color="#C9D4E6"/><stop offset="1" stop-color="#7B88A0"/></linearGradient>
 <linearGradient id="boot" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#96623C"/><stop offset="1" stop-color="#4C2A18"/></linearGradient>
 <linearGradient id="irisK" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3A1C0E"/><stop offset=".55" stop-color="#8A4A1C"/><stop offset="1" stop-color="#E9A040"/></linearGradient>
 <linearGradient id="irisQ" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0C2A4A"/><stop offset=".55" stop-color="#1C78B8"/><stop offset="1" stop-color="#6FE0F0"/></linearGradient>
 <linearGradient id="tear" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#E6F8FF"/><stop offset="1" stop-color="#7CCBF7"/></linearGradient>
 <radialGradient id="bskin" cx="36%" cy="28%" r="85%"><stop offset="0" stop-color="#FFA6E4"/><stop offset=".55" stop-color="#EE4BB4"/><stop offset="1" stop-color="#B41C84"/></radialGradient>
 <linearGradient id="bskind" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#D836A0"/><stop offset="1" stop-color="#8E1468"/></linearGradient>
 <linearGradient id="iron" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#A9B1CC"/><stop offset=".5" stop-color="#666D8A"/><stop offset="1" stop-color="#3C405A"/></linearGradient>
 <radialGradient id="ironball" cx="34%" cy="28%" r="80%"><stop offset="0" stop-color="#C9D0E6"/><stop offset=".5" stop-color="#6A7190"/><stop offset="1" stop-color="#34384E"/></radialGradient>
 <linearGradient id="bcape" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#A66BF0"/><stop offset=".5" stop-color="#6B34C0"/><stop offset="1" stop-color="#3A1678"/></linearGradient>
 <linearGradient id="bhair" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#7E48D8"/><stop offset="1" stop-color="#3A1678"/></linearGradient>
 <linearGradient id="irisB" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#6A0A12"/><stop offset=".5" stop-color="#F0481C"/><stop offset="1" stop-color="#FFE04A"/></linearGradient>
</defs>'''

def P(d, fill, sw=SW, stroke=OL, extra=""):
    return f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="round" {extra}/>'
def L(d, sw=SW, stroke=OL, extra=""):
    return f'<path d="{d}" fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="round" {extra}/>'
def E(cx, cy, rx, ry, fill, sw=SW, stroke=OL, extra=""):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" {extra}/>'
def N(cx, cy, rx, ry, fill, extra=""):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{fill}" {extra}/>'

# ---------- face features (head-local units: radius 100, facing right) ----------
def eye_open(x, y, rx, ry, iris, lash=False, sparkle=False, hs=5):
    s = E(x, y, rx, ry, f"url(#{iris})", sw=hs)
    s += N(x, y - ry * 0.18, rx * 0.5, ry * 0.42, "#1A0A08")
    s += N(x - rx * 0.38, y - ry * 0.48, rx * 0.36, ry * 0.26, "#FFFFFF")
    s += N(x + rx * 0.35, y + ry * 0.45, rx * 0.2, ry * 0.14, "#FFFFFF", 'opacity=".9"')
    if sparkle:
        s += N(x + rx * 0.3, y - ry * 0.25, rx * 0.2, ry * 0.14, "#FFFFFF")
    s += L(f"M {x-rx-2},{y-ry*0.45} Q {x},{y-ry*1.35} {x+rx+2},{y-ry*0.45}", sw=hs + 2.5)
    if lash:
        s += L(f"M {x-rx-1},{y-ry*0.5} l -8,-7 M {x-rx+2},{y-ry*0.8} l -5,-9", sw=hs - 1)
    return s
def eye_arc_up(x, y, w, hs=6.5):      # ^ happy closed
    return L(f"M {x-w},{y+5} Q {x},{y-w*1.1} {x+w},{y+5}", sw=hs)
def eye_arc_down(x, y, w, hs=6.5, lash=False):  # closed, lashes down
    s = L(f"M {x-w},{y-3} Q {x},{y+w*0.85} {x+w},{y-3}", sw=hs)
    if lash:
        s += L(f"M {x-w},{y-3} l -8,3 M {x-w*0.55},{y+w*0.3} l -6,7", sw=hs - 2)
    return s
def eye_squint(x, y, w, hs=6.5):      # > shape
    return L(f"M {x-w},{y-w*0.7} L {x+w*0.6},{y} L {x-w},{y+w*0.7}", sw=hs)
def blush(x, y, rx=15, ry=9, op=.5):
    return N(x, y, rx, ry, "#FF6F8E", f'opacity="{op}"')

def crown(hs):
    g = '<g transform="translate(6,6) rotate(-7 0 -85)">'
    g += E(0, -112, 54, 36, "url(#redin)", sw=hs)
    g += P("M -66,-70 L -78,-142 L -42,-108 L -24,-156 L 0,-112 L 24,-156 L 42,-108 L 78,-142 L 66,-70 Q 0,-54 -66,-70 Z", "url(#gold)", sw=hs)
    g += P("M -66,-70 Q 0,-54 66,-70 L 69,-93 Q 0,-77 -69,-93 Z", "url(#goldband)", sw=hs)
    for x, y in ((-78, -142), (-24, -156), (24, -156), (78, -142)):
        g += E(x, y, 9, 9, "#FFF2A0", sw=hs * .8)
    g += E(0, -72, 10, 10, "#FF3B5C", sw=hs * .7) + N(-3, -75, 3, 3, "#FFFFFF", 'opacity=".9"')
    g += E(-38, -78, 7, 7, "#3FE0D0", sw=hs * .7) + E(38, -78, 7, 7, "#3FE0D0", sw=hs * .7)
    g += L("M -58,-98 L -64,-128", sw=4, stroke="#FFFFFF", extra='opacity=".7"')
    return g + '</g>'

def tiara(hs):
    g = '<g transform="translate(8,4) rotate(-6 0 -85)">'
    g += P("M -48,-80 L -56,-116 L -28,-98 L 0,-142 L 28,-98 L 56,-116 L 48,-80 Q 0,-66 -48,-80 Z", "url(#gold)", sw=hs)
    g += E(-56, -116, 7, 7, "#FFF2A0", sw=hs * .8) + E(56, -116, 7, 7, "#FFF2A0", sw=hs * .8)
    g += E(0, -142, 8, 8, "#FFF2A0", sw=hs * .8)
    # heart gem
    g += P("M 0,-84 C -16,-98 -18,-112 -8,-114 C -3,-115 0,-110 0,-108 C 0,-110 3,-115 8,-114 C 18,-112 16,-98 0,-84 Z", "#FF3F7F", sw=hs * .7)
    g += N(-6, -108, 3, 2.4, "#FFFFFF", 'opacity=".9"')
    return g + '</g>'

def head_king(cx, cy, R, expr, tilt=0):
    hs = SW * 100 / R
    g = f'<g transform="translate({cx},{cy}) rotate({tilt}) scale({R/100})">'
    g += E(-6, -8, 106, 104, "url(#hairK)", sw=hs)
    g += P("M -98,6 C -124,36 -116,80 -82,88 C -92,62 -88,40 -80,18 Z", "url(#hairK)", sw=hs)
    g += E(-91, 18, 15, 19, "url(#skin)", sw=hs)
    g += E(0, 0, 100, 95, "url(#skin)", sw=hs)
    # features
    if expr == "idle":
        g += blush(-44, 46, op=.4) + blush(72, 44, 12, 8, op=.4)
        g += eye_open(-24, 16, 14, 20, "irisK") + eye_open(56, 16, 12, 19, "irisK")
        g += L("M -46,-17 L -8,-10", sw=7.5) + L("M 40,-10 L 73,-17", sw=7.5)
        g += L("M 4,51 Q 21,64 39,49", sw=5.5)
    elif expr == "attack":
        g += blush(-44, 46, op=.35) + blush(72, 44, 12, 8, op=.35)
        g += eye_open(-24, 18, 14, 17, "irisK") + eye_open(56, 18, 12, 16, "irisK")
        g += L("M -48,-22 L -6,-4", sw=8.5) + L("M 38,-4 L 75,-21", sw=8.5)
        g += P("M 0,46 Q 21,38 42,46 Q 40,78 21,78 Q 2,78 0,46 Z", "#7A1020", sw=5)
        g += P("M 6,47 Q 21,42 36,47 L 35,54 Q 21,50 7,54 Z", "#FFFFFF", sw=0)
        g += N(21, 70, 11, 6, "#FF7A8A")
    elif expr == "kiss":
        g += blush(-54, 46, 20, 12, op=.7) + blush(62, 46, 16, 11, op=.7)
        g += L("M -62,40 l 6,10 M -52,38 l 6,10 M -42,40 l 6,10", sw=3, stroke="#E0486A")
        g += eye_open(-34, 14, 15, 22, "irisK", sparkle=True) + eye_squint(44, 16, 12)
        g += L("M -56,-26 Q -38,-34 -18,-26", sw=7) + L("M 28,-16 Q 44,-24 60,-14", sw=7)
        g += L("M -8,54 Q 0,46 8,54 Q 16,62 25,52", sw=5.5)
    elif expr == "victory":
        g += blush(-44, 46, op=.5) + blush(72, 44, 12, 8, op=.5)
        g += eye_arc_up(-24, 18, 15) + eye_arc_up(56, 18, 13)
        g += L("M -46,-20 Q -27,-28 -8,-20", sw=7) + L("M 40,-20 Q 57,-28 73,-20", sw=7)
        g += P("M 0,44 Q 21,50 42,44 Q 40,78 21,78 Q 2,78 0,44 Z", "#7A1020", sw=5)
        g += N(21, 70, 11, 6, "#FF7A8A")
    # fringe
    g += P("M -103,4 C -110,-70 -52,-108 4,-106 C 62,-104 102,-62 99,-8 C 92,-28 82,-44 68,-56 C 68,-40 62,-26 52,-16 C 48,-34 38,-50 24,-60 C 22,-42 12,-26 -2,-16 C -6,-34 -16,-50 -30,-58 C -34,-36 -48,-18 -66,-8 C -66,-22 -70,-36 -76,-44 C -84,-26 -94,-8 -103,4 Z", "url(#hairK)", sw=hs)
    g += L("M -60,-66 Q -30,-86 6,-86", sw=5, stroke="#D9A066", extra='opacity=".7"')
    g += crown(hs)
    return g + '</g>'

def tear_stream(x, top, bottom, w=8):
    return P(f"M {x-w},{top} C {x-w-3},{(top+bottom)/2} {x-w+1},{bottom-8} {x-w+3},{bottom} L {x+w-1},{bottom+2} C {x+w+1},{bottom-10} {x+w+2},{(top+bottom)/2} {x+w},{top} Z", "url(#tear)", sw=3, stroke="#3F9FDD")
def drop(x, y, s=1.0, rot=0):
    return f'<g transform="translate({x},{y}) rotate({rot}) scale({s})">' + P("M 0,-18 C 10,-4 13,4 13,9 A 13,13 0 1 1 -13,9 C -13,4 -10,-4 0,-18 Z", "url(#tear)", sw=3.5, stroke="#3F9FDD") + N(-4, 8, 3.5, 5, "#FFFFFF", 'opacity=".9"') + '</g>'

def head_queen(cx, cy, R, expr, tilt=0):
    hs = SW * 100 / R
    g = f'<g transform="translate({cx},{cy}) rotate({tilt}) scale({R/100})">'
    g += E(-6, -8, 107, 105, "url(#hairQ)", sw=hs)
    g += E(-91, 18, 15, 19, "url(#skin)", sw=hs)
    g += E(0, 0, 100, 95, "url(#skin)", sw=hs)
    if expr == "cry":
        g += blush(-46, 50, 18, 10, op=.55) + blush(72, 48, 14, 9, op=.55)
        g += tear_stream(-24, 22, 84) + tear_stream(56, 22, 70, w=7)
        g += eye_arc_down(-24, 14, 16, lash=True) + eye_arc_down(56, 14, 13)
        g += L("M -48,-10 L -8,-24", sw=6.5) + L("M 40,-24 L 74,-10", sw=6.5)
        g += P("M -2,50 Q 9,42 20,48 Q 31,42 42,50 Q 44,80 20,80 Q -4,80 -2,50 Z", "#7A1020", sw=5)
        g += N(20, 72, 12, 6, "#FF7A8A")
        g += drop(-124, -20, 1.0, 50) + drop(-134, 40, .75, 35) + drop(126, -28, .95, -50) + drop(134, 26, .7, -35)
    elif expr == "happy":
        g += blush(-46, 48, 18, 10, op=.6) + blush(72, 46, 14, 9, op=.6)
        g += eye_open(-24, 14, 15, 22, "irisQ", lash=True, sparkle=True) + eye_open(56, 14, 12.5, 21, "irisQ", sparkle=True)
        g += L("M -46,-24 Q -27,-32 -8,-25", sw=5.5) + L("M 40,-25 Q 57,-32 73,-24", sw=5.5)
        g += P("M 0,46 Q 21,52 42,46 Q 40,78 21,78 Q 2,78 0,46 Z", "#7A1020", sw=5)
        g += N(21, 70, 11, 6, "#FF7A8A")
        g += drop(-52, 30, .6, -20)
    elif expr == "kiss":
        g += blush(-30, 50, 20, 11, op=.7) + blush(78, 40, 12, 10, op=.7)
        g += eye_arc_down(-6, 12, 16, lash=True) + eye_arc_down(68, 12, 11)
        g += L("M -30,-22 Q -10,-30 12,-22", sw=5.5) + L("M 54,-22 Q 68,-28 82,-20", sw=5.5)
    # fringe (side-swept)
    g += P("M -104,10 C -112,-72 -52,-110 4,-108 C 64,-106 104,-62 100,2 C 94,-22 86,-40 72,-54 C 44,-28 4,-18 -36,-26 C -28,-36 -22,-48 -20,-58 C -40,-40 -62,-32 -78,-34 C -90,-18 -98,-4 -104,10 Z", "url(#hairQ)", sw=hs)
    g += L("M -62,-70 Q -28,-92 14,-90", sw=6, stroke="#FFFFFF", extra='opacity=".75"')
    # side locks
    g += P("M -101,-6 C -120,34 -118,96 -100,138 C -98,110 -86,84 -84,34 C -84,16 -90,2 -101,-6 Z", "url(#hairQ)", sw=hs)
    if expr == "kiss":
        g += P("M 86,36 C 100,31 106,41 97,46 C 106,51 100,61 86,56 C 81,52 81,40 86,36 Z", "#F0486E", sw=3.5)
    else:
        g += P("M 97,-4 C 110,34 106,86 94,124 C 90,96 84,66 86,28 C 88,14 92,4 97,-4 Z", "url(#hairQ)", sw=hs)
    g += tiara(hs)
    return g + '</g>'

# ---------- bodies (canvas units, head centre given) ----------
def sword(hx, hy, ang, length=330):
    g = f'<g transform="translate({hx},{hy}) rotate({ang})">'
    g += P(f"M -22,-40 L -22,{-length+40} L 0,{-length} L 22,{-length+40} L 22,-40 Z", "url(#steel)")
    g += L(f"M 0,-50 L 0,{-length+50}", sw=5, stroke="#8E9AB2")
    g += P("M -62,-52 Q 0,-34 62,-52 L 62,-24 Q 0,-8 -62,-24 Z", "url(#gold)")
    g += P("M -15,-22 L 15,-22 L 13,52 L -13,52 Z", "url(#boot)")
    g += E(0, 62, 20, 20, "url(#gold)") + E(0, -32, 9, 9, "#FF3B5C", sw=5)
    return g + '</g>'

def arm(x1, y1, x2, y2, fill, w=58, hand=31, cuff=None):
    g = f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{OL}" stroke-width="{w+2*SW}" stroke-linecap="round"/>'
    g += f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{fill}" stroke-width="{w}" stroke-linecap="round"/>'
    g += E(x2, y2, hand, hand, "url(#skin)")
    return g

def king(pose):
    """Right-facing king, head centre (500,400), feet y≈945."""
    R = 215
    g = '<g>'
    lean = {"idle": 0, "attack": 9, "kiss": 0, "victory": 0}[pose]
    g += f'<g transform="rotate({lean} 500 940)">'
    # cape
    if pose == "attack":
        g += P("M 410,590 C 300,560 170,640 110,760 C 190,750 230,790 250,850 C 330,800 420,820 470,880 L 600,600 Z", "url(#red)")
    else:
        g += P("M 414,590 C 330,650 292,790 274,902 C 330,880 372,900 400,930 C 440,896 500,900 540,930 L 612,600 Z", "url(#red)")
        g += L("M 380,700 C 352,770 340,830 334,880", sw=5, stroke="#7A0C20", extra='opacity=".6"')
    # back arm (viewer's left)
    if pose == "attack":
        g += arm(420, 640, 330, 700, "#0F8C8A")
    elif pose == "victory":
        g += arm(420, 640, 330, 560, "#0F8C8A")
    else:
        g += arm(420, 640, 374, 752, "#0F8C8A")
    # legs + boots
    if pose == "attack":
        g += P("M 420,820 L 330,900 L 300,946 L 392,950 L 400,920 L 480,860 Z", "url(#boot)")
        g += P("M 530,830 L 590,890 L 584,950 L 690,950 Q 690,916 640,908 L 620,830 Z", "url(#boot)")
    else:
        g += P("M 428,830 L 424,948 L 520,948 Q 522,918 494,910 L 496,830 Z", "url(#boot)")
        g += P("M 522,830 L 520,948 L 622,948 Q 624,916 592,910 L 594,830 Z", "url(#boot)")
    # tunic
    g += P("M 418,600 Q 512,556 606,600 L 646,852 Q 512,896 378,852 Z", "url(#teal)")
    g += P("M 384,812 L 378,852 Q 512,896 646,852 L 640,812 Q 512,856 384,812 Z", "url(#gold)", sw=8)
    g += P("M 492,600 L 532,600 L 540,838 L 484,838 Z", "url(#gold)", sw=8)
    g += P("M 398,728 Q 512,762 626,728 L 631,764 Q 512,800 393,764 Z", "url(#boot)", sw=8)
    g += P("M 486,738 L 540,738 L 540,790 L 486,790 Z", "url(#gold)", sw=8) + N(513, 764, 10, 10, "#B96C06")
    # fur collar
    g += P("M 398,612 C 400,570 470,560 512,566 C 560,560 624,572 626,612 C 628,650 570,660 512,654 C 456,660 396,650 398,612 Z", "url(#white)")
    for x, y in ((430, 628), (478, 640), (548, 640), (594, 626)):
        g += N(x, y, 6, 9, OL)
    # front arm + sword
    if pose == "idle":
        g += sword(694, 700, 24)
        g += arm(606, 640, 690, 702, "#19B8AA")
    elif pose == "attack":
        g += sword(742, 640, 78, length=250)
        g += arm(606, 640, 736, 642, "#19B8AA")
    elif pose == "victory":
        g += sword(700, 520, 8)
        g += arm(606, 640, 696, 524, "#19B8AA")
    else:
        g += arm(606, 640, 690, 720, "#19B8AA")
    # head
    expr = pose
    g += head_king(500, 400, R, expr, tilt={"attack": 4, "victory": -4}.get(pose, 0))
    g += '</g></g>'
    return g

def queen(pose):
    """Right-facing queen, head centre (512,410), feet y≈950."""
    R = 200
    g = '<g>'
    # long back hair
    g += P("M 400,300 C 300,380 286,520 300,640 C 310,730 262,800 300,880 C 330,920 400,900 420,840 C 450,760 430,700 440,640 L 620,600 L 600,300 Z", "url(#hairQd)")
    g += L("M 350,520 C 340,640 330,740 344,850", sw=5, stroke="#FFF3B5", extra='opacity=".6"')
    # skirt
    g += P("M 432,668 Q 512,644 592,668 C 650,740 722,860 742,926 Q 512,990 282,926 C 302,860 374,740 432,668 Z", "url(#gown)")
    g += P("M 474,662 Q 512,654 550,662 L 610,952 Q 512,972 414,952 Z", "url(#gownlight)", sw=8)
    # hem ruffle
    hem = ""
    import math
    n = 11
    for i in range(n):
        t = i / (n - 1)
        x = 296 + t * (728 - 296)
        y = 928 + 30 * math.sin(math.pi * t)
        hem += E(round(x), round(y), 27, 20, "url(#white)", sw=8)
    g += hem
    # bodice
    g += P("M 440,604 Q 512,584 584,604 L 598,676 Q 512,700 426,676 Z", "url(#bodice)")
    g += P("M 426,664 Q 512,690 598,664 L 601,688 Q 512,714 423,688 Z", "url(#gold)", sw=7)
    g += E(512, 696, 11, 11, "#3FE0D0", sw=6)
    # sleeves + arms
    if pose == "cry":
        g += arm(430, 640, 412, 592, "url(#skin)", w=36, hand=30)
        g += arm(596, 640, 650, 600, "url(#skin)", w=36, hand=30)
    elif pose == "happy":
        g += arm(432, 646, 500, 628, "url(#skin)", w=36, hand=30)
        g += arm(594, 646, 540, 628, "url(#skin)", w=36, hand=30)
    else:  # kiss: hands clasped forward
        g += arm(432, 646, 506, 632, "url(#skin)", w=36, hand=30)
        g += arm(594, 646, 544, 636, "url(#skin)", w=36, hand=30)
    g += E(426, 634, 46, 42, "url(#gownlight)") + E(598, 634, 46, 42, "url(#gownlight)")
    g += head_queen(512, 410, R, pose, tilt={"cry": 3, "happy": -3, "kiss": 12}.get(pose, 0))
    return g + '</g>'


# ---------- BOSS (magenta ogre demon-king; drawn facing right, flipped in build) ----------
def eye_squint_l(x, y, w, hs=6.5):    # < shape
    return L(f"M {x+w},{y-w*0.7} L {x-w*0.6},{y} L {x+w},{y+w*0.7}", sw=hs)
def eye_spiral(x, y, r, hs=5.5, turns=2.4):
    import math
    pts = []
    n = 44
    for i in range(n + 1):
        t = i / n
        a = t * turns * 2 * math.pi
        rr = 1.5 + (r - 1.5) * t
        pts.append(f"{x + rr*math.cos(a):.1f},{y + rr*math.sin(a):.1f}")
    return L("M " + " L ".join(pts), sw=hs)
def star(x, y, r, rot=0, sw=5):
    import math
    pts = []
    for i in range(10):
        a = math.radians(rot - 90 + i * 36)
        rr = r if i % 2 == 0 else r * 0.46
        pts.append(f"{x + rr*math.cos(a):.1f},{y + rr*math.sin(a):.1f}")
    return P("M " + " L ".join(pts) + " Z", "url(#gold)", sw=sw) + N(x - r*.18, y - r*.2, r*.16, r*.12, "#FFFFFF", 'opacity=".9"')

def horn(hs):
    k = .76
    hs = hs / k
    g = f'<g transform="translate(-64,-62) scale({k}) translate(64,62)">'
    g += P("M -88,-40 C -132,-62 -146,-124 -116,-170 C -112,-130 -92,-102 -40,-84 C -52,-62 -68,-46 -88,-40 Z", "url(#gold)", sw=hs)
    g += L("M -116,-84 Q -104,-96 -86,-98", sw=4, stroke="#B96C06") + L("M -124,-116 Q -114,-126 -102,-126", sw=4, stroke="#B96C06")
    g += L("M -122,-150 Q -128,-126 -122,-100", sw=4, stroke="#FFFFFF", extra='opacity=".75"')
    return g + '</g>'

def head_boss(cx, cy, R, expr, tilt=0):
    """expr: idle | hurt | ko. Head-local units, radius 100, facing right."""
    hs = SW * 100 / R
    g = f'<g transform="translate({cx},{cy}) rotate({tilt}) scale({R/100})">'
    # pointed ear + gold ring
    g += P("M -90,-12 C -112,-34 -134,-34 -146,-22 C -132,-12 -122,14 -92,38 Z", "url(#bskind)", sw=hs)
    g += L("M -128,-20 Q -112,-12 -104,4", sw=3.5, stroke="#7A0E58", extra='opacity=".8"')
    g += f'<circle cx="-112" cy="34" r="10" fill="none" stroke="{OL}" stroke-width="{hs+5}"/><circle cx="-112" cy="34" r="10" fill="none" stroke="#FFCC33" stroke-width="5"/>'
    g += E(0, 0, 100, 95, "url(#bskin)", sw=hs)
    # horns (near one, far one mirrored and nudged for the 3/4 view)
    g += horn(hs) + '<g transform="translate(12,0) scale(-1,1)">' + horn(hs) + '</g>'
    lid = "#E64AB0"
    if expr == "idle":
        g += N(-52, 48, 17, 10, "#FFC0E6", 'opacity=".5"') + N(80, 44, 11, 9, "#FFC0E6", 'opacity=".5"')
        g += eye_open(-26, 14, 18, 22, "irisB", hs=5.5) + eye_open(54, 14, 15.5, 21, "irisB", hs=5.5)
        g += '<clipPath id="bcl"><ellipse cx="-26" cy="14" rx="22" ry="27"/></clipPath><clipPath id="bcr"><ellipse cx="54" cy="14" rx="19" ry="26"/></clipPath>'
        g += f'<path d="M -60,-27 L 0,3 L 0,-40 L -60,-40 Z" fill="{lid}" clip-path="url(#bcl)"/><path d="M 30,3 L 84,-27 L 84,-40 L 30,-40 Z" fill="{lid}" clip-path="url(#bcr)"/>'
        g += L("M -54,-24 L -2,2", sw=10.5) + L("M 34,2 L 80,-24", sw=10.5)
        # big fanged grin
        g += P("M -30,42 Q 16,62 70,32 Q 72,84 22,88 Q -22,86 -30,42 Z", "#5A0A1E", sw=5.5)
        g += N(22, 78, 20, 8, "#FF7A8A")
        g += P("M -22,47 Q 16,64 64,38 L 60,50 Q 18,74 -18,58 Z", "#FFFFFF", sw=3.5)
        g += P("M -22,46 L -12,76 L 0,55 Z", "#FFFFFF", sw=4) + P("M 46,48 L 58,72 L 66,38 Z", "#FFFFFF", sw=4)
    elif expr == "hurt":
        g += N(-52, 50, 18, 10, "#FFC0E6", 'opacity=".55"') + N(80, 46, 11, 9, "#FFC0E6", 'opacity=".55"')
        g += eye_squint(-26, 14, 19, hs=8) + eye_squint_l(56, 14, 17, hs=8)
        g += L("M -52,-16 Q -30,-32 -6,-28", sw=9) + L("M 36,-28 Q 60,-32 80,-16", sw=9)
        g += P("M -22,48 Q 20,36 64,46 Q 70,78 22,80 Q -26,80 -22,48 Z", "#FFFFFF", sw=5.5)
        g += L("M -20,63 Q 22,58 66,62", sw=3.5) + L("M 0,46 L 0,78 M 22,44 L 22,79 M 44,44 L 44,78", sw=3.5)
        g += P("M -18,48 L -8,66 L 2,46 Z", "#FFFFFF", sw=3.5) + P("M 44,45 L 54,64 L 63,46 Z", "#FFFFFF", sw=3.5)
        g += drop(-128, -40, 1.3, 50) + drop(-150, 62, .9, 60) + drop(120, -52, 1.05, -45)
    else:  # ko
        g += N(-52, 50, 18, 10, "#FFC0E6", 'opacity=".55"') + N(80, 46, 11, 9, "#FFC0E6", 'opacity=".55"')
        g += eye_spiral(-26, 12, 21, hs=6) + eye_spiral(56, 12, 18, hs=6)
        g += L("M -52,-30 Q -30,-36 -6,-26", sw=8) + L("M 36,-26 Q 60,-36 80,-28", sw=8)
        g += P("M -14,50 Q 4,40 20,50 Q 36,40 56,50 Q 58,80 20,80 Q -16,80 -14,50 Z", "#5A0A1E", sw=5.5)
        g += P("M -8,50 L 2,66 L 10,49 Z", "#FFFFFF", sw=3.5)
        g += P("M 14,66 Q 34,60 48,68 Q 54,96 34,98 Q 14,96 14,66 Z", "#FF7A8A", sw=4.5) + L("M 32,72 L 33,86", sw=3, stroke="#C2405A")
    # spiky tuft between the horns
    g += P("M -38,-84 L -34,-122 L -14,-100 L 2,-140 L 20,-100 L 42,-124 L 48,-84 Q 6,-100 -38,-84 Z", "url(#bhair)", sw=hs)
    g += L("M -2,-124 L -6,-104", sw=4, stroke="#C9A6FF", extra='opacity=".8"')
    if expr == "ko":
        g += f'<ellipse cx="8" cy="-158" rx="96" ry="18" fill="none" stroke="#FFFFFF" stroke-width="4" stroke-dasharray="10 12" opacity=".7"/>'
        g += star(-86, -160, 21, -15, sw=hs) + star(12, -178, 25, 8, sw=hs) + star(102, -154, 19, 20, sw=hs)
    return g + '</g>'

def mace(hx, hy, ang, length=215):
    import math
    g = f'<g transform="translate({hx},{hy}) rotate({ang})">'
    g += P(f"M -15,58 L -17,{-length+30} L 17,{-length+30} L 15,58 Z", "url(#boot)")
    g += L(f"M -6,40 L -7,{-length+60}", sw=4, stroke="#C08A5A", extra='opacity=".7"')
    g += E(0, 66, 21, 19, "url(#gold)")
    g += P(f"M -24,{-length+62} L 24,{-length+62} L 22,{-length+40} L -22,{-length+40} Z", "url(#gold)", sw=8)
    for a in range(0, 360, 45):
        g += f'<g transform="translate(0,{-length}) rotate({a+22})">' + P("M -19,-56 L 0,-102 L 19,-56 Z", "url(#gold)", sw=9) + '</g>'
    g += E(0, -length, 68, 68, "url(#ironball)")
    g += P(f"M -17,{-length+4} L 0,{-length-24} L 17,{-length+4} L 0,{-length+20} Z", "url(#gold)", sw=7)
    g += L(f"M -44,{-length-22} Q -34,{-length-46} -10,{-length-52}", sw=5, stroke="#FFFFFF", extra='opacity=".7"')
    return g + '</g>'

def blimb(x1, y1, x2, y2, fill, w=74, hand=42, handfill="url(#bskin)", bracer=True):
    import math
    g = f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{OL}" stroke-width="{w+2*SW}" stroke-linecap="round"/>'
    g += f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{fill}" stroke-width="{w}" stroke-linecap="round"/>'
    if bracer:
        d = math.hypot(x2 - x1, y2 - y1) or 1
        ux, uy = (x2 - x1) / d, (y2 - y1) / d
        a, b = d - hand - 44, d - hand + 4
        ax, ay, bx, by = x1 + ux*a, y1 + uy*a, x1 + ux*b, y1 + uy*b
        g += f'<line x1="{ax-ux*SW/2:.1f}" y1="{ay-uy*SW/2:.1f}" x2="{bx+ux*SW/2:.1f}" y2="{by+uy*SW/2:.1f}" stroke="{OL}" stroke-width="{w+10+2*SW}"/>'
        g += f'<line x1="{ax:.1f}" y1="{ay:.1f}" x2="{bx:.1f}" y2="{by:.1f}" stroke="#666D8A" stroke-width="{w+10}"/>'
        g += f'<line x1="{ax:.1f}" y1="{ay:.1f}" x2="{bx:.1f}" y2="{by:.1f}" stroke="#FFCC33" stroke-width="{w+10}" stroke-dasharray="9 39" stroke-dashoffset="-20"/>'
    g += E(x2, y2, hand, hand, handfill)
    return g

def pauldron(x, y, side):
    """side -1 = back shoulder (spike points back), +1 = front."""
    g = P(f"M {x+side*26},{y-30} L {x+side*86},{y-52} L {x+side*50},{y+4} Z", "url(#gold)", sw=9)
    g += E(x, y, 56, 46, "url(#iron)")
    g += L(f"M {x-34},{y-14} Q {x-10},{y-34} {x+22},{y-30}", sw=5, stroke="#FFFFFF", extra='opacity=".6"')
    g += E(x + side*4, y + 14, 9, 9, "#FFCC33", sw=5)
    return g

def boss_torso():
    g = P("M 336,838 L 322,896 L 366,876 L 398,912 L 440,884 L 482,918 L 522,886 L 562,916 L 604,884 L 644,908 L 672,874 L 708,892 L 692,838 Z", "url(#bcape)")
    g += P("M 396,668 Q 512,632 628,668 C 690,740 702,800 692,850 Q 512,900 332,850 C 322,800 334,740 396,668 Z", "url(#bskin)")
    g += N(546, 756, 92, 62, "#FFC6EC", 'opacity=".5"')
    g += L("M 520,712 Q 546,724 574,710", sw=5, stroke="#B41C84", extra='opacity=".7"')
    g += P("M 329,796 Q 512,846 695,796 L 695,846 Q 512,898 329,846 Z", "url(#iron)", sw=9)
    g += L("M 346,812 Q 512,860 680,812", sw=4, stroke="#FFFFFF", extra='opacity=".45"')
    g += E(538, 852, 33, 33, "url(#gold)", sw=8) + E(538, 852, 19, 19, "#FFE680", sw=5) + N(531, 845, 6, 5, "#FFFFFF", 'opacity=".9"')
    for x, y in ((392, 836), (446, 850), (628, 848), (668, 836)):
        g += E(x, y, 7, 7, "#FFCC33", sw=4)
    # spiked collar
    g += P("M 384,680 C 386,640 470,632 512,636 C 560,632 638,642 640,680 C 642,714 570,722 512,718 C 456,722 382,714 384,680 Z", "url(#iron)")
    for x, y in ((420, 698), (468, 708), (556, 708), (604, 698)):
        g += P(f"M {x-11},{y-8} L {x+11},{y-8} L {x},{y+16} Z", "url(#gold)", sw=5)
    return g

def boot_stand(x):
    g = P(f"M {x+8},866 L {x},975 L {x+120},975 Q {x+122},938 {x+86},928 L {x+88},866 Z", "url(#iron)")
    g += P(f"M {x+70},975 L {x+120},975 Q {x+122},944 {x+96},934 Q {x+72},944 {x+70},975 Z", "url(#gold)", sw=8)
    g += L(f"M {x+6},898 L {x+87},898", sw=6)
    return g

def boss(pose):
    """Right-facing boss, head centre (512,430) R=250, feet y=975. pose: idle | hurt | ko."""
    R = 250
    g = '<g>'
    if pose in ("idle", "hurt"):
        lean = {"idle": 0, "hurt": -6}[pose]
        g += boot_stand(392) + boot_stand(524)
        g += f'<g transform="rotate({lean} 512 900)">'
        if pose == "idle":
            g += P("M 404,668 C 300,700 236,820 204,962 L 252,932 L 288,970 L 328,932 L 366,968 L 400,936 L 442,962 L 620,690 Z", "url(#bcape)")
        else:
            g += P("M 404,668 C 300,664 210,740 150,872 L 190,860 L 206,908 L 250,878 L 280,922 L 330,892 L 372,930 L 620,690 Z", "url(#bcape)")
        g += L("M 372,740 C 330,800 306,860 296,920", sw=5, stroke="#2A0E5C", extra='opacity=".6"')
        # back arm
        if pose == "idle":
            g += blimb(398, 716, 340, 826, "#C22A8E")
        else:
            g += blimb(398, 716, 286, 668, "#C22A8E")
        g += boss_torso()
        g += pauldron(392, 694, -1)
        if pose == "idle":
            g += mace(800, 742, 17)
            g += blimb(636, 714, 796, 744, "#EE4BB4")
        else:
            g += mace(806, 640, 42)
            g += blimb(636, 714, 800, 644, "#EE4BB4")
        g += pauldron(640, 694, 1)
        g += head_boss(512, 430 if pose == "idle" else 444, R, pose, tilt={"idle": 0, "hurt": -4}[pose])
        g += '</g>'
    else:
        # sitting dazed like a dropped plush: leaning back, soles forward, mace on the ground
        g += '<clipPath id="bko"><rect x="-100" y="-100" width="1300" height="1078"/></clipPath><g clip-path="url(#bko)">'
        sit = '<g transform="rotate(-9 470 975)"><g transform="translate(0,64)">'
        g += P("M 380,760 C 250,800 150,880 96,968 L 470,972 L 560,760 Z", "url(#bcape)")
        g += sit + blimb(398, 716, 304, 826, "#C22A8E") + boss_torso() + pauldron(392, 694, -1) + '</g></g>'
        for x, rot in ((432, -14), (648, 12)):
            g += f'<g transform="translate({x},914) rotate({rot})">'
            g += E(0, 0, 66, 55, "url(#iron)")
            g += P("M -58,-24 C -44,-66 44,-66 58,-24 C 26,-40 -26,-40 -58,-24 Z", "url(#gold)", sw=8)
            g += E(0, 10, 36, 26, "#3C405A", sw=6) + L("M -22,4 L 22,4 M -24,18 L 24,18", sw=5)
            g += '</g>'
        g += mace(744, 922, 72, length=172)
        g += sit + blimb(636, 714, 742, 836, "#EE4BB4") + pauldron(640, 694, 1) + '</g>'
        g += head_boss(512, 552, R, "ko", tilt=-7)
        g += '</g></g>'
    return g + '</g>'

def svg(w, h, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">{DEFS}{body}</svg>'

def build(out):
    os.makedirs(out, exist_ok=True)
    files = {
        "KingIdle": svg(1024, 1024, f'<g transform="translate(-30,30)">{king("idle")}</g>'),
        "KingAttack": svg(1024, 1024, f'<g transform="translate(-40,30)">{king("attack")}</g>'),
        "QueenCry": svg(1024, 1024, f'<g transform="translate(1024,20) scale(-1,1)">{queen("cry")}</g>'),
        "QueenHappy": svg(1024, 1024, f'<g transform="translate(1024,20) scale(-1,1)">{queen("happy")}</g>'),
        "KingQueenKiss": svg(1536, 1024,
            f'<g transform="translate(110,30)">{king("kiss")}</g>'
            f'<g transform="translate(1464,-10) scale(-1,1)">{queen("kiss")}</g>'),
        "KingVictory": svg(1024, 1024, f'<g transform="translate(-30,30)">{king("victory")}</g>'),
        "BossIdle": svg(1024, 1024, f'<g transform="translate(1054,0) scale(-1,1)">{boss("idle")}</g>'),
        "BossHurt": svg(1024, 1024, f'<g transform="translate(1054,0) scale(-1,1)">{boss("hurt")}</g>'),
        "BossKO": svg(1024, 1024, f'<g transform="translate(1054,0) scale(-1,1)">{boss("ko")}</g>'),
    }
    for k, v in files.items():
        open(os.path.join(out, k + ".svg"), "w").write(v)

if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else "out")
