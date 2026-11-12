#!/usr/bin/env python3
"""App Store satış özeti: son 7 gün indirme / güncelleme / abonelik adedi.

Neden ayrı anahtar: mevcut ASC_* anahtarının rolü Satış raporunu göremiyor
(rol sonradan değişmez); yasin 2026-11-13 Sales rolüyle `ASC_SATIS_*` açtı.
Salt okunur (yalnız GET). Neden yalnız ADET: repo herkese açık, Actions
logları da öyle; gelir tutarı ve hesap ayrıntısı basılmaz.
GÜNLÜK rapor çekilir (haftalık raporun tarih kuralı belirsiz); Apple henüz
yayınlamadığı ya da satış olmayan günlere 404 döner, atlanır.

Kullanım: ASC_SATIS_KEY_ID, ASC_SATIS_ISSUER_ID, ASC_SATIS_KEY_CONTENT,
ASC_VENDOR_NUMBER ortamda olmalı (pip install requests pyjwt cryptography).
"""
import csv
import datetime as dt
import gzip
import io
import os
import sys
import time
from collections import Counter

import jwt
import requests

URL = "https://api.appstoreconnect.apple.com/v1/salesReports"
# Apple "Product Type Identifier" → okunur ad (belgelenmiş değerler).
TUR = {
    "1": "indirme", "1F": "indirme", "1T": "indirme",
    "3": "indirme", "3F": "indirme", "3T": "indirme",
    "7": "güncelleme", "7F": "güncelleme", "7T": "güncelleme",
    "IA1": "uygulama içi satın alma", "IA9": "abonelik",
    "IAY": "abonelik (otomatik yenilenen)", "IAC": "abonelik (ücretsiz)",
    "FI1": "abonelik yenileme",
}


def token():
    simdi = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_SATIS_ISSUER_ID"], "iat": simdi,
         "exp": simdi + 900, "aud": "appstoreconnect-v1"},
        os.environ["ASC_SATIS_KEY_CONTENT"], algorithm="ES256",
        headers={"kid": os.environ["ASC_SATIS_KEY_ID"], "typ": "JWT"})


def gun_raporu(tok, gun):
    r = requests.get(URL, timeout=60, headers={"Authorization": f"Bearer {tok}"},
                     params={"filter[frequency]": "DAILY",
                             "filter[reportType]": "SALES",
                             "filter[reportSubType]": "SUMMARY",
                             "filter[vendorNumber]": os.environ["ASC_VENDOR_NUMBER"],
                             "filter[reportDate]": gun.isoformat(),
                             "filter[version]": "1_0"})
    if r.status_code == 404:
        return []
    r.raise_for_status()
    metin = gzip.decompress(r.content).decode("utf-8")
    return list(csv.DictReader(io.StringIO(metin), delimiter="\t"))


def main():
    for ad in ("ASC_SATIS_KEY_ID", "ASC_SATIS_ISSUER_ID",
               "ASC_SATIS_KEY_CONTENT", "ASC_VENDOR_NUMBER"):
        if not os.environ.get(ad):
            print(f"atlandı: {ad} yok")
            return 0
    tok = token()
    bugun = dt.date.today()
    toplam, ulke, gunluk = Counter(), Counter(), {}
    bos = 0
    # Apple raporu ~1 gün gecikmeli: dünü değil, 2–8 gün önceyi çek.
    for i in range(2, 9):
        gun = bugun - dt.timedelta(days=i)
        satirlar = gun_raporu(tok, gun)
        if not satirlar:
            bos += 1
        gunluk[gun] = 0
        for s in satirlar:
            tur = TUR.get(s.get("Product Type Identifier", ""), "diğer")
            adet = int(float(s.get("Units") or 0))
            toplam[tur] += adet
            if tur == "indirme":
                gunluk[gun] += adet
                ulke[s.get("Country Code", "?")] += adet
    print(f"Son 7 gün ({min(gunluk)} – {max(gunluk)}), yalnız adet")
    for tur, adet in toplam.most_common():
        print(f"  {tur}: {adet}")
    if not toplam:
        print("  (satış kaydı yok)")
    for gun in sorted(gunluk):
        print(f"  {gun} indirme: {gunluk[gun]}")
    if ulke:
        print("  indirme, ilk 5 ülke:",
              ", ".join(f"{k} {v}" for k, v in ulke.most_common(5)))
    print(f"  raporu olmayan gün: {bos}/7")
    return 0


if __name__ == "__main__":
    sys.exit(main())
