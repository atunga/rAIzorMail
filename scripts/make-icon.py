from pathlib import Path
from PIL import Image, ImageDraw
root = Path(__file__).resolve().parent.parent
folder = root / 'build' / 'icon.iconset'
folder.mkdir(parents=True, exist_ok=True)
im = Image.new('RGBA', (1024, 1024))
d = ImageDraw.Draw(im)
d.rounded_rectangle((42, 42, 982, 982), 210, fill='#242a20')
d.rounded_rectangle((44, 44, 980, 980), 208, outline='#536047', width=6)
d.rounded_rectangle((179, 319, 845, 762), 49, fill='#d1843e')
d.polygon([(179, 350), (512, 588), (845, 350)], fill='#e1a25d')
d.line([(200, 729), (435, 551), (512, 608), (590, 551), (824, 729)], fill='#ae632c', width=12, joint='curve')
d.line([(236, 306), (406, 120), (560, 291), (657, 175), (801, 306)], fill='#e7e2c9', width=22, joint='curve')
d.line([(345, 191), (406, 120), (474, 194), (416, 173), (383, 205), (345, 191)], fill='#94a88b', width=10, joint='curve')
for n in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        name = f'icon_{n}x{n}' + ('@2x' if scale == 2 else '') + '.png'
        im.resize((n*scale, n*scale), Image.Resampling.LANCZOS).save(folder / name)
(root / 'public').mkdir(exist_ok=True)
im.save(root / 'public' / 'icon.png')
