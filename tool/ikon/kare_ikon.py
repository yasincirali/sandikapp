"""Köşesiz (tam dolu) uygulama ikonu kaynakları — gönderilen ikonun geometrisinden.

Neden (2026-11-05, yasin: "store da app icon kötü gözüküyor"):
Eski ana kaynak `assets/images/sandik_icon.png` logoyu YUVARLAK KÖŞELİ bir
kare olarak, şeffaf kenar payıyla taşıyordu. Her platform ikona kendi
maskesini uyguladığı için köşe iki kez yuvarlanıyordu:
- iOS / App Store: `remove_alpha_ios` şeffaflığı #FCD35A ile doldurdu →
  sarı çerçevenin içinde ikinci bir yuvarlak kare ("ikon içinde ikon").
- Play mağaza simgesi: logo köşesi (r≈%23) Play maskesinden (r=%20) daha
  yuvarlak → üst köşelerde kahverengi dolgu hilali.
- Android adaptive: koyu yeşil (#0A1E15) zeminde, %16 içeriden ve zaten
  pay bırakılmış küçük bir turuncu kare → ikonun ~üçte biri.
Kural: ikon kaynağı KARE ve KENARA KADAR DOLU çizilir, köşeyi platform
yuvarlar. Bu betik tek kaynaktır; PIL dışında bağımlılık yok (Windows
makinesinde de koşar).

Çıktılar:
  tool/ikon/sandik_icon_kare.png      1024, RGB  → iOS ikon + Play 512 kaynağı
  tool/ikon/adaptive_arka.png         432, RGB   → Android adaptive zemin (degrade)
  tool/ikon/adaptive_on.png           432, RGBA  → Android adaptive ön (üç dalga)
  tool/ikon/adaptive_mono.png         432, RGBA  → Android 13 temalı ikon

Koşma:  python tool/ikon/kare_ikon.py  → sonra  dart run flutter_launcher_icons
"""

import math
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

# sandik_logo.svg ile aynı renkler.
UST = (0xFC, 0xD3, 0x5A)
ALT = (0xEA, 0xA1, 0x2B)
DALGALAR = [  # (taban y, renk) — SVG birimi, gen_icon.py ile aynı
    (160, (0xE2, 0x86, 0x1F)),
    (220, (0xC5, 0x63, 0x14)),
    (280, (0x99, 0x3D, 0x0A)),
]
# SVG'de görünen ikon alanı: clipPath rect x=y=64, 384 birim.
IKON_X0, IKON_BOY = 64, 384

SS = 4  # süper örnekleme (kenar yumuşatma)


def _y(taban, x):
    """Dalganın SVG x'indeki yüksekliği.

    Bugüne kadar cihazda ve mağazada görünen ikon `tool/gen_icon.py`
    çıktısıdır; o SVG'deki bezier'i değil kosinüs yaklaşımını kullanır
    (genlik 50, periyot 256, x=256'da tepe). Tanınan şekil o olduğu için
    burada da aynı formül: kullanıcı ikonu değişmiş sanmasın, yalnız
    köşe hatası gitsin. Periyodik olduğundan adaptive taşma payı doğal uzar.
    """
    return taban + 50 * math.cos(2 * math.pi * x / 256 + math.pi)


def _ciz(boy, svg_x0, svg_boy, zemin=True, dalga=True, alfa=False):
    """SVG'nin [svg_x0, svg_x0+svg_boy] karesini `boy` piksele çizer."""
    B = boy * SS
    k = B / svg_boy
    img = Image.new("RGBA", (B, B), (0, 0, 0, 0))
    if zemin:
        d = ImageDraw.Draw(img)
        for py in range(B):
            sy = svg_x0 + py / k
            # Degrade SVG'de rect'in kendi kutusuna (64..448) bağlı, dışı sabit.
            t = min(1.0, max(0.0, (sy - IKON_X0) / IKON_BOY))
            d.line([(0, py), (B, py)], fill=tuple(
                round(UST[i] + (ALT[i] - UST[i]) * t) for i in range(3)) + (255,))
    if dalga:
        d = ImageDraw.Draw(img)
        for taban, renk in DALGALAR:
            poli = []
            for px in range(0, B + SS, SS):
                sx = svg_x0 + px / k
                poli.append((px, (_y(taban, sx) - svg_x0) * k))
            poli += [(B, B), (0, B)]
            d.polygon(poli, fill=renk + (255,))
    img = img.resize((boy, boy), Image.LANCZOS)
    return img if alfa else img.convert("RGB")


def _mono(boy=432):
    """Temalı ikon (Android 13+): tek renk siluet. Üç dalga bandı, aralarında
    boşluk. Sistem rengi alfadan uygular. İçerik merkezdeki ~48dp'de
    (108dp'nin %44'ü) — temalı ikonlarda Google'ın önerdiği logo alanı."""
    B = boy * SS
    img = Image.new("L", (B, B), 0)
    d = ImageDraw.Draw(img)
    kenar = B * (1 - 0.44) / 2
    alan = B - 2 * kenar
    k = alan / 384  # SVG ikon karesi (64..448) → alan
    bosluk = 14  # SVG biriminde bantlar arası boşluk
    for i, (taban, _) in enumerate(DALGALAR):
        alt_taban = DALGALAR[i + 1][0] if i + 1 < len(DALGALAR) else None
        ust = []
        alt = []
        for j in range(0, 385, 2):
            sx = 64 + j
            ust.append((kenar + j * k, kenar + (_y(taban, sx) - 64) * k))
            yalt = (_y(alt_taban, sx) - bosluk) if alt_taban else 448
            alt.append((kenar + j * k, kenar + (yalt - 64) * k))
        d.polygon(ust + alt[::-1], fill=255)
    a = img.resize((boy, boy), Image.LANCZOS)
    out = Image.new("RGBA", (boy, boy), (255, 255, 255, 0))
    out.putalpha(a)
    return out


def main():
    # Mağaza / iOS: yalnız görünen ikon karesi, kenara kadar.
    kare = _ciz(1024, IKON_X0, IKON_BOY)
    kare.save(os.path.join(HERE, "sandik_icon_kare.png"))

    # Android adaptive: katman 108dp, maske içi 72dp. İkon karesi (384 birim)
    # ortadaki 72dp'ye otursun → 108dp = 576 birim, başlangıç 64 - 96 = -32.
    # Taşma payı yalnız paralaks/maske farkında görünür.
    x0, b = IKON_X0 - 96, 576
    _ciz(432, x0, b, dalga=False).save(os.path.join(HERE, "adaptive_arka.png"))
    _ciz(432, x0, b, zemin=False, alfa=True).save(os.path.join(HERE, "adaptive_on.png"))
    _mono().save(os.path.join(HERE, "adaptive_mono.png"))
    print("ikon kaynakları üretildi")


if __name__ == "__main__":
    main()
