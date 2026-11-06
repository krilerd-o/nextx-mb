"""Generate launcher / splash / web icons from assets/app_icon.png."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'assets' / 'app_icon.png'


def square_opaque(im: Image.Image) -> Image.Image:
    rgba = im.convert('RGBA')
    bg = Image.new('RGBA', rgba.size, (5, 4, 46, 255))
    return Image.alpha_composite(bg, rgba).convert('RGB')


def save_resized(im: Image.Image, path: Path, size: int, *, rgb: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    out = im.resize((size, size), Image.Resampling.LANCZOS)
    if rgb:
        out = out.convert('RGB')
    out.save(path, 'PNG')


def main() -> None:
    rounded = Image.open(SRC).convert('RGBA')
    square = square_opaque(rounded)

    android = {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192,
    }
    for folder, size in android.items():
        save_resized(
            square,
            ROOT / 'android' / 'app' / 'src' / 'main' / 'res' / folder / 'ic_launcher.png',
            size,
            rgb=True,
        )

    save_resized(
        rounded,
        ROOT / 'android' / 'app' / 'src' / 'main' / 'res' / 'drawable' / 'splash_icon.png',
        192,
        rgb=False,
    )

    ios_sizes = {
        'Icon-App-20x20@1x.png': 20,
        'Icon-App-20x20@2x.png': 40,
        'Icon-App-20x20@3x.png': 60,
        'Icon-App-29x29@1x.png': 29,
        'Icon-App-29x29@2x.png': 58,
        'Icon-App-29x29@3x.png': 87,
        'Icon-App-40x40@1x.png': 40,
        'Icon-App-40x40@2x.png': 80,
        'Icon-App-40x40@3x.png': 120,
        'Icon-App-60x60@2x.png': 120,
        'Icon-App-60x60@3x.png': 180,
        'Icon-App-76x76@1x.png': 76,
        'Icon-App-76x76@2x.png': 152,
        'Icon-App-83.5x83.5@2x.png': 167,
        'Icon-App-1024x1024@1x.png': 1024,
    }
    ios_dir = ROOT / 'ios' / 'Runner' / 'Assets.xcassets' / 'AppIcon.appiconset'
    for name, size in ios_sizes.items():
        save_resized(square, ios_dir / name, size, rgb=True)

    launch_dir = ROOT / 'ios' / 'Runner' / 'Assets.xcassets' / 'LaunchImage.imageset'
    save_resized(rounded, launch_dir / 'LaunchImage.png', 168, rgb=False)
    save_resized(rounded, launch_dir / 'LaunchImage@2x.png', 336, rgb=False)
    save_resized(rounded, launch_dir / 'LaunchImage@3x.png', 504, rgb=False)

    web = ROOT / 'web'
    save_resized(square, web / 'favicon.png', 48, rgb=True)
    save_resized(square, web / 'icons' / 'Icon-192.png', 192, rgb=True)
    save_resized(square, web / 'icons' / 'Icon-512.png', 512, rgb=True)
    save_resized(square, web / 'icons' / 'Icon-maskable-192.png', 192, rgb=True)
    save_resized(square, web / 'icons' / 'Icon-maskable-512.png', 512, rgb=True)

    print('generated launcher icons from', SRC)


if __name__ == '__main__':
    main()
