#!/usr/bin/env python3
"""Build the gallery catalog from a folder of product photos.

Usage (from the trade-show-gallery folder):

    pip install pillow
    python3 tools/build_catalog.py

What it does:
  1. Scans photos/ for original product photos (jpg, jpeg, png, webp, tif, bmp).
  2. Writes a web-sized copy to images/<id>.webp and a small copy to thumbs/<id>.webp.
     Transparent PNG cut-outs keep their transparency and are trimmed to the
     product outline, so they float on the sphere. Files are only regenerated
     when the original is newer than the output.
  3. Adds a row to products.csv for every new photo (name guessed from the file
     name, category "Uncategorized"). Existing rows are never overwritten, so it
     is safe to edit products.csv in Excel / Google Sheets and re-run.
  4. Writes products.js, which the gallery page loads.

The product id is the photo's file name without extension, lower-cased and
slugified (e.g. "Eye Bolt 3in.JPG" -> "eye-bolt-3in").
"""

import csv
import json
import re
import sys
from pathlib import Path

try:
    from PIL import Image, ImageOps
except ImportError:
    sys.exit("Pillow is required: pip install pillow")

ROOT = Path(__file__).resolve().parent.parent
PHOTOS = ROOT / "photos"
IMAGES = ROOT / "images"
THUMBS = ROOT / "thumbs"
CSV_PATH = ROOT / "products.csv"
JS_PATH = ROOT / "products.js"

IMAGE_MAX = 1600   # longest edge of the detail-view image
THUMB_MAX = 480    # longest edge of the sphere tile image
PHOTO_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".tif", ".tiff", ".bmp"}

COLUMNS = [
    "id", "name", "category", "material", "process", "finish",
    "industries", "description", "specs", "tags", "featured",
]
# Columns holding several values, separated by "|" in the CSV.
LIST_COLUMNS = {"industries", "tags"}


def slugify(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-") or "item"


def title_from_slug(slug):
    return " ".join(w.capitalize() for w in slug.split("-"))


def has_alpha(src):
    with Image.open(src) as im:
        if im.mode not in ("RGBA", "LA", "P"):
            return False
        alpha = im.convert("RGBA").getchannel("A")
        return alpha.getextrema()[0] < 250


def render(src, dest, max_edge, quality):
    """Resize src to dest (WebP). Transparent cut-outs keep their transparency and
    are trimmed to the product's outline so every object fills its sphere slot."""
    if dest.exists() and dest.stat().st_mtime >= src.stat().st_mtime:
        return False
    with Image.open(src) as im:
        im = ImageOps.exif_transpose(im)
        if im.mode in ("RGBA", "LA", "P"):
            im = im.convert("RGBA")
            box = im.getchannel("A").point(lambda a: 255 if a > 12 else 0).getbbox()
            if box:
                pad = round(max(box[2] - box[0], box[3] - box[1]) * 0.04)
                im = im.crop((max(0, box[0] - pad), max(0, box[1] - pad),
                              min(im.width, box[2] + pad), min(im.height, box[3] + pad)))
        else:
            im = im.convert("RGB")
        im.thumbnail((max_edge, max_edge), Image.LANCZOS)
        dest.parent.mkdir(parents=True, exist_ok=True)
        im.save(dest, "WEBP", quality=quality, method=6)
    return True


def read_csv():
    if not CSV_PATH.exists():
        return []
    with CSV_PATH.open(newline="", encoding="utf-8-sig") as f:
        return [{c: (row.get(c) or "").strip() for c in COLUMNS} for row in csv.DictReader(f)]


def write_csv(rows):
    with CSV_PATH.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=COLUMNS)
        writer.writeheader()
        writer.writerows(rows)


def parse_specs(text):
    """"Finish: Black; Holes: 6" -> [["Finish", "Black"], ["Holes", "6"]]"""
    specs = []
    for part in text.split(";"):
        if ":" in part:
            key, value = part.split(":", 1)
            specs.append([key.strip(), value.strip()])
        elif part.strip():
            specs.append(["", part.strip()])
    return specs


def to_product(row, cutout):
    product = {"id": row["id"]}
    for col in COLUMNS[1:]:
        value = row[col]
        if col in LIST_COLUMNS:
            product[col] = [v.strip() for v in value.split("|") if v.strip()]
        elif col == "specs":
            product[col] = parse_specs(value)
        elif col == "featured":
            product[col] = value.lower() in ("1", "true", "yes", "y", "x")
        else:
            product[col] = value
    product["image"] = f"images/{row['id']}.webp"
    product["thumb"] = f"thumbs/{row['id']}.webp"
    product["cutout"] = cutout
    return product


def main():
    photos = {}
    if PHOTOS.exists():
        for p in sorted(PHOTOS.iterdir()):
            if p.suffix.lower() in PHOTO_EXTS:
                slug = slugify(p.stem)
                if slug in photos:
                    print(f"warning: {p.name} has the same id as {photos[slug].name}; skipped")
                    continue
                photos[slug] = p

    rendered = 0
    for slug, src in photos.items():
        rendered += render(src, IMAGES / f"{slug}.webp", IMAGE_MAX, 86)
        rendered += render(src, THUMBS / f"{slug}.webp", THUMB_MAX, 82)

    rows = read_csv()
    known = {r["id"] for r in rows}
    added = 0
    for slug in photos:
        if slug not in known:
            rows.append({c: "" for c in COLUMNS} | {
                "id": slug, "name": title_from_slug(slug), "category": "Uncategorized",
            })
            added += 1
    write_csv(rows)

    products, missing = [], []
    for row in rows:
        thumb = THUMBS / f"{row['id']}.webp"
        if (IMAGES / f"{row['id']}.webp").exists() and thumb.exists():
            products.append(to_product(row, has_alpha(thumb)))
        else:
            missing.append(row["id"])

    JS_PATH.write_text(
        "// Generated by tools/build_catalog.py from products.csv. Do not edit by hand.\n"
        "window.MARK_ONE_PRODUCTS = "
        + json.dumps(products, indent=2, ensure_ascii=False)
        + ";\n",
        encoding="utf-8",
    )

    print(f"{len(photos)} photos, {rendered} image files written, {added} new CSV rows")
    print(f"{len(products)} products written to {JS_PATH.name}")
    if missing:
        print(f"skipped (no image found): {', '.join(missing)}")


if __name__ == "__main__":
    main()
