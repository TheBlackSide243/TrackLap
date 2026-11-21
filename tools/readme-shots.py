"""The README's screenshots from the ones the Screenshots workflow makes.

    python tools/readme-shots.py <folder with the workflow's shots>

Each one goes to docs/readme as a 600 px wide WebP with the corners of the phone's screen rounded
off, under the name the READMEs use.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

WIDTH = 600
RADIUS = 72
# The workflow's name -> the README's.
NAMES = {
    "live": "live", "session": "session", "analysis": "analysis", "editor": "editor",
    "challenge": "challenge", "group": "group", "share": "share",
    "drag": "drag", "dragRun": "drag-run",
    "garage": "garage", "car": "car", "setup": "setup",
    "livemotorcycle": "moto-live", "leanmotorcycle": "moto-lean",
}


def convert(src: Path, dst: Path) -> None:
    im = Image.open(src).convert("RGB")
    im = im.resize((WIDTH, round(im.height * WIDTH / im.width)), Image.LANCZOS)
    # The mask four times as big, then down: smooth corners.
    big = Image.new("L", (im.width * 4, im.height * 4), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, big.width - 1, big.height - 1), RADIUS * 4, fill=255)
    im.putalpha(big.resize(im.size, Image.LANCZOS))
    im.save(dst, "WEBP", quality=82, method=6)


def main() -> None:
    shots = Path(sys.argv[1])
    out = Path(__file__).resolve().parent.parent / "docs" / "readme"
    for lang in ("it", "en"):
        for theirs, ours in NAMES.items():
            src = shots / f"{lang}-{theirs}.png"
            if not src.exists():
                print("missing", src.name)
                continue
            dst = out / f"{lang}-{ours}.webp"
            convert(src, dst)
            print(dst.name, dst.stat().st_size // 1024, "KB")


if __name__ == "__main__":
    main()
