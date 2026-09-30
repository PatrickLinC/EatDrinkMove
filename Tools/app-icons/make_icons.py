"""把精靈的像素圖做成 App 替代圖示（1024×1024），風格跟主圖示一樣：上面是底色、下面奶油色

用法（需要 Pillow）：python3 Tools/app-icons/make_icons.py . /tmp/icons.png
第一個參數是專案資料夾，第二個是預覽圖要存的位置；圖示會寫進 iOS/Assets.xcassets/AppIcon-*.appiconset
"""
import json, os, re, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = sys.argv[1]
src = open(os.path.join(ROOT, "Shared/PixelKit.swift")).read()
arts = {m.group(1): re.findall(r'"([^"]*)"', m.group(2))
        for m in re.finditer(r"static let (\w+) = PixelArt\(\[(.*?)\]\)", src, re.S)}

# 主圖示的顏色
BROWN, INK, CREAM, WHITE, GOLD = (173, 130, 87), (76, 56, 40), (246, 237, 218), (255, 249, 238), (245, 205, 110)
PAL = {"k": INK, "e": INK, "w": WHITE, "h": WHITE, "s": (122, 100, 80), "b": (156, 111, 69), "c": (217, 130, 75),
       "a": (79, 143, 191), "g": (110, 154, 78), "y": (210, 160, 60), "p": (181, 87, 60), "t": (228, 211, 180), "f": (140, 123, 181)}

ICONS = {"onigiri": "companion", "boba": "companionBoba", "cat": "companionCat", "dog": "companionDog",
         "slime": "companionSlime", "dragon": "companionDragon", "unicorn": "companionUnicorn",
         "fox": "companionFox", "pumpkin": "companionPumpkin"}
# 每隻的底色（跟精靈的顏色錯開）
BACKGROUND = {"onigiri": BROWN, "boba": (97, 140, 170), "cat": (130, 115, 170), "dog": (110, 150, 85),
              "slime": (185, 110, 85), "dragon": (170, 85, 70), "unicorn": (80, 130, 175),
              "fox": (70, 130, 130), "pumpkin": (110, 90, 150)}

font = ImageFont.truetype(os.path.join(ROOT, "Shared/Fonts/Cubic_11.ttf"), 12)

def title_bitmap(text):
    """用像素字體畫 12px 的字（不反鋸齒），之後整張放大"""
    w = int(font.getlength(text)) + 2
    img = Image.new("L", (w, 16), 0)
    d = ImageDraw.Draw(img)
    d.fontmode = "1"
    d.text((1, 1), text, font=font, fill=255)
    return img.crop(img.getbbox())

def make(name, art_name):
    art = arts[art_name]
    img = Image.new("RGB", (1024, 1024), BACKGROUND[name])
    d = ImageDraw.Draw(img)
    # 下面的奶油色帶和分隔線
    d.rectangle([0, 704, 1024, 1024], fill=CREAM)
    d.rectangle([0, 672, 1024, 704], fill=INK)
    # 精靈：16 格 × 36 = 576，放在棕色區正中間，右下加一格硬陰影
    cell = 36
    ox, oy = (1024 - 16 * cell) // 2, (672 - 16 * cell) // 2 + 8
    for dx, dy, shadow in [(cell // 3, cell // 3, True), (0, 0, False)]:
        for y, row in enumerate(art):
            for x, ch in enumerate(row):
                if ch in PAL:
                    color = INK if shadow else PAL[ch]
                    d.rectangle([ox + x * cell + dx, oy + y * cell + dy, ox + (x + 1) * cell - 1 + dx, oy + (y + 1) * cell - 1 + dy], fill=color)
    # 標題：像素字體放大 8 倍，墨色
    text = title_bitmap("卡路里大作戰")
    scale = 8
    big = text.resize((text.width * scale, text.height * scale), Image.NEAREST)
    tx, ty = (1024 - big.width) // 2, 704 + (320 - big.height) // 2
    img.paste(INK, (tx, ty), big)
    folder = os.path.join(ROOT, f"iOS/Assets.xcassets/AppIcon-{name}.appiconset")
    os.makedirs(folder, exist_ok=True)
    img.save(os.path.join(folder, "AppIcon.png"))
    json.dump({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(folder, "Contents.json"), "w"), indent=2)
    return img

previews = [make(n, a) for n, a in ICONS.items()]
sheet = Image.new("RGB", (3 * 260, 3 * 260), (255, 255, 255))
for i, p in enumerate(previews):
    sheet.paste(p.resize((250, 250), Image.LANCZOS), ((i % 3) * 260, (i // 3) * 260))
sheet.save(sys.argv[2])
print("ok", list(ICONS))
