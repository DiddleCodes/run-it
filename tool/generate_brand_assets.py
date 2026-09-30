#!/usr/bin/env python3
"""Task 76: derive every RUN-It brand asset from the three design sources.

Sources (as delivered — flattened onto white, no transparency):
  design/branding/source/run_it_app_icon.png          maroon rounded square + grey arrow
  design/branding/source/run_it_wordmark_stacked.png  gold swoosh over "RUN iT"
  design/branding/source/run_it_wordmark_horizontal.jpg  "RUN iT" alone

Everything is keyed off the white background against the brand's exact
colours (never a blind threshold), so edges stay smooth, and nothing is ever
upscaled past its source resolution. The rounded mark is re-rendered at 4x
and downsampled so its corners stay crisp. Re-run after changing a source:

  python3 tool/generate_brand_assets.py
  dart run flutter_launcher_icons
  dart run flutter_native_splash:create   # then re-apply the iOS notes in
                                          # LaunchScreen.storyboard

Requires Pillow.
"""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "design/branding/source"

WHITE = (255, 255, 255)
BRAND_MAROON = (0x59, 0x0E, 0x25)  # wordmark text; = AppColors.primaryMaroonDeep
ICON_MAROON = (0x4F, 0x0B, 0x20)  # the app-icon square
ICON_MAROON_LIGHT = (0x6E, 0x22, 0x3A)  # its top-left highlight
GOLD = (0xD9, 0x9A, 0x18)  # = AppColors.gold
ARROW_GREY = (0xBE, 0xBE, 0xBE)
CREAM = (0xFB, 0xF4, 0xE9)  # = AppColors.backgroundCream / onMaroon


def matte(img, inks):
    """Separate [inks] from a white background.

    Returns a list of (ink_index, alpha 0..1) per pixel: for each pixel the ink
    that best explains it as `white*(1-a) + ink*a`, with that least-squares a.
    """
    out = []
    for p in img.convert("RGB").getdata():
        best = None
        for i, ink in enumerate(inks):
            d = [w - f for w, f in zip(WHITE, ink)]
            v = [w - c for w, c in zip(WHITE, p)]
            a = max(0.0, min(1.0, sum(x * y for x, y in zip(v, d)) / sum(x * x for x in d)))
            err = sum((w - a * dd - c) ** 2 for w, dd, c in zip(WHITE, d, p))
            if best is None or err < best[2]:
                best = (i, a, err)
        out.append((best[0], best[1] if best[1] > 0.02 else 0.0))
    return out


def recolour(size, matted, colours):
    """Build an RGBA image: each pixel takes colours[ink] at its alpha."""
    img = Image.new("RGBA", size)
    img.putdata([(*colours[i], round(a * 255)) for i, a in matted])
    return img


def trim(img, pad=0):
    box = img.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    img = img.crop(box)
    if pad:
        canvas = Image.new("RGBA", (img.width + 2 * pad, img.height + 2 * pad))
        canvas.alpha_composite(img, (pad, pad))
        img = canvas
    return img


def fit(img, box_w, box_h):
    """Scale down (never up) to fit inside box_w x box_h."""
    s = min(box_w / img.width, box_h / img.height, 1.0)
    return img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)


def centred(canvas_size, img, fill=(0, 0, 0, 0), dy=0):
    canvas = Image.new("RGBA", canvas_size, fill)
    canvas.alpha_composite(img, ((canvas_size[0] - img.width) // 2, (canvas_size[1] - img.height) // 2 + dy))
    return canvas


def gradient_square(size, radius=0):
    """Icon-maroon tile with the source's soft top-left highlight.

    The gradient is smooth, so it's drawn at 1x; only the rounded corners
    are drawn at 4x and downsampled, which is what keeps them crisp.
    """
    w, h = size
    # t = 0 at the top-left corner, reaching 1 by ~45% of the way across the
    # diagonal: the average of a left->right and a top->bottom ramp.
    down = Image.linear_gradient("L")
    across = down.transpose(Image.Transpose.ROTATE_90)
    diagonal = ImageChops.add(down, across, scale=2.0)
    t = diagonal.point(lambda v: min(255, round(v / 0.45))).resize((w, h), Image.BILINEAR)
    tile = Image.composite(
        Image.new("RGBA", size, ICON_MAROON + (255,)),
        Image.new("RGBA", size, ICON_MAROON_LIGHT + (255,)),
        t,
    )
    if radius:
        s = 4
        mask = Image.new("L", (w * s, h * s), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, w * s - 1, h * s - 1), radius=radius * s, fill=255)
        tile.putalpha(mask.resize(size, Image.LANCZOS))
    return tile


def save(img, rel):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)
    print(f"  {rel}  {img.width}x{img.height}")


def main():
    stacked = Image.open(SRC / "run_it_wordmark_stacked.png")
    horizontal = Image.open(SRC / "run_it_wordmark_horizontal.jpg")

    # Stacked lockup (gold swoosh + maroon text), and the swoosh on its own.
    m = matte(stacked, [BRAND_MAROON, GOLD])
    lockup = trim(recolour(stacked.size, m, [BRAND_MAROON, GOLD]), pad=8)
    # The swoosh is the gold ABOVE the lettering — the dot on the "i" is gold
    # too and must not come along with it.
    text_top = min(k // stacked.width for k, (i, a) in enumerate(m) if i == 0 and a > 0.5)
    swoosh_only = recolour(
        stacked.size,
        [(i, a if i == 1 and k // stacked.width < text_top - 4 else 0.0) for k, (i, a) in enumerate(m)],
        [BRAND_MAROON, GOLD],
    )
    swoosh = trim(swoosh_only)
    arrow_mask = swoosh.getchannel("A")  # the arrow shape, as alpha

    def arrow(colour, width):
        glyph = Image.new("RGBA", swoosh.size, colour + (0,))
        glyph.putalpha(arrow_mask)
        return fit(glyph, width, width)

    # Horizontal "RUN iT", on light and on maroon backgrounds.
    mh = matte(horizontal, [BRAND_MAROON, GOLD])
    horiz = trim(recolour(horizontal.size, mh, [BRAND_MAROON, GOLD]), pad=4)
    horiz_dark = trim(recolour(horizontal.size, mh, [CREAM, GOLD]), pad=4)

    # The app icon: a full-bleed square (iOS masks its own corners; no white
    # may show), arrow at ~60% width, optically centred.
    icon = gradient_square((1024, 1024))
    a = arrow(ARROW_GREY, 620)
    icon.alpha_composite(a, ((1024 - a.width) // 2, (1024 - a.height) // 2 + 8))
    icon = icon.convert("RGB")

    # Android adaptive foreground: arrow alone inside the 66dp/108dp safe
    # circle (the OS draws the maroon background and masks the shape).
    foreground = centred((1024, 1024), arrow(ARROW_GREY, 500), dy=6)

    # The rounded mark as the designer drew it (744x658 in the source),
    # re-rendered crisply — dashboard favicon/header, Android 12 splash.
    def rounded_mark(width):
        h = round(width * 658 / 744)
        tile = gradient_square((width, h), radius=round(width * 0.2))
        g = arrow(ARROW_GREY, round(width * 0.75))
        tile.alpha_composite(g, ((width - g.width) // 2, (h - g.height) // 2 + round(width * 0.02)))
        return tile

    print("Brand assets:")
    save(lockup, "assets/branding/run_it_wordmark.png")
    save(horiz, "assets/branding/run_it_wordmark_horizontal.png")
    save(horiz_dark, "assets/branding/run_it_wordmark_horizontal_on_dark.png")
    save(arrow(CREAM, 512), "assets/branding/run_it_mark.png")
    save(icon, "assets/branding/run_it_app_icon.png")

    print("Launcher icon + splash inputs:")
    save(icon, "assets/icons/app_icon.png")
    save(foreground, "assets/icons/app_icon_foreground.png")
    # Native splash (iOS + Android < 12): the stacked lockup at its source
    # resolution — flutter_native_splash treats it as xxxhdpi (4x).
    save(lockup, "assets/icons/splash_icon.png")
    # Android 12+ crops the splash icon to a circle (768px of 1152px):
    # the rounded mark, small enough that its corners stay inside it.
    save(centred((1152, 1152), rounded_mark(560)), "assets/icons/splash_icon_android12.png")

    # iOS launch image, hand-exported (see LaunchScreen.storyboard): the
    # lockup at 220pt wide, downsampled straight from source for each scale.
    for scale, suffix in ((1, ""), (2, "@2x"), (3, "@3x")):
        w = 220 * scale
        save(lockup.resize((w, round(lockup.height * w / lockup.width)), Image.LANCZOS),
             f"ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png")

    # Android status-bar notification icon: Android draws only the alpha
    # channel (white), tinted by default_notification_color. 24dp per density.
    print("Android notification icon:")
    for density, px in (("mdpi", 24), ("hdpi", 36), ("xhdpi", 48), ("xxhdpi", 72), ("xxxhdpi", 96)):
        save(centred((px, px), arrow((255, 255, 255), round(px * 0.9))),
             f"android/app/src/main/res/drawable-{density}/ic_stat_run_it.png")

    print("Dashboard:")
    mark512 = rounded_mark(512)
    save(mark512, "dashboard/public/brand/run-it-icon.png")
    save(centred((512, 512), mark512), "dashboard/app/icon.png")


if __name__ == "__main__":
    main()
