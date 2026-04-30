#!/usr/bin/env python3
"""
スクショにマーケコピー (キャッチ + サブ) を上1/3 に半透明帯で合成する。

入力:  tools/screenshots/<lang>/<NN_name>.png
出力:  tools/output/<lang>/<NN_name>.png

使い方:
    python3 tools/screenshot_overlay.py
"""

import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).parent
SRC_DIR = ROOT / "screenshots"
OUT_DIR = ROOT / "output"

# キャッチコピー (ja/en/zh-Hans/zh-Hant/ko)
COPIES = {
    "01_home.png": {
        "ja": ("毎日の言葉で", "なりたい自分へ"),
        "en": ("Daily words", "for the you you want to be"),
        "zh-Hans": ("每日的话语", "塑造理想的自己"),
        "zh-Hant": ("每日的話語", "塑造理想的自己"),
        "ko":      ("매일의 말로", "되고 싶은 나로"),
    },
    "02_timeline.png": {
        "ja": ("みんなの願い", "24時間で天に流れる"),
        "en": ("Wishes from everyone", "Drift away in 24 hours"),
        "zh-Hans": ("大家的愿望", "24小时随风消散"),
        "zh-Hant": ("大家的願望", "24小時隨風消散"),
        "ko":      ("모두의 소원", "24시간 후 하늘로"),
    },
    "05_lang.png": {
        "ja": ("通知も声も", "あなた仕様に"),
        "en": ("Notifications & voice", "tailored for you"),
        "zh-Hans": ("通知与声音", "为你定制"),
        "zh-Hant": ("通知與聲音", "為你定制"),
        "ko":      ("알림도 목소리도", "당신만의 설정"),
    },
    "06_recording.png": {
        "ja": ("自分の声で", "潜在意識に届ける"),
        "en": ("Read aloud", "Reach your subconscious"),
        "zh-Hans": ("朗读出声", "传达潜意识"),
        "zh-Hant": ("朗讀出聲", "傳達潛意識"),
        "ko":      ("소리내어 읽기", "잠재의식에 닿다"),
    },
}

# 言語別フォントマッピング (macOS 標準)
FONTS = {
    "ja":      "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc",
    "en":      "/System/Library/Fonts/SFNS.ttf",
    "zh-Hans": "/System/Library/Fonts/PingFang.ttc",
    "zh-Hant": "/System/Library/Fonts/PingFang.ttc",
    "ko":      "/System/Library/Fonts/AppleSDGothicNeo.ttc",
}

# フォールバック
FALLBACK_FONT = "/System/Library/Fonts/Helvetica.ttc"


def load_font(lang: str, size: int):
    path = FONTS.get(lang, FALLBACK_FONT)
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        try:
            return ImageFont.truetype(FALLBACK_FONT, size)
        except Exception:
            return ImageFont.load_default()


def overlay(src_img: Path, headline: str, sub: str, lang: str) -> Image.Image:
    img = Image.open(src_img).convert("RGBA")
    W, H = img.size

    # 上1/3 に半透明グラデ帯
    band_h = int(H * 0.30)
    band = Image.new("RGBA", (W, band_h), (0, 0, 0, 0))
    bd = ImageDraw.Draw(band)
    for y in range(band_h):
        # 上ほど濃い
        alpha = int(180 * (1 - y / band_h * 0.4))
        bd.line([(0, y), (W, y)], fill=(20, 30, 60, alpha))
    img.paste(band, (0, 0), band)

    # テキスト描画
    headline_size = int(W * 0.075)  # 6.5"幅 1290 → 約97pt
    sub_size = int(W * 0.040)
    headline_font = load_font(lang, headline_size)
    sub_font = load_font(lang, sub_size)

    draw = ImageDraw.Draw(img)
    # 中央寄せ
    headline_w = draw.textlength(headline, font=headline_font)
    sub_w = draw.textlength(sub, font=sub_font)
    headline_y = int(H * 0.06)
    sub_y = headline_y + int(headline_size * 1.3)

    # 影
    for ox, oy in [(2, 2), (-2, -2), (2, -2), (-2, 2)]:
        draw.text(((W - headline_w) // 2 + ox, headline_y + oy),
                  headline, fill=(0, 0, 0, 200), font=headline_font)
        draw.text(((W - sub_w) // 2 + ox, sub_y + oy),
                  sub, fill=(0, 0, 0, 180), font=sub_font)
    # 本文
    draw.text(((W - headline_w) // 2, headline_y),
              headline, fill=(255, 255, 255, 255), font=headline_font)
    draw.text(((W - sub_w) // 2, sub_y),
              sub, fill=(255, 230, 180, 255), font=sub_font)

    return img.convert("RGB")


def main():
    OUT_DIR.mkdir(exist_ok=True, parents=True)

    # ja は素のスクショから 5 言語に複製生成 (撮影済 ja のみ前提)
    src_lang_dir = SRC_DIR / "ja"
    if not src_lang_dir.exists():
        src_lang_dir = SRC_DIR  # フラット配置 fallback

    files = sorted([f for f in COPIES.keys() if (src_lang_dir / f).exists()])
    if not files:
        print(f"⚠️  No source screenshots found in {src_lang_dir}")
        print(f"    Place 01_home.png ... 06_recording.png there")
        return

    for lang in ("ja", "en", "zh-Hans", "zh-Hant", "ko"):
        out_lang = OUT_DIR / lang
        out_lang.mkdir(exist_ok=True, parents=True)
        for fname in files:
            src = src_lang_dir / fname
            headline, sub = COPIES[fname][lang]
            img = overlay(src, headline, sub, lang)
            dst = out_lang / fname
            img.save(dst, "PNG", optimize=True)
            print(f"✅ {dst} ({headline}/{sub})")

    print(f"\n🎉 出力先: {OUT_DIR}")


if __name__ == "__main__":
    main()
