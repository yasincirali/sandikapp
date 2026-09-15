#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Play Console / App Store mağaza grafikleri üretici.

`build_screenshots.py` ekran görüntülerini üretir; bu betik onun
üretmediği İKİ zorunlu grafiği üretir:

    1. Uygulama ikonu    512x512   (Play: 32-bit PNG, ALFA YOK)
    2. Feature graphic  1024x500   (Play: zorunlu, alfa yok)

Neden betik, neden Canva değil: ikisi de markanın türevi (aynı palet, aynı
logo, aynı font). Elle çizilirse bir sonraki sürümde "hangi dosyadan
üretmiştik" sorusu doğar ve palet kayar. Betik kaynağı tek yerde tutar;
`assets/images/sandik_icon.png` değişirse ikisi de yeniden üretilir.

Kullanım:
    cd store_listing && python build_store_graphics.py

Çıktı: store_listing/android/graphics/
    icon_512.png              → Play Console "Uygulama simgesi"
    feature_graphic_1024x500.png → Play Console "Öne çıkan grafik"

⚠️ Play ikonu ALFA KANALI KABUL ETMEZ ve köşeleri kendi yuvarlar. Bu yüzden
kaynak RGBA ikon marka zemini üzerine düzleştiriliyor ve köşe yuvarlama
UYGULANMIYOR — iki kez yuvarlanmış köşe Play'de bozuk görünür.
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFont

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
# Çıktı Android'e özgü klasöre: ikon 512 ve feature graphic YALNIZCA
# Play Console alanlarıdır (App Store ikonu ipa içinden gelir, feature
# graphic'in App Store'da karşılığı yok). Mağaza başına tek klasör,
# Console'a yüklerken "hangi dosya hangi mağaza" sorusu doğmasın diye.
OUT = os.path.join(HERE, "android", "graphics")

SRC_ICON = os.path.join(ROOT, "assets", "images", "sandik_icon.png")
FONT_BOLD = os.path.join(ROOT, "assets", "fonts", "DMSans-Bold.ttf")
FONT_MED = os.path.join(ROOT, "assets", "fonts", "DMSans-Medium.ttf")

# sandık paleti — lib/theme/sandik.dart ve build_screenshots.py ile aynı.
BG_TOP = (10, 30, 21)
BG_BOTTOM = (6, 18, 13)
AMBER = (245, 166, 35)
TEXT = (255, 255, 255)
SUBTLE = (176, 190, 183)

# Feature graphic sloganı. PLAY_STORE_YAYIN_REHBERI.md §6.3'te önerilen
# metin; ürünün ne yaptığını tek cümlede söylüyor ve "kazanç vaat etme"
# tuzağına düşmüyor (finansal uygulama politikası).
SLOGAN = "Gerçek kâr/zarar, tek ekranda"
ALT_SLOGAN = "BIST · Fon · Döviz · Altın"


def dikey_gradyan(w: int, h: int) -> Image.Image:
    """Marka zemini: koyu yeşil, yukarıdan aşağı hafif koyulaşan."""
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        satir = tuple(
            int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3)
        )
        for x in range(w):
            px[x, y] = satir
    return img


def ikon_512() -> str:
    """Play 'Uygulama simgesi': 512x512, 32-bit PNG, alfa YOK.

    ⚠️ İki kez yuvarlanmış köşe tuzağı: kaynak PNG'nin köşeleri ZATEN
    yuvarlak ve dışı şeffaf. Şeffaflığı koyu zemine düzleştirince ikonun
    çevresinde koyu bir çerçeve kalıyor; Play kendi maskesini onun üstüne
    uygulayınca logonun kenarları kesiliyor ve çirkin bir halka doğuyor.

    Çözüm: opak pikselleri kırp (`getbbox`) ve tuvali TAM dolduracak
    şekilde ölçekle. Böylece Play'in maskesi logonun kendi köşesiyle
    çakışır, arada çerçeve kalmaz.
    """
    src = Image.open(SRC_ICON).convert("RGBA")

    # Şeffaf kenar payını at — geriye yalnızca logonun kendisi kalsın.
    kutu = src.getchannel("A").getbbox()
    if kutu:
        src = src.crop(kutu)

    # Kare değilse ortadan kare yap (ölçekleme logoyu ezmesin).
    if src.width != src.height:
        k = max(src.size)
        kare = Image.new("RGBA", (k, k), (0, 0, 0, 0))
        kare.paste(src, ((k - src.width) // 2, (k - src.height) // 2), src)
        src = kare

    src = src.resize((512, 512), Image.LANCZOS)

    # Alfayı düzleştir: Play alfa kanallı ikonu reddeder, şeffaf köşeler
    # Console'da siyah basılır. Zemin logonun kendi alt rengi — kırpma
    # sonrası görünür bir alan kalmıyor, yalnızca kenar yumuşatmasının
    # (anti-aliasing) yarı saydam pikselleri buna karışıyor.
    zemin = Image.new("RGB", (512, 512), (139, 69, 19))
    zemin.paste(src, (0, 0), src)

    yol = os.path.join(OUT, "icon_512.png")
    zemin.save(yol, "PNG")
    return yol


def feature_graphic() -> str:
    """Play 'Öne çıkan grafik': 1024x500, alfa yok.

    Yerleşim: solda logo, sağda iki satır metin. Play bu grafiği bazı
    yerleşimlerde kenarlardan kırptığı için her şey %8'lik güvenli
    kenar boşluğunun içinde tutuluyor.
    """
    W, H = 1024, 500
    img = dikey_gradyan(W, H)
    d = ImageDraw.Draw(img)

    guvenli = int(W * 0.08)

    # Sol: logo (alfasıyla, zemine karışsın).
    logo = Image.open(SRC_ICON).convert("RGBA")
    boy = 240
    logo = logo.resize((boy, boy), Image.LANCZOS)
    logo_x = guvenli
    logo_y = (H - boy) // 2
    img.paste(logo, (logo_x, logo_y), logo)

    # Sağ: marka adı + slogan.
    #
    # Punto seçimi ölçümle: ilk denemede 38pt slogan sağ güvenli kenarı
    # aşıyordu ("ekranda" kırpılma riski). Sabit punto yazmak yerine
    # metnin gerçek genişliğini ölçüp sığana kadar küçültüyoruz — slogan
    # ileride değişirse (SLOGAN sabiti) grafik sessizce bozulmasın.
    metin_x = logo_x + boy + 56
    kullanilabilir = W - guvenli - metin_x

    def sigan_font(yol: str, metin: str, baslangic: int, en_az: int):
        for punto in range(baslangic, en_az - 1, -2):
            f = ImageFont.truetype(yol, punto)
            if d.textlength(metin, font=f) <= kullanilabilir:
                return f
        return ImageFont.truetype(yol, en_az)

    f_ad = sigan_font(FONT_BOLD, "sandık", 88, 56)
    f_slogan = sigan_font(FONT_MED, SLOGAN, 36, 22)
    f_alt = sigan_font(FONT_MED, ALT_SLOGAN, 30, 20)

    # Dikey ortalama: üç satırın gerçek yüksekliğine göre, sabit y yerine.
    satirlar = [("sandık", f_ad, TEXT, 20), (SLOGAN, f_slogan, AMBER, 14),
                (ALT_SLOGAN, f_alt, SUBTLE, 0)]
    toplam = sum(
        (f.getbbox(t)[3] - f.getbbox(t)[1]) + bosluk for t, f, _, bosluk in satirlar
    )
    y = (H - toplam) // 2
    for t, f, renk, bosluk in satirlar:
        ust, alt = f.getbbox(t)[1], f.getbbox(t)[3]
        d.text((metin_x, y - ust), t, font=f, fill=renk)
        y += (alt - ust) + bosluk

    yol = os.path.join(OUT, "feature_graphic_1024x500.png")
    img.save(yol, "PNG")
    return yol


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for f in (SRC_ICON, FONT_BOLD, FONT_MED):
        if not os.path.exists(f):
            print(f"HATA: bulunamadi -> {f}")
            sys.exit(1)

    uretilen = [ikon_512(), feature_graphic()]
    print(f"{len(uretilen)} dosya uretildi -> {OUT}")
    for y in uretilen:
        im = Image.open(y)
        print(f"  + {os.path.basename(y):32s} {im.size[0]}x{im.size[1]} {im.mode}")


if __name__ == "__main__":
    main()
