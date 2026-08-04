#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
App Store / Play Store ekran görüntüsü üretici.

Ham ekran görüntülerini (iPhone 12 mini, 1080x2340) alır; telefon çerçevesi
içine yerleştirip üstüne başlık metni ekler ve mağazanın istediği boyutlarda
çıktı üretir.

Kullanım:
    python build_screenshots.py

Girdi : screenshots/raw/NN_ad.png   (sıra numarasına göre eşleşir)
Çıktı : screenshots/out/<boyut>/NN_ad.png

Boyutlar App Store Connect'in kabul ettiği ölçülerdir:
    1242x2688  (6.5")
    1284x2778  (6.7")

Font: assets/fonts/ altındaki DM Sans — uygulamanın kendi yazı tipi,
marka tutarlılığı için.
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# Windows konsolu (cp1254) Türkçe karakterleri basamıyor ve script'i
# UnicodeEncodeError ile düşürüyor. Çıktıyı UTF-8'e zorla.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RAW = os.path.join(HERE, "screenshots", "raw")
OUT = os.path.join(HERE, "screenshots", "out")

FONT_BOLD = os.path.join(ROOT, "assets", "fonts", "DMSans-Bold.ttf")
FONT_MED = os.path.join(ROOT, "assets", "fonts", "DMSans-Medium.ttf")

# sandık paleti — lib/theme/sandik.dart ile aynı
BG_TOP = (10, 30, 21)      # koyu yeşil, marka zemini
BG_BOTTOM = (6, 18, 13)
AMBER = (245, 166, 35)
TEXT = (255, 255, 255)
SUBTLE = (255, 255, 255, 150)
# Ölçüldü: ortak sekmesindeki pasif etiket rengi (soluk gri-yeşil).
TAB_GREY = (108, 120, 115)

TARGETS = [(1242, 2688), (1284, 2778)]

# Ham görüntünün üstünden kırpılacak oran (durum çubuğu). 0 = kırpma yok.
# Ekran görüntülerinde saat/pil görünmesini istemiyorsanız 0.035 deneyin.
CROP_TOP = 0.0

# ── Gerçek isimlerin üzerine sahte isim yazma ─────────────────────────────
#
# Yarış/ortak ekranlarında gerçek kullanıcı adları görünür; mağaza görseline
# gerçek kişi adı gitmemeli. Burada tanımlanan bölgeler ham görüntü
# üzerinde ORANSAL koordinatlarla (0-1 arası) belirtilir, böylece farklı
# çözünürlükte de aynı yere denk gelir.
#
# Format:
#   "01": [ (x, y, genişlik, yükseklik, "yeni metin"), ... ]
#
# Koordinatları bulmak için:
#   python build_screenshots.py --grid
# komutu ham görüntülerin üzerine ızgara çizip scratch klasörüne kaydeder.
REDACTIONS = {
    # Ortak sekmesindeki gerçek ad ("sila") — segment kontrolünün sağ
    # üçte biri. Satır konumu ekrana göre değiştiği için her kare ayrı.
    # Ölçüm: segment şeridi 01=0.489-0.538, 02=0.143-0.190,
    # 03/04/05=0.164-0.213. Yama şeridin iç yüksekliğini kaplar.
    "01": [(0.660, 0.4955, 0.245, 0.0360, "Ayşe", "c", 0.0111, TAB_GREY)],
    "02": [(0.660, 0.1495, 0.245, 0.0345, "Ayşe", "c", 0.0111, TAB_GREY)],
    "03": [(0.660, 0.1710, 0.245, 0.0360, "Ayşe", "c", 0.0111, TAB_GREY)],
    "04": [(0.660, 0.1710, 0.245, 0.0360, "Ayşe", "c", 0.0111, TAB_GREY)],
    "05": [(0.660, 0.1710, 0.245, 0.0360, "Ayşe", "c", 0.0111, TAB_GREY)],
    # Yarış sıralaması — iki gerçek ad + üstteki iOS sistem bildirimi
    "06": [
        (0.120, 0.040, 0.790, 0.058, ""),           # "Arkaya Dokunma" bildirimi
        # Ölçüm: 1. satır ismi 0.217-0.504, LİDER rozeti 0.541-0.599.
        # Yama 0.51'de biter — rozet korunur (kişisel veri değil, bilgi verici).
        (0.212, 0.2415, 0.298, 0.0290, "Ayşe K. (sen)"),
        (0.212, 0.3465, 0.230, 0.0280, "Mehmet D."),
    ],
}

# Sıra → (başlık, alt satır). SCREENSHOT_PLAN.md ile birebir aynı sıra.
# Alt satır None ise yalnızca başlık çizilir.
CAPTIONS = {
    "01": ("Tüm yatırımların\ntek ekranda", "Hisse, fon, döviz, altın"),
    "02": ("Zaman içinde\nne kazandın, gör", "Gün, ay, yıl bazında getiri"),
    # Bu kare kaydırma aksiyonlarını gösteriyor (Ekle / Çıkar / Temettü) —
    # komisyon kırılımını değil. Başlık kareyle uyumlu olmalı.
    "03": ("Temettünü de\nkaydet", "Kaydır: ekle, çıkar, temettü gir"),
    "04": ("Ağırlığın nerede,\ntek bakışta", "Dağılımını dengede tut"),
    "05": ("Eşinle, ortağınla\naynı portföy", "Herkesin katkısı ayrı hesaplanır"),
    "06": ("İstersen sıralamada\nyerini gör", "Anonim — tutar paylaşılmaz"),
    "07": ("Her varlığın\nkendi hikâyesi", "Alış çizgisi, dönem değişimi, MA20"),
}


def gradient(size):
    """Dikey degrade zemin."""
    w, h = size
    base = Image.new("RGB", (1, h))
    px = base.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        px[0, y] = tuple(
            int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3)
        )
    return base.resize((w, h), Image.BILINEAR)


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([(0, 0), (size[0] - 1, size[1] - 1)],
                                        radius=radius, fill=255)
    return m


def fit_font(path, text, max_w, start, draw, min_size=28):
    """Metin max_w'ye sığana kadar punto düşürür."""
    size = start
    while size > min_size:
        f = ImageFont.truetype(path, size)
        widest = max(
            draw.textbbox((0, 0), line, font=f)[2] for line in text.split("\n")
        )
        if widest <= max_w:
            return f
        size -= 2
    return ImageFont.truetype(path, min_size)


def sample_bg(img, box):
    """Maskelenecek alanın zemin rengini çevresinden örnekler.

    Tek noktadan renk almak yamanın sınırını belli ediyordu (zemin hafif
    degradeli). Bunun yerine kutunun üst ve alt kenarından medyan alınır —
    yama çevreye karışır.
    """
    x, y, w, h = box
    px = img.load()
    samples = []
    for sy in (max(0, y - 3), min(img.height - 1, y + h + 2)):
        for i in range(1, 10):
            sx = min(img.width - 1, x + w * i // 10)
            samples.append(px[sx, sy])
    if not samples:
        return (0, 0, 0)
    samples.sort(key=sum)
    return samples[len(samples) // 2]


def apply_redactions(shot, key):
    """Gerçek isimleri sahte olanlarla değiştirir.

    Koordinatlar oransaldır; ham görüntünün çözünürlüğü değişse de
    aynı yere denk gelir.
    """
    spec = REDACTIONS.get(key)
    if not spec:
        return shot

    draw = ImageDraw.Draw(shot)
    for item in spec:
        rx, ry, rw, rh, text = item[:5]
        # 6. eleman verilirse hizalama: "c" ortalı (sekme etiketi),
        # varsayılan sola dayalı (liste satırı).
        align = item[5] if len(item) > 5 else "l"

        x = int(rx * shot.width)
        y = int(ry * shot.height)
        w = int(rw * shot.width)
        h = int(rh * shot.height)

        draw.rectangle([(x, y), (x + w, y + h)],
                       fill=sample_bg(shot, (x, y, w, h)))

        if not text:
            continue

        # 7. eleman: metin yüksekliği (ham görüntü oranı). Verilmezse
        # yama yüksekliğinin yarısı. Orijinal metnin punto ve rengiyle
        # eşleşmezse yama gözle belli olur — ölçüp geçmek gerekir.
        cap_h = item[6] if len(item) > 6 else rh * 0.5
        colour = item[7] if len(item) > 7 else TEXT

        size = max(10, int(cap_h * shot.height * 1.38))
        f = ImageFont.truetype(FONT_MED, size)
        bb = draw.textbbox((0, 0), text, font=f)
        tx = x + (w - (bb[2] - bb[0])) // 2 if align == "c" else x
        draw.text((tx, y + (h - (bb[3] - bb[1])) // 2 - bb[1]), text,
                  font=f, fill=colour)
    return shot


def write_grid_overlays():
    """Ham görüntülerin üzerine oransal ızgara çizer.

    REDACTIONS koordinatlarını gözle bulmak için: üretilen dosyada
    her çizginin yanında 0-1 arası oran yazar.
    """
    out_dir = os.path.join(HERE, "screenshots", "grid")
    os.makedirs(out_dir, exist_ok=True)

    for name in sorted(f for f in os.listdir(RAW)
                       if f.lower().endswith((".png", ".jpg", ".jpeg"))):
        im = Image.open(os.path.join(RAW, name)).convert("RGB")
        d = ImageDraw.Draw(im)
        f = ImageFont.truetype(FONT_MED, max(14, im.width // 55))

        for i in range(1, 20):
            t = i / 20
            yy = int(im.height * t)
            d.line([(0, yy), (im.width, yy)], fill=(255, 0, 128), width=1)
            d.text((6, yy + 2), "%.2f" % t, font=f, fill=(255, 0, 128))

        for i in range(1, 10):
            t = i / 10
            xx = int(im.width * t)
            d.line([(xx, 0), (xx, im.height)], fill=(0, 220, 255), width=1)
            d.text((xx + 3, 6), "%.1f" % t, font=f, fill=(0, 220, 255))

        im.save(os.path.join(out_dir, "grid_" + os.path.splitext(name)[0]
                             + ".png"))
        print("  + grid_%s" % name)

    print("\nIzgara dosyalari -> screenshots/grid/")


def compose(raw_path, caption, target, key=None):
    tw, th = target
    canvas = gradient(target).convert("RGB")
    draw = ImageDraw.Draw(canvas)

    title, subtitle = caption
    margin = int(tw * 0.08)
    text_w = tw - margin * 2

    # ── Başlık ────────────────────────────────────────────────────────────
    f_title = fit_font(FONT_BOLD, title, text_w, int(tw * 0.082), draw)
    f_sub = ImageFont.truetype(FONT_MED, int(tw * 0.038))

    y = int(th * 0.055)
    for line in title.split("\n"):
        bb = draw.textbbox((0, 0), line, font=f_title)
        draw.text(((tw - (bb[2] - bb[0])) / 2, y), line, font=f_title, fill=TEXT)
        y += int((bb[3] - bb[1]) * 1.45)

    if subtitle:
        y += int(th * 0.018)
        bb = draw.textbbox((0, 0), subtitle, font=f_sub)
        draw.text(((tw - (bb[2] - bb[0])) / 2, y), subtitle, font=f_sub,
                  fill=AMBER)
        y += (bb[3] - bb[1])

    # ── Telefon çerçevesi ─────────────────────────────────────────────────
    shot = Image.open(raw_path).convert("RGB")

    # Gerçek isimleri sahte olanlarla değiştir — kırpmadan ÖNCE, çünkü
    # REDACTIONS koordinatları kırpılmamış görüntüye göre tanımlı.
    if key:
        shot = apply_redactions(shot, key)

    # Ham görüntünün üstündeki durum çubuğu (saat/pil) mağaza görselinde
    # gereksiz; istenirse kırpılır. CROP_TOP oranı ham yüksekliğe göredir.
    if CROP_TOP:
        shot = shot.crop((0, int(shot.height * CROP_TOP), shot.width,
                          shot.height))

    top = y + int(th * 0.045)
    avail_h = th - top - int(th * 0.05)
    avail_w = tw - margin * 2

    scale = min(avail_w / shot.width, avail_h / shot.height)
    sw, sh = int(shot.width * scale), int(shot.height * scale)
    shot = shot.resize((sw, sh), Image.LANCZOS)

    radius = int(sw * 0.075)
    shot.putalpha(rounded_mask((sw, sh), radius))

    x = (tw - sw) // 2

    # Gölge — çerçeveyi zeminden ayırır
    shadow = Image.new("RGBA", (sw + 80, sh + 80), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [(40, 46), (sw + 39, sh + 45)], radius=radius, fill=(0, 0, 0, 130)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(26))
    canvas.paste(shadow, (x - 40, top - 40), shadow)

    # İnce amber kenarlık
    border = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle(
        [(0, 0), (sw - 1, sh - 1)], radius=radius,
        outline=AMBER + (90,), width=max(2, int(sw * 0.004))
    )

    canvas.paste(shot, (x, top), shot)
    canvas.paste(border, (x, top), border)

    return canvas


def main():
    if not os.path.isdir(RAW):
        sys.exit("Ham görüntü klasörü yok: %s" % RAW)

    for missing in (FONT_BOLD, FONT_MED):
        if not os.path.exists(missing):
            sys.exit("Font bulunamadı: %s" % missing)

    if "--grid" in sys.argv:
        write_grid_overlays()
        return

    # PNG tercih edilir ama JPEG de kabul — WhatsApp/AirDrop ile taşınan
    # görüntüler JPEG gelir.
    files = sorted(f for f in os.listdir(RAW)
                   if f.lower().endswith((".png", ".jpg", ".jpeg")))
    if not files:
        sys.exit(
            "screenshots/raw/ boş.\n"
            "Ham ekran görüntülerini 01_*.png ... 06_*.png olarak koyun."
        )

    made = 0
    for name in files:
        key = name[:2]
        caption = CAPTIONS.get(key)
        if caption is None:
            print("  ! %s — %s için başlık tanımlı değil, atlandı" % (name, key))
            continue

        src = Image.open(os.path.join(RAW, name))
        if min(src.size) < 1000:
            print("  ! %s — çözünürlük düşük (%dx%d). Ham ekran görüntüsü "
                  "kullanın; WhatsApp gibi araçlar görseli küçültür."
                  % (name, src.width, src.height))

        stem = os.path.splitext(name)[0] + ".png"
        for tw, th in TARGETS:
            out_dir = os.path.join(OUT, "%dx%d" % (tw, th))
            os.makedirs(out_dir, exist_ok=True)
            img = compose(os.path.join(RAW, name), caption, (tw, th), key=key)
            img.save(os.path.join(out_dir, stem), "PNG", optimize=True)
            made += 1
        print("  + %s" % name)

    print("\n%d dosya uretildi -> screenshots/out/" % made)


if __name__ == "__main__":
    main()
