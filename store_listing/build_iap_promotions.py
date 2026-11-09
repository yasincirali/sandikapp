"""App Store abonelik tanıtım görselleri (App Store Promotion, 1024x1024).

    python store_listing/build_iap_promotions.py
    CHROME=/yol/chrome python store_listing/build_iap_promotions.py

Çıktı: store_listing/final/app_store/iap_promotions/sandik_premium_{aylik,yillik}.{svg,png}

Neden çizim: 1.1.7 bu alandan reddedildi (2026-11-07, 2.3.2). Apple tanıtım
görselinde ekran görüntüsünü ve uygulama simgesini kabul etmiyor, iki ürüne
aynı görseli de kabul etmiyor. İlk çizim denemesi (döngü oku, yükselen grafik
simgesi) uygulamaya ait değildi (yasin 2026-11-09: "uygulama tasarımına ve
anlamına uygun değil").

Fikir: Premium'un sloganı "Sandığının içini aç." Zemin, simgedeki dalga
katmanlarının uygulamanın yeşilleriyle çizilmiş hâli (kapalı sandık). Pencere
aynı katmanları simgenin amberleriyle gösterir (açılmış hâli). Aylıkta tek
pencere (bir ay), yıllıkta on iki pencere (on iki ay): iki görsel aynı aileden
ama bir bakışta ayrılır. Yazı yok; mağaza adı ve fiyatı kendi yazar.

Renkler lib/theme/sandik.dart ve assets/images/sandik_logo.svg'den alınır.
"""
import math
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

KOK = Path(__file__).resolve().parent
CIKTI = KOK / "final" / "app_store" / "iap_promotions"
B = 1024

# Simgedeki dalga: periyot simge genişliğinin 2/3'ü, tepe ortada.
PERIYOT = B * 2 / 3
GENLIK = 46
KATMANLAR = [452, 590, 728]  # üç katmanın orta çizgisi (y)

YESIL = ["#112E28", "#16382B", "#1A3D2E"]  # surface1 → surface2
AMBER = ["#E2861F", "#C56314", "#993D0A"]  # sandik_logo.svg katmanları


def dalga(y0: float, faz: float = 0.0) -> str:
    """Tuvali boydan boya geçen, altı dolu dalga katmanı."""
    nokta = []
    for x in range(-8, B + 9, 8):
        y = y0 - GENLIK * math.cos(2 * math.pi * (x - B / 2 - faz) / PERIYOT)
        nokta.append(f"{x},{y:.1f}")
    return f'<path d="M{" L".join(nokta)} L{B + 8},{B + 8} L-8,{B + 8} Z"'


def katmanlar(renkler: list[str]) -> str:
    return "\n".join(
        f'    {dalga(y, faz)} fill="{r}"/>'
        for y, r, faz in zip(KATMANLAR, renkler, (0, 0, 0))
    )


def sahne(pencereler: list[tuple[float, float, float, float]], isik: tuple[float, float, float]) -> str:
    """pencereler: (x, y, genişlik, yükseklik) hap biçimli açıklıklar."""
    hap = "\n".join(
        f'      <rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{w / 2:.1f}"/>'
        for x, y, w, h in pencereler
    )
    ix, iy, ir = isik
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{B}" height="{B}" viewBox="0 0 {B} {B}">
  <defs>
    <linearGradient id="zemin" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#0A1E15"/><stop offset="1" stop-color="#0E2519"/>
    </linearGradient>
    <linearGradient id="altin" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FCD35A"/><stop offset="1" stop-color="#EAA12B"/>
    </linearGradient>
    <radialGradient id="isik" cx="{ix}" cy="{iy}" r="{ir}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#F5C842" stop-opacity=".16"/>
      <stop offset="1" stop-color="#F5C842" stop-opacity="0"/>
    </radialGradient>
    <clipPath id="pencere">
{hap}
    </clipPath>
  </defs>
  <rect width="{B}" height="{B}" fill="url(#zemin)"/>
  <rect width="{B}" height="{B}" fill="url(#isik)"/>
  <g>
{katmanlar(YESIL)}
  </g>
  <g clip-path="url(#pencere)">
    <rect width="{B}" height="{B}" fill="url(#altin)"/>
{katmanlar(AMBER)}
  </g>
</svg>
"""


def aylik() -> str:
    # Tek pencere = bir ay. Ortada; dalganın tepesi içinden geçer.
    w, h = 336, 704
    return sahne([((B - w) / 2, (B - h) / 2, w, h)], (B / 2, B / 2, 520))


def yillik() -> str:
    # On iki pencere = on iki ay. Üst kenar simgedeki dalgayı izler; düz
    # sıra çit gibi, sürekli yükselen sıra getiri vaadi gibi okunuyordu.
    n, w, bosluk, alt = 12, 46, 24, 880
    sol = (B - (n * w + (n - 1) * bosluk)) / 2
    p = []
    for i in range(n):
        x = sol + i * (w + bosluk)
        ust = 236 - 62 * math.cos(2 * math.pi * (x + w / 2 - B / 2) / PERIYOT)
        p.append((x, ust, w, alt - ust))
    return sahne(p, (B / 2, 420, 620))


def chrome() -> str:
    adaylar = [
        os.environ.get("CHROME"),
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        "/usr/bin/google-chrome",
        "/usr/bin/chromium",
    ]
    for a in adaylar:
        if a and Path(a).exists():
            return a
    sys.exit("Chrome bulunamadı; CHROME ortam değişkeniyle yolunu ver.")


def main() -> None:
    CIKTI.mkdir(parents=True, exist_ok=True)
    tarayici = chrome()
    for ad, svg in (("aylik", aylik()), ("yillik", yillik())):
        kaynak = CIKTI / f"sandik_premium_{ad}.svg"
        hedef = CIKTI / f"sandik_premium_{ad}.png"
        kaynak.write_text(svg, encoding="utf-8")
        with tempfile.TemporaryDirectory() as profil:
            subprocess.run(
                [tarayici, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                 f"--user-data-dir={profil}", f"--window-size={B},{B}",
                 "--force-device-scale-factor=1", f"--screenshot={hedef}",
                 kaynak.as_uri()],
                check=True, capture_output=True, timeout=120,
            )
        # Apple saydamlık (alfa) kabul etmiyor.
        g = Image.open(hedef).convert("RGB")
        assert g.size == (B, B), g.size
        g.save(hedef, optimize=True)
        print("ok", hedef.relative_to(KOK.parent))


if __name__ == "__main__":
    main()
