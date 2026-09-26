from pathlib import Path
import io
import struct
from PIL import Image, ImageDraw

root = Path(__file__).parent
assets = root / "Assets"
assets.mkdir(parents=True, exist_ok=True)

scale = 4
image = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
draw = ImageDraw.Draw(image)
draw.rounded_rectangle((48, 48, 976, 976), radius=210, fill="#121c2b")

def tile(box, color, radius=28):
    draw.rounded_rectangle(tuple(v * scale for v in box), radius=radius * scale, fill=color)

tile((34, 34, 139, 133), "#64c8b5")
tile((143, 34, 222, 78), "#7d96e8", 18)
tile((143, 82, 222, 133), "#d58dab", 18)
tile((34, 137, 98, 222), "#9e83d8")
tile((102, 137, 162, 222), "#e2b36c")
tile((166, 137, 222, 222), "#5ea9cb")

image.save(assets / "driveviewer.png")
chunks = []
for size, kind in [(16, b"icp4"), (32, b"icp5"), (64, b"icp6"),
                   (128, b"ic07"), (256, b"ic08"), (512, b"ic09"), (1024, b"ic10")]:
    output = io.BytesIO()
    image.resize((size, size), Image.Resampling.LANCZOS).save(output, format="PNG")
    payload = output.getvalue()
    chunks.append(kind + struct.pack(">I", len(payload) + 8) + payload)
content = b"".join(chunks)
(assets / "driveviewer.icns").write_bytes(b"icns" + struct.pack(">I", len(content) + 8) + content)
