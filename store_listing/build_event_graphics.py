"""App Store In-App Event görselleri (karar 6.2 / 6.3, 2026-09-30).

Çıktı: store_listing/ios/in_app_events/<etkinlik>_kart_1920x1080.png
       store_listing/ios/in_app_events/<etkinlik>_detay_1080x1920.png

Neden METİNSİZ: App Store etkinlik adını ve kısa açıklamayı görselin
üstüne kendisi yazar; görselin içindeki yazı onunla çakışır ve dile göre
ayrı görsel ister. Görsel yalnızca motif taşır, alt üçte biri sakin
bırakılır (metin orada durur).

Palet sandık kimliğinden (lib/theme/sandik.dart): zemin #0B211C → #1A3D2E,
amber #F5A623, altın #F5C842, kazanç #3DB77F. Tek amber öğe kuralı.

    python store_listing/build_event_graphics.py
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

KOK = os.path.dirname(os.path.abspath(__file__))
CIKTI = os.path.join(KOK, "ios", "in_app_events")

ZEMIN_UST = (11, 33, 28)
ZEMIN_ALT = (26, 61, 46)
AMBER = (245, 166, 35)
ALTIN = (245, 200, 66)
KAZANC = (61, 183, 127)
SOLUK = (255, 255, 255, 60)


def zemin(g, y):
    img = Image.new("RGB", (g, y))
    d = ImageDraw.Draw(img)
    for i in range(y):
        t = i / (y - 1)
        renk = tuple(int(ZEMIN_UST[k] + (ZEMIN_ALT[k] - ZEMIN_UST[k]) * t) for k in range(3))
        d.line([(0, i), (g, i)], fill=renk)
    return img.convert("RGBA")


def isilti(img, merkez, yaricap, renk, guc=110):
    # Zemin ışıltı RENGİNDE ve saydam: saydam SİYAH bulanıklaşınca kenarda
    # koyu halka bırakıyordu.
    kat = Image.new("RGBA", img.size, renk + (0,))
    d = ImageDraw.Draw(kat)
    x, y = merkez
    d.ellipse([x - yaricap, y - yaricap, x + yaricap, y + yaricap], fill=renk + (guc,))
    kat = kat.filter(ImageFilter.GaussianBlur(yaricap * 0.6))
    return Image.alpha_composite(img, kat)


def egri(noktalar, g, y, kutu):
    """0..1 noktalarını [x0,y0,x1,y1] kutusuna yerleştirir."""
    x0, y0, x1, y1 = kutu
    n = len(noktalar)
    return [(x0 + (x1 - x0) * i / (n - 1), y1 - (y1 - y0) * v) for i, v in enumerate(noktalar)]


def kesikli(d, pts, renk, genislik, parca=26, bosluk=18):
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        uz = math.hypot(bx - ax, by - ay)
        adim = parca + bosluk
        s = 0.0
        while s < uz:
            e = min(s + parca, uz)
            d.line([(ax + (bx - ax) * s / uz, ay + (by - ay) * s / uz),
                    (ax + (bx - ax) * e / uz, ay + (by - ay) * e / uz)],
                   fill=renk, width=genislik)
            s += adim


def enflasyon(g, y, kutu):
    """TÜFE (kesikli, soluk) ile portföy (altın) yarışı; portföy sonda önde."""
    img = zemin(g, y)
    tufe = [0.10 + 0.62 * (i / 23) ** 1.05 for i in range(24)]
    portfoy = [0.08, 0.12, 0.10, 0.18, 0.16, 0.24, 0.22, 0.30, 0.28, 0.36, 0.33, 0.42,
               0.40, 0.47, 0.52, 0.50, 0.58, 0.62, 0.60, 0.68, 0.73, 0.71, 0.80, 0.86]
    tp = egri(tufe, g, y, kutu)
    pp = egri(portfoy, g, y, kutu)
    img = isilti(img, pp[-1], int(min(g, y) * 0.10), ALTIN, 120)
    kal = max(4, int(min(g, y) * 0.007))
    # TÜFE ayrı katmanda: doğrudan RGBA'ya çizilen yarı saydam renk
    # karışmaz, pikseli değiştirir (ilk çıktıda çizgi opak beyazdı).
    kat = Image.new("RGBA", img.size, (255, 255, 255, 0))
    kesikli(ImageDraw.Draw(kat), tp, SOLUK, kal)
    img = Image.alpha_composite(img, kat)
    d = ImageDraw.Draw(img)
    d.line(pp, fill=ALTIN, width=int(kal * 1.8), joint="curve")
    r = int(kal * 3.2)
    x, yy = pp[-1]
    d.ellipse([x - r, yy - r, x + r, yy + r], fill=AMBER)
    return img


def yil_sonu(g, y, kutu):
    """On iki ay: yükselen sütunlar, son ay altın ve ışıltılı."""
    img = zemin(g, y)
    x0, y0, x1, y1 = kutu
    boy = [0.28, 0.34, 0.31, 0.40, 0.44, 0.41, 0.52, 0.57, 0.55, 0.66, 0.74, 0.92]
    n = len(boy)
    adim = (x1 - x0) / n
    gen = adim * 0.56
    son_ust = None
    kat = Image.new("RGBA", img.size, (61, 183, 127, 0))
    d = ImageDraw.Draw(kat)
    for i, b in enumerate(boy):
        cx = x0 + adim * (i + 0.5)
        ust = y1 - (y1 - y0) * b
        renk = ALTIN + (255,) if i == n - 1 else (61, 183, 127, 90 + 12 * i)
        d.rounded_rectangle([cx - gen / 2, ust, cx + gen / 2, y1], radius=gen * 0.28, fill=renk)
        if i == n - 1:
            son_ust = (cx, ust)
    img = isilti(img, son_ust, int(min(g, y) * 0.11), ALTIN, 110)
    img = Image.alpha_composite(img, kat)
    d = ImageDraw.Draw(img)
    r = int(min(g, y) * 0.018)
    d.ellipse([son_ust[0] - r, son_ust[1] - 2.6 * r, son_ust[0] + r, son_ust[1] - 0.6 * r], fill=AMBER)
    return img


def uret():
    os.makedirs(CIKTI, exist_ok=True)
    # Kart 16:9 — motif üst üçte ikide; alt üçte bir metne bırakılır.
    # Detay 9:16 — motif ortada; üst (durum çubuğu) ve alt (metin) sakin.
    boyutlar = {
        "kart_1920x1080": (1920, 1080, lambda g, y: (g * 0.10, y * 0.10, g * 0.90, y * 0.62)),
        "detay_1080x1920": (1080, 1920, lambda g, y: (g * 0.10, y * 0.24, g * 0.90, y * 0.62)),
    }
    for ad, cizici in (("enflasyon_gunu", enflasyon), ("yil_sonu_ozeti", yil_sonu)):
        for ek, (g, y, kutu) in boyutlar.items():
            yol = os.path.join(CIKTI, f"{ad}_{ek}.png")
            cizici(g, y, kutu(g, y)).convert("RGB").save(yol, optimize=True)
            print(yol)


if __name__ == "__main__":
    uret()
