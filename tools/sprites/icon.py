"""game/icon.png: the app icon, Pikachu's Happy portrait from SpriteCollab in a rounded frame (192x192)."""
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import common  # noqa: E402

SIZE, BORDER, RADIUS = 192, 14, 36
FRAME = (24, 32, 96, 255)


def main(out=None):
    src = os.path.join(common.SPRITECOLLAB, "portrait", "0025", "Happy.png")
    if not os.path.exists(src):
        src = os.path.join(common.SPRITECOLLAB, "portrait", "0025", "Normal.png")
    por = Image.open(src).convert("RGBA")
    inner = SIZE - 2 * BORDER
    por = por.resize((inner, inner), Image.NEAREST)
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], RADIUS, fill=255)
    img = Image.new("RGBA", (SIZE, SIZE), FRAME)
    inner_mask = Image.new("L", (inner, inner), 0)
    ImageDraw.Draw(inner_mask).rounded_rectangle([0, 0, inner - 1, inner - 1], RADIUS - BORDER, fill=255)
    img.paste(por, (BORDER, BORDER), inner_mask)
    out_img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out_img.paste(img, (0, 0), mask)
    out_img.save(out or os.path.join(common.GAME, "icon.png"))
    print("icon.png written")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
