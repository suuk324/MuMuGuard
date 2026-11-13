"""
生成 MuMuGuard 图标：白底圆角方块 + 黑色图形
输出多尺寸 ICO（16/24/32/48/64/128/256）以及 256px PNG 预览
"""
import sys
from PIL import Image, ImageDraw

SRC = r"C:\Users\MOOM\.dsh\attachments\v1\objects\ea\ea2d9be382dbdf96478ec3f1f3c5070733ffcbad6a481b641aadc9ddf07ff9e2"
OUT_ICO = r"C:\Users\MOOM\Documents\MuMuGuard\MuMuGuard.ico"
OUT_PNG = r"C:\Users\MOOM\Documents\MuMuGuard\icon.png"
OUT_PREVIEW = r"C:\Users\MOOM\AppData\Local\Temp\icon_preview.png"

BASE = 1024          # 主画布
RADIUS_RATIO = 0.225 # 圆角半径占画布比例（苹果式圆角）
GLYPH_RATIO = 0.90   # 图形占画布比例

# 1) 读入黑色图形，去掉四周透明留白
glyph = Image.open(SRC).convert("RGBA")
bbox = glyph.getbbox()
glyph = glyph.crop(bbox)

# 2) 把图形缩放后居中放进画布，留出白边
side = int(BASE * GLYPH_RATIO)
gw, gh = glyph.size
scale = min(side / gw, side / gh)
glyph = glyph.resize((max(1, int(gw * scale)), max(1, int(gh * scale))), Image.LANCZOS)

canvas = Image.new("RGBA", (BASE, BASE), (0, 0, 0, 0))

# 3) 白色圆角底
radius = int(BASE * RADIUS_RATIO)
mask = Image.new("L", (BASE, BASE), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, BASE - 1, BASE - 1], radius=radius, fill=255)

white = Image.new("RGBA", (BASE, BASE), (255, 255, 255, 255))
canvas.paste(white, (0, 0), mask)

# 4) 叠加图形（保持原有 alpha，避免黑边）
gx = (BASE - glyph.width) // 2
gy = (BASE - glyph.height) // 2
canvas.alpha_composite(glyph, (gx, gy))

# 5) 输出 ICO（多尺寸）与 PNG
sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (24, 24), (16, 16)]
canvas.save(OUT_ICO, format="ICO", sizes=sizes)

canvas.resize((256, 256), Image.LANCZOS).save(OUT_PNG, format="PNG")
canvas.resize((256, 256), Image.LANCZOS).save(OUT_PREVIEW, format="PNG")

# 6) 生成对比预览图：256 / 48 / 32 / 16 并排
preview = Image.new("RGBA", (256 + 48 + 32 + 16 + 60, 256), (24, 28, 36, 255))
x = 10
for s in (256, 48, 32, 16):
    preview.alpha_composite(canvas.resize((s, s), Image.LANCZOS), (x, (256 - s) // 2))
    x += s + 16
preview.save(OUT_PREVIEW, format="PNG")

print("ICO:", OUT_ICO)
print("PNG:", OUT_PNG)
print("PREVIEW:", OUT_PREVIEW)
print("sizes:", [f"{w}x{h}" for w, h in sizes])