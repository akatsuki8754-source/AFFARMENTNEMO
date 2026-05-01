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

# キャッチコピー (PAS + Cialdini 視点で全面リライト)
# - 1枚目: Problem (3日坊主問題) — 「変わりたい」のフック
# - 2枚目: Social proof (みんなの願い) — Cialdini 社会的証明
# - 3枚目: Authority (科学的根拠) — スタンフォード/NYU
# - 4枚目: Solution (30秒の音読) — Specific
COPIES = {
    "01_home.png": {
        "ja": ("3日坊主、終わりに。", "AIが3秒で言葉を作る"),
        "en": ("Quit quitting in 3 days.", "AI gives 3 picks in seconds"),
        "zh-Hans": ("3 天打鱼，告别。", "AI 3 秒给你 3 句"),
        "zh-Hant": ("3 天打魚，告別。", "AI 3 秒給你 3 句"),
        "ko":      ("3일 만에 끝, 이제 그만.", "AI가 3초에 3문장"),
    },
    "02_timeline.png": {
        "ja": ("ひとりじゃない。", "世界中の願いが、今日も流れる"),
        "en": ("You're not alone.", "Wishes from across the world"),
        "zh-Hans": ("你并不孤单。", "全世界的愿望，今天也在流"),
        "zh-Hant": ("你並不孤單。", "全世界的願望，今天也在流"),
        "ko":      ("혼자가 아닙니다.", "전 세계의 소원이 오늘도 흐른다"),
    },
    "05_lang.png": {
        "ja": ("科学が認めた習慣化。", "Stanford × NYU の理論を実装"),
        "en": ("Science-backed habit.", "Stanford + NYU research, implemented"),
        "zh-Hans": ("科学支持的习惯。", "实装 斯坦福 × 纽约大 研究"),
        "zh-Hant": ("科學支持的習慣。", "實裝 史丹佛 × 紐約大 研究"),
        "ko":      ("과학이 입증한 습관.", "스탠퍼드 × NYU 연구 구현"),
    },
    "06_recording.png": {
        "ja": ("30 秒で、自分が変わる。", "声に出すたび、行動が動く"),
        "en": ("30 sec to shift you.", "Speak it. Your action follows."),
        "zh-Hans": ("30 秒，重塑自己。", "出声朗读，行动随之改变"),
        "zh-Hant": ("30 秒，重塑自己。", "出聲朗讀，行動隨之改變"),
        "ko":      ("30 초로 자신이 바뀐다.", "소리 내면 행동도 따라온다"),
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

    # 上 35% にしっかり目立つグラデ帯 (旧 30% → 35%)
    band_h = int(H * 0.35)
    band = Image.new("RGBA", (W, band_h), (0, 0, 0, 0))
    bd = ImageDraw.Draw(band)
    for y in range(band_h):
        # 上ほど濃く、下にいくほど透明 (旧 alpha 180 → 220 で視認性↑)
        ratio = 1 - (y / band_h) * 0.55
        alpha = int(220 * ratio)
        bd.line([(0, y), (W, y)], fill=(15, 25, 55, alpha))
    img.paste(band, (0, 0), band)

    # テキスト描画 — フォントサイズ大幅増 (旧 7.5% → 10%, 旧 4% → 5.2%)
    headline_size = int(W * 0.10)   # 1290px → 129pt
    sub_size = int(W * 0.052)        # 1290px → 67pt
    headline_font = load_font(lang, headline_size)
    sub_font = load_font(lang, sub_size)

    draw = ImageDraw.Draw(img)
    headline_w = draw.textlength(headline, font=headline_font)
    sub_w = draw.textlength(sub, font=sub_font)
    headline_y = int(H * 0.05)
    sub_y = headline_y + int(headline_size * 1.25)

    # 強い影 (4方向 → 8方向、ぼかしなしで太く)
    shadow_offsets = [(3, 3), (-3, -3), (3, -3), (-3, 3),
                      (4, 0), (-4, 0), (0, 4), (0, -4)]
    for ox, oy in shadow_offsets:
        draw.text(((W - headline_w) // 2 + ox, headline_y + oy),
                  headline, fill=(0, 0, 0, 230), font=headline_font)
        draw.text(((W - sub_w) // 2 + ox, sub_y + oy),
                  sub, fill=(0, 0, 0, 200), font=sub_font)
    # 本文 (見出し: 純白 / サブ: 暖色アンバー — Cialdini "liking" 暖色)
    draw.text(((W - headline_w) // 2, headline_y),
              headline, fill=(255, 255, 255, 255), font=headline_font)
    draw.text(((W - sub_w) // 2, sub_y),
              sub, fill=(255, 220, 140, 255), font=sub_font)

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
