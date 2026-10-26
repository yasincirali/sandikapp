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

Çıktı: docs/img/ (2026-10-26, web paylaşım kartı, 1200x630, <300 KB)
    og-ana.png                → docs/index.html og:image
    og-enflasyon.png          → docs/enflasyon/index.html og:image
Aynı betikte çünkü aynı türev: palet, logo, font. Yalnız web görselleri
için: `python build_store_graphics.py --og`.

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

# Feature graphic sloganı.
#
# 2026-09-16: "Gerçek kâr/zarar, tek ekranda" → enflasyon ekseni.
#
# Eski slogan doğruydu ama AYIRT EDİCİ değildi: her portföy uygulaması
# "kâr/zararını gör" der. Galeri set_c ve önizleme videosu artık tek bir
# iddia etrafında kuruldu — TÜFE'ye göre reel getiri — ve feature graphic
# onlarla aynı şeyi söylemeli. Mağaza sayfasında üç yüzey (grafik, galeri,
# video) farklı vaat verirse kullanıcı ne aldığını anlamaz.
#
# "Kazanç vaat etme" tuzağına düşmüyor (Play finansal uygulama politikası):
# soru soruyor, getiri sözü vermiyor.
SLOGAN = "Enflasyonu geçtin mi?"
ALT_SLOGAN = "BIST · Fon · Döviz · Altın — TÜFE ile yan yana"


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


# ── Web paylaşım kartları (og:image) ────────────────────────────────────────
# 2026-10-26. Eskiden og:image kare uygulama ikonuydu; WhatsApp/X/LinkedIn
# 1.91:1 kartı kırpıp bulanık küçük bir kare gösteriyordu. 1200x630 her
# platformun "büyük kart" ölçüsü (twitter:card summary_large_image).
#
# Kurallar:
# - Rakam YOK. Ne gerçek kullanıcı verisi ne "örnek" sayı: kart sayfadan
#   koparılıp tek başına dolaşır, "örnek" notu onunla gitmez; görsel bir
#   getiri vaadi gibi okunur (Play finansal politika + uydurma sayı yasak).
# - Başlık sayfanın og:title'ıyla AYNI cümle: önizlemede başlık ile görsel
#   iki farklı vaat vermesin.
# - İmza öğesi: logodaki üç amber dalga (sandik_logo.svg geometrisi,
#   periyot 256, genlik 25 birim). Sayfadaki "sandık katmanları"nın eşi.
# - <300 KB: WhatsApp 300 KB üstü önizlemeyi düşürüyor. Bunun için palet
#   kuantalama (gradyan + dalga birkaç düz renktir, kayıp görünmez).
OG_OUT = os.path.join(ROOT, "docs", "img")
OG_W, OG_H = 1200, 630
OG_SINIR = 300 * 1024
# Logodaki dalga renkleri (sandik_logo.svg), üstten alta.
DALGA = [(226, 134, 31), (197, 99, 20), (153, 61, 10)]
OG_KARTLAR = [
    # (dosya, başlık, alt satır) — başlık = sayfanın og:title'ı.
    ("og-ana.png", "Birikimin tek ekranda",
     "Hisse, fon, döviz, altın ve BES bir arada"),
    ("og-enflasyon.png", "Param enflasyona karşı ne oldu?",
     "TÜİK TÜFE endeksiyle bugünkü karşılığı"),
]


def _dalga_katmani(img: Image.Image, taban_y: int, renk, alfa: int,
                   faz: float) -> None:
    """Logodaki S-eğrisi dalganın düz bant hâli, tuvalin altına."""
    import math

    katman = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(katman)
    # SVG'de periyot 256/512 genişlik, genlik 25/512 → tuvale ölçekli.
    periyot = OG_W / 2
    genlik = OG_W * 25 / 512 / 2
    noktalar = [
        (x, taban_y + genlik * (1 - math.cos(2 * math.pi * (x / periyot) + faz)))
        for x in range(0, OG_W + 1, 4)
    ]
    noktalar += [(OG_W, OG_H), (0, OG_H)]
    d.polygon(noktalar, fill=(*renk, alfa))
    img.alpha_composite(katman)


def og_kart(dosya: str, baslik: str, alt: str) -> str:
    img = dikey_gradyan(OG_W, OG_H).convert("RGBA")

    # Dalgalar: alt üçte birde, yavaşça koyulaşan üç bant. Opaklık düşük
    # tutulur ki metinle yarışmasın; imza, dikkat çekici süs değil.
    for i, renk in enumerate(DALGA):
        _dalga_katmani(img, 520 + i * 30, renk, 50 + i * 35, faz=i * 0.9)

    d = ImageDraw.Draw(img)
    kenar = 80

    # Üst sol: logo + "sandık" kelime markası.
    logo = Image.open(SRC_ICON).convert("RGBA")
    kutu = logo.getchannel("A").getbbox()
    if kutu:
        logo = logo.crop(kutu)
    boy = 88
    logo = logo.resize((boy, boy), Image.LANCZOS)
    img.alpha_composite(logo, (kenar, kenar))
    f_marka = ImageFont.truetype(FONT_BOLD, 52)
    ust, alt_ = f_marka.getbbox("sandık")[1], f_marka.getbbox("sandık")[3]
    d.text((kenar + boy + 24, kenar + (boy - (alt_ - ust)) // 2 - ust),
           "sandık", font=f_marka, fill=TEXT)

    # Başlık: sığana kadar küçülen punto, gerekirse iki satır.
    kullanilabilir = OG_W - 2 * kenar

    def satirlara_bol(metin: str, f) -> list:
        kelimeler, satirlar, simdiki = metin.split(), [], ""
        for k in kelimeler:
            aday = f"{simdiki} {k}".strip()
            if d.textlength(aday, font=f) <= kullanilabilir:
                simdiki = aday
            else:
                satirlar.append(simdiki)
                simdiki = k
        satirlar.append(simdiki)
        return satirlar

    for punto in range(84, 47, -4):
        f_baslik = ImageFont.truetype(FONT_BOLD, punto)
        satirlar = satirlara_bol(baslik, f_baslik)
        if len(satirlar) <= 2:
            break
    satir_y = int(punto * 1.12)
    y = 250 if len(satirlar) == 1 else 200
    for satir in satirlar:
        d.text((kenar, y), satir, font=f_baslik, fill=TEXT)
        y += satir_y

    f_alt = ImageFont.truetype(FONT_MED, 34)
    d.text((kenar, y + 18), alt, font=f_alt, fill=AMBER)

    yol = os.path.join(OG_OUT, dosya)
    # Kuantalama: 128 renk gradyanı bantlamadan taşır, boyutu ~4x düşürür.
    img.convert("RGB").quantize(colors=128, method=Image.MEDIANCUT,
                                dither=Image.Dither.NONE).save(
        yol, "PNG", optimize=True)
    boyut = os.path.getsize(yol)
    if boyut >= OG_SINIR:
        raise SystemExit(f"HATA: {dosya} {boyut // 1024} KB >= 300 KB")
    return yol


def og_kartlari() -> list:
    os.makedirs(OG_OUT, exist_ok=True)
    return [og_kart(*k) for k in OG_KARTLAR]


def main() -> None:
    if "--og" in sys.argv:
        for y in og_kartlari():
            im = Image.open(y)
            print(f"  + {os.path.basename(y):32s} {im.size[0]}x{im.size[1]} "
                  f"{os.path.getsize(y) // 1024} KB")
        return
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
