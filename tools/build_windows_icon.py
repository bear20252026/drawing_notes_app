from pathlib import Path

from PIL import Image

root = Path(__file__).resolve().parents[1]
source = root / "assets" / "release" / "app_icon_source.png"
target = root / "windows" / "runner" / "resources" / "app_icon.ico"
target.parent.mkdir(parents=True, exist_ok=True)

with Image.open(source) as image:
    icon = image.convert("RGBA")
    icon.save(
        target,
        format="ICO",
        sizes=[(16, 16), (20, 20), (24, 24), (32, 32), (40, 40), (48, 48), (64, 64), (128, 128), (256, 256)],
    )

print(target)
