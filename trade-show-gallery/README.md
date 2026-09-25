# Mark One Trade Show Gallery

An interactive 3D product sphere for trade show screens and kiosks. Plain HTML, CSS and JavaScript with no libraries and no internet connection needed.

- **Sphere**: every product photo floats on a rotating sphere. Drag or swipe to spin it, and scroll or pinch to zoom. When nobody is touching it, it spins slowly on its own.
- **Sidebar**: search, filter chips (category, material, process, finish, industry) with live counts, and sliders for object size, sphere size and spin speed.
- **Detail view**: tap a product and it flies up to full size next to its description and specs. Use Previous and Next (or ← →) to step through the filtered products, and Esc to close.
- **Kiosk mode**: after 90 seconds with nobody touching the screen, the gallery closes the detail view, clears filters and goes back to spinning. You can change this in `config.js`.

## Run it

Open `index.html` in Chrome or Edge. For a booth, press F11 or use the full-screen button.

## Adding your photos

1. Put the original photos in `photos/`. Transparent PNG cut-outs work best, because they float on the sphere without a box. Regular JPGs show up as rounded cards.
   The file name becomes the product id, so `Eye Bolt 3in.png` becomes `eye-bolt-3in`.
2. Run the build script:
   ```
   pip install pillow
   python3 tools/build_catalog.py
   ```
   It trims and resizes each photo into `images/` (detail view) and `thumbs/` (sphere). It adds a row to `products.csv` for each new photo and regenerates `products.js`.
3. Fill in `products.csv` in Excel or Google Sheets (see below), then run the script again.

Re-running the script never overwrites rows you already edited in `products.csv`.

## products.csv columns

| Column | Notes |
| --- | --- |
| `id` | Photo file name, slugified. Don't change it. |
| `name` | Product name shown in the detail view. |
| `category`, `material`, `process`, `finish` | Each one becomes a filter group in the sidebar. |
| `industries`, `tags` | Several values separated by `|`. Tags are searchable but not shown as filters. |
| `description` | Paragraph shown in the detail view. |
| `specs` | `Label: value; Label: value`. Use `|` within a value for a list. |
| `featured` | `yes` puts the product first in its category order. |

To change which columns appear as sidebar filters, edit `filters` in `config.js`.

## Files

```
index.html              page layout
styles.css              styling (colors are variables at the top)
gallery.js              sphere rendering, interaction, filters, detail view
config.js               filters, idle reset, spin speed, tile fill for tiny catalogs
products.csv            product details (you edit this)
products.js             generated from products.csv, don't edit it
photos/                 original photos (not committed, see .gitignore)
images/, thumbs/        generated web images
tools/build_catalog.py  photo and catalog build script
```
