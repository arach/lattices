#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
IOS_ROOT = HERE.parent.parent
RAW = IOS_ROOT / ".artifacts" / "app-store-screenshots" / "raw-ipad"
OUTPUT = HERE / "ipad-pro-129"
ICON = IOS_ROOT / "Assets.xcassets" / "AppIcon.appiconset" / "Icon-App-1024x1024@1x.png"

WIDTH = 2064
HEIGHT = 2752
INK = (238, 237, 228)
MUTED = (158, 157, 149)
ACCENT = (130, 222, 133)
MONO_PATH = "/System/Library/Fonts/SFNSMono.ttf"
SANS_PATH = "/System/Library/Fonts/SFNS.ttf"

SLIDES = [
    {
        "file": "01-your-mac-at-your-fingertips.png",
        "source": "03-windows.png",
        "eyebrow": "LATS DECK · COCKPIT",
        "headline": "Your Mac.\nAt your fingertips.",
        "subtitle": "Press, talk, swipe, and undo from one tactile iPad cockpit.",
        "accent": (130, 222, 133),
        "brightness": 1.75,
    },
    {
        "file": "02-see-the-whole-fleet.png",
        "source": "01-home.png",
        "eyebrow": "LATS DECK · HOME",
        "headline": "See the whole fleet.\nAct in one tap.",
        "subtitle": "Machines, agents, scenes, routines, and live activity—at a glance.",
        "accent": (118, 177, 229),
    },
    {
        "file": "03-talk-your-mac-responds.png",
        "source": "05-voice.png",
        "eyebrow": "LATS DECK · VOICE",
        "headline": "Talk.\nYour Mac responds.",
        "subtitle": "Dictate, issue voice commands, and keep the live transcript in view.",
        "accent": (190, 151, 252),
    },
    {
        "file": "04-work-at-thought-speed.png",
        "source": "04-dev.png",
        "eyebrow": "LATS DECK · DEV",
        "headline": "Work at the speed\nof thought.",
        "subtitle": "Run builds, tests, terminals, Git actions, and logs from one surface.",
        "accent": (130, 222, 133),
    },
    {
        "file": "05-every-command-within-reach.png",
        "source": "02-command.png",
        "eyebrow": "LATS DECK · COMMAND",
        "headline": "Every command.\nWithin reach.",
        "subtitle": "Capture, search, launch agents, and reach everyday shortcuts in one deck.",
        "accent": (130, 222, 133),
        "brightness": 1.85,
    },
]


def font(path: str, size: int, index: int = 0) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size=size, index=index)


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, image.width, image.height), radius=radius, fill=255)
    result = image.convert("RGBA")
    result.putalpha(mask)
    return result


def gradient_background(accent: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGB", (WIDTH, HEIGHT), (7, 8, 9))
    pixels = image.load()
    for y in range(HEIGHT):
        vertical = y / HEIGHT
        for x in range(WIDTH):
            dx = (x - WIDTH * 0.82) / WIDTH
            dy = (y - HEIGHT * 0.10) / HEIGHT
            glow = max(0.0, 1.0 - (dx * dx + dy * dy) ** 0.5 / 0.68)
            base = 10 + int(5 * (1.0 - vertical))
            pixels[x, y] = tuple(
                min(255, base + int(channel * glow * 0.16)) for channel in accent
            )

    draw = ImageDraw.Draw(image, "RGBA")
    for x in range(-HEIGHT, WIDTH + HEIGHT, 128):
        draw.line((x, 0, x - HEIGHT, HEIGHT), fill=(255, 255, 255, 8), width=1)
    for y in range(0, HEIGHT, 128):
        draw.line((0, y, WIDTH, y), fill=(255, 255, 255, 6), width=1)
    draw.ellipse((1460, -420, 2260, 380), outline=(*accent, 32), width=2)
    draw.ellipse((1550, -330, 2170, 290), outline=(*accent, 20), width=2)
    return image


def fit_text(draw: ImageDraw.ImageDraw, value: str, max_width: int, start: int) -> ImageFont.FreeTypeFont:
    size = start
    while size > 48:
        candidate = font(SANS_PATH, size)
        bounds = draw.multiline_textbbox((0, 0), value, font=candidate, spacing=4)
        if bounds[2] - bounds[0] <= max_width:
            return candidate
        size -= 2
    return font(SANS_PATH, size)


def render(slide: dict[str, object]) -> None:
    accent = slide["accent"]
    canvas = gradient_background(accent)
    draw = ImageDraw.Draw(canvas, "RGBA")

    eyebrow_font = font(MONO_PATH, 28)
    headline_font = fit_text(draw, str(slide["headline"]), WIDTH - 220, 116)
    subtitle_font = font(SANS_PATH, 38)
    number_font = font(MONO_PATH, 23)

    draw.text((112, 112), str(slide["eyebrow"]), font=eyebrow_font, fill=accent, stroke_width=0)
    draw.text((WIDTH - 112, 118), f"{SLIDES.index(slide) + 1:02d} / {len(SLIDES):02d}", font=number_font, fill=(124, 124, 119), anchor="ra")
    draw.multiline_text((108, 220), str(slide["headline"]), font=headline_font, fill=INK, spacing=0)
    draw.text((112, 535), str(slide["subtitle"]), font=subtitle_font, fill=MUTED)

    source_path = RAW / str(slide["source"])
    if not source_path.exists():
        raise FileNotFoundError(f"Missing raw screenshot: {source_path}")

    screen = Image.open(source_path).convert("RGB")
    screen = ImageEnhance.Brightness(screen).enhance(float(slide.get("brightness", 1.32)))
    screen = ImageEnhance.Contrast(screen).enhance(1.08)

    frame_width = 1260
    frame_height = 1680
    screen.thumbnail((frame_width, frame_height), Image.Resampling.LANCZOS)
    screen = rounded(screen, 36)

    frame_x = (WIDTH - screen.width) // 2
    frame_y = 720
    shadow = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (frame_x - 12, frame_y + 18, frame_x + screen.width + 12, frame_y + screen.height + 50),
        radius=48,
        fill=(0, 0, 0, 210),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(42))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow)

    rim = Image.new("RGBA", (screen.width + 28, screen.height + 28), (0, 0, 0, 0))
    rim_draw = ImageDraw.Draw(rim)
    rim_draw.rounded_rectangle((0, 0, rim.width - 1, rim.height - 1), radius=48, fill=(27, 28, 28), outline=(114, 114, 105, 130), width=2)
    canvas.alpha_composite(rim, (frame_x - 14, frame_y - 14))
    canvas.alpha_composite(screen, (frame_x, frame_y))

    draw = ImageDraw.Draw(canvas, "RGBA")
    rule_y = 2450
    draw.line((112, rule_y, WIDTH - 112, rule_y), fill=(255, 255, 255, 28), width=1)
    icon = Image.open(ICON).convert("RGBA").resize((116, 116), Image.Resampling.LANCZOS)
    canvas.alpha_composite(rounded(icon, 26), (112, 2510))
    draw.text((258, 2522), "LATS DECK", font=font(MONO_PATH, 29), fill=INK)
    draw.text((258, 2570), "A cockpit for your Mac, on your iPad.", font=font(SANS_PATH, 34), fill=MUTED)
    draw.text((WIDTH - 112, 2558), "LATS.DEV", font=font(MONO_PATH, 26), fill=accent, anchor="ra")

    output_path = OUTPUT / str(slide["file"])
    canvas.convert("RGB").save(output_path, format="PNG", optimize=True)


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for existing in OUTPUT.glob("*.png"):
        existing.unlink()
    for slide in SLIDES:
        render(slide)
    print(f"Rendered {len(SLIDES)} App Store screenshots to {OUTPUT}")


if __name__ == "__main__":
    main()
