#!/usr/bin/env python3
"""Mood-Ring Weather: App Icon Generator (v6-03 Aurora Atmos).

仕様は .claude-memory/mrw-app-icon-decision.md および spec.md §17.7 を参照。
1024×1024 のマスターをまず生成し、iOS / Android の全サイズへ書き出す。

依存: Pillow, numpy
    pip install --break-system-packages Pillow numpy
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# ---------------------------------------------------------------------------
# パス
# ---------------------------------------------------------------------------
ROOT = Path(__file__).resolve().parent.parent
IOS_APPICON_DIR = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"
DOCS_DIR = ROOT / "docs" / "branding"
MASTER_PATH = DOCS_DIR / "app_icon_master_1024.png"


# ---------------------------------------------------------------------------
# 色定義 (spec §17.7)
# ---------------------------------------------------------------------------
BG_BASE = (14, 18, 48)  # #0E1230

# 大気ブロブ 4 層 (RGB, position xy in 0..1, radius scale)
BLOBS = [
    ((93, 202, 165), (0.22, 0.28), 0.55),  # 緑 #5DCAA5  top-left
    ((127, 119, 221), (0.78, 0.72), 0.58),  # 紫 #7F77DD  bottom-right
    ((244, 165, 184), (0.30, 0.78), 0.50),  # 桃 #F4A5B8  bottom-left
    ((255, 213, 128), (0.74, 0.24), 0.48),  # 金 #FFD580  top-right
]

# リング角度グラデ (4 stops, 5 色 — 最後は最初に戻る)
RING_STOPS = [
    (0, (92, 199, 158)),   # teal #5CC79E
    (90, (158, 217, 115)),  # lime #9ED973
    (180, (245, 217, 92)),  # yellow #F5D95C
    (270, (240, 140, 107)),  # coral #F08C6B
    (360, (92, 199, 158)),  # teal back to start
]

MASTER_SIZE = 1024
RING_CENTER = (MASTER_SIZE / 2, MASTER_SIZE / 2)
RING_RADIUS_OUTER = 400  # 直径 800 = リング外径
RING_STROKE = 88         # spec の 44 × 2 (Figma 原本 512 → 1024)
RING_RADIUS_INNER = RING_RADIUS_OUTER - RING_STROKE


# ---------------------------------------------------------------------------
# ヘルパ
# ---------------------------------------------------------------------------
def _lerp(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def _angle_color(deg: float) -> tuple[int, int, int]:
    """0〜360 を受け、RING_STOPS から線形補間した色を返す。"""
    deg = deg % 360
    for i in range(len(RING_STOPS) - 1):
        a_deg, a_col = RING_STOPS[i]
        b_deg, b_col = RING_STOPS[i + 1]
        if a_deg <= deg <= b_deg:
            t = (deg - a_deg) / (b_deg - a_deg) if b_deg > a_deg else 0
            return _lerp(a_col, b_col, t)
    return RING_STOPS[0][1]


# ---------------------------------------------------------------------------
# 描画
# ---------------------------------------------------------------------------
def _draw_background() -> Image.Image:
    img = Image.new("RGB", (MASTER_SIZE, MASTER_SIZE), BG_BASE)

    # 各ブロブを別レイヤに描き、強くブラーしてから合成する
    for color, (cx_ratio, cy_ratio), r_ratio in BLOBS:
        layer = Image.new("RGBA", (MASTER_SIZE, MASTER_SIZE), (0, 0, 0, 0))
        draw = ImageDraw.Draw(layer)
        cx = int(cx_ratio * MASTER_SIZE)
        cy = int(cy_ratio * MASTER_SIZE)
        r = int(r_ratio * MASTER_SIZE / 2)
        # アルファを段階的に下げた重ね塗りで放射状に見せる
        for step, frac in enumerate([1.0, 0.85, 0.7, 0.55, 0.4]):
            rr = int(r * frac)
            alpha = 90 if step == 0 else 60
            draw.ellipse(
                (cx - rr, cy - rr, cx + rr, cy + rr),
                fill=(*color, alpha),
            )
        # 強いガウシアンブラーで大気のように
        layer = layer.filter(ImageFilter.GaussianBlur(radius=260))
        img = Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")

    return img


def _draw_ring(base: Image.Image) -> Image.Image:
    """角度グラデのリングを描いて合成。"""
    size = MASTER_SIZE
    cx, cy = RING_CENTER

    # 角度マップを numpy で生成
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    dx = xx - cx
    dy = yy - cy
    dist = np.sqrt(dx * dx + dy * dy)
    # 12 時方向を 0° とし時計回り
    ang = (np.degrees(np.arctan2(dx, -dy)) + 360.0) % 360.0

    # 角度→色 LUT を 360 ステップで作る
    lut = np.array([_angle_color(d) for d in range(360)], dtype=np.uint8)
    ang_int = ang.astype(np.int32) % 360
    rgb = lut[ang_int]  # (H, W, 3)

    # リング領域マスク (アンチエイリアス: 端 1px をぼかす)
    outer = RING_RADIUS_OUTER
    inner = RING_RADIUS_INNER
    soft = 1.5  # ピクセル幅のエッジソフト化

    alpha_outer = np.clip((outer - dist) / soft, 0.0, 1.0)
    alpha_inner = np.clip((dist - inner) / soft, 0.0, 1.0)
    alpha = alpha_outer * alpha_inner  # 0..1
    alpha_u8 = (alpha * 255).astype(np.uint8)

    ring_rgba = np.dstack([rgb, alpha_u8])
    ring_img = Image.fromarray(ring_rgba, mode="RGBA")

    # 微発光: リング外側に淡いハロー
    halo = ring_img.copy().filter(ImageFilter.GaussianBlur(radius=18))
    halo_arr = np.array(halo)
    halo_arr[..., 3] = (halo_arr[..., 3].astype(np.float32) * 0.35).astype(np.uint8)
    halo_img = Image.fromarray(halo_arr, mode="RGBA")

    result = base.convert("RGBA")
    result = Image.alpha_composite(result, halo_img)
    result = Image.alpha_composite(result, ring_img)
    return result.convert("RGB")


def build_master() -> Image.Image:
    DOCS_DIR.mkdir(parents=True, exist_ok=True)
    bg = _draw_background()
    final = _draw_ring(bg)
    final.save(MASTER_PATH, "PNG", optimize=True)
    print(f"[master] {MASTER_PATH.relative_to(ROOT)} written ({final.size})")
    return final


# ---------------------------------------------------------------------------
# 出力サイズ表
# ---------------------------------------------------------------------------
IOS_FILES = {
    # filename : (px)
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

ANDROID_LEGACY = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

ANDROID_ADAPTIVE_FG = {
    # foreground 432×432 を full canvas、内側 66dp 安全領域にリング
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}


def _resize(master: Image.Image, px: int) -> Image.Image:
    return master.resize((px, px), Image.LANCZOS)


def write_ios(master: Image.Image) -> None:
    IOS_APPICON_DIR.mkdir(parents=True, exist_ok=True)
    for name, px in IOS_FILES.items():
        out = IOS_APPICON_DIR / name
        _resize(master, px).save(out, "PNG", optimize=True)
    print(f"[ios] {len(IOS_FILES)} files written to {IOS_APPICON_DIR.relative_to(ROOT)}")


def write_android(master: Image.Image) -> None:
    # 1. legacy ic_launcher.png (full bleed square — system が丸/角丸を切る)
    for folder, px in ANDROID_LEGACY.items():
        out = ANDROID_RES / folder / "ic_launcher.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        _resize(master, px).save(out, "PNG", optimize=True)
        # round 版は同じ画像 (system がマスク)
        _resize(master, px).save(ANDROID_RES / folder / "ic_launcher_round.png", "PNG", optimize=True)

    # 2. adaptive icon: foreground にリング+大気 (full canvas), background は単色
    for folder, px in ANDROID_ADAPTIVE_FG.items():
        out = ANDROID_RES / folder / "ic_launcher_foreground.png"
        # adaptive icon は 108dp canvas で内側 66dp が visible → 中心 60% にリングが収まるよう
        # master 自体が中央 78% に収まっているのでそのまま縮小で OK
        _resize(master, px).save(out, "PNG", optimize=True)

    # 3. mipmap-anydpi-v26 で adaptive 定義
    anydpi = ANDROID_RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    adaptive_xml = (
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        "<adaptive-icon xmlns:android=\"http://schemas.android.com/apk/res/android\">\n"
        "    <background android:drawable=\"@color/ic_launcher_background\"/>\n"
        "    <foreground android:drawable=\"@mipmap/ic_launcher_foreground\"/>\n"
        "</adaptive-icon>\n"
    )
    (anydpi / "ic_launcher.xml").write_text(adaptive_xml, encoding="utf-8")
    (anydpi / "ic_launcher_round.xml").write_text(adaptive_xml, encoding="utf-8")

    # 4. background 単色 (#0E1230)
    colors_dir = ANDROID_RES / "values"
    colors_dir.mkdir(parents=True, exist_ok=True)
    colors_xml = colors_dir / "ic_launcher_background.xml"
    colors_xml.write_text(
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        "<resources>\n"
        "    <color name=\"ic_launcher_background\">#0E1230</color>\n"
        "</resources>\n",
        encoding="utf-8",
    )

    print(f"[android] legacy + adaptive icons written to {ANDROID_RES.relative_to(ROOT)}")


def update_ios_contents_json() -> None:
    """既存 Contents.json は維持されているが念のため整合性チェックして書き直す。"""
    contents = {
        "images": [],
        "info": {"version": 1, "author": "xcode"},
    }
    spec = [
        ("iphone", "20x20", "2x", "Icon-App-20x20@2x.png"),
        ("iphone", "20x20", "3x", "Icon-App-20x20@3x.png"),
        ("iphone", "29x29", "1x", "Icon-App-29x29@1x.png"),
        ("iphone", "29x29", "2x", "Icon-App-29x29@2x.png"),
        ("iphone", "29x29", "3x", "Icon-App-29x29@3x.png"),
        ("iphone", "40x40", "2x", "Icon-App-40x40@2x.png"),
        ("iphone", "40x40", "3x", "Icon-App-40x40@3x.png"),
        ("iphone", "60x60", "2x", "Icon-App-60x60@2x.png"),
        ("iphone", "60x60", "3x", "Icon-App-60x60@3x.png"),
        ("ipad", "20x20", "1x", "Icon-App-20x20@1x.png"),
        ("ipad", "20x20", "2x", "Icon-App-20x20@2x.png"),
        ("ipad", "29x29", "1x", "Icon-App-29x29@1x.png"),
        ("ipad", "29x29", "2x", "Icon-App-29x29@2x.png"),
        ("ipad", "40x40", "1x", "Icon-App-40x40@1x.png"),
        ("ipad", "40x40", "2x", "Icon-App-40x40@2x.png"),
        ("ipad", "76x76", "1x", "Icon-App-76x76@1x.png"),
        ("ipad", "76x76", "2x", "Icon-App-76x76@2x.png"),
        ("ipad", "83.5x83.5", "2x", "Icon-App-83.5x83.5@2x.png"),
        ("ios-marketing", "1024x1024", "1x", "Icon-App-1024x1024@1x.png"),
    ]
    for idiom, size, scale, name in spec:
        contents["images"].append(
            {"size": size, "idiom": idiom, "filename": name, "scale": scale}
        )
    (IOS_APPICON_DIR / "Contents.json").write_text(
        json.dumps(contents, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    master = build_master()
    write_ios(master)
    update_ios_contents_json()
    write_android(master)
    print("\nDone. Aurora Atmos icon installed across iOS + Android.")


if __name__ == "__main__":
    main()
