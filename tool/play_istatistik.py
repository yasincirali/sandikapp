#!/usr/bin/env python3
"""Play özeti: son 7 gün kurulum/kaldırma adedi ve çökme/ANR oranı.

Neden (yasin 2026-11-13, "Play mağazaya açıldı"): App Store tarafı
`asc_satis_raporu.py` ile haftalık geliyor; Play herkese açılınca aynı
pazartesi özetine Play de girsin.

İki kaynak, ikisi de mevcut `PLAY_SERVICE_ACCOUNT_JSON` ile:
- Çökme/ANR: Play Developer Reporting API (Android vitals). Servis hesabının
  Play Console'da "Uygulama bilgilerini görüntüleme" izni yeterli.
- Kurulum: Reporting API kurulum sayısı vermez; Play bunu yalnız toplu rapor
  kovasında (`pubsite_prod_…`, stats/installs) CSV olarak yayınlar. Kova adı
  `PLAY_GCS_BUCKET`'ta; yoksa bu bölüm atlanır, vitals yine basılır. Hesabın
  "Toplu raporları indirme" izni gerekir.

Salt okunur (yalnız GET/query). Neden yalnız adet ve oran: repo herkese
açık, Actions logları da öyle; gelir ve hata gövdesi basılmaz. Hata
olursa yalnız HTTP durum kodu yazılır, iş kırılmaz (rapor bilgi amaçlı).
"""
import csv
import datetime as dt
import io
import json
import os
import sys
import time
import urllib.parse

PAKET = "com.sandik.app"
VITALS = "https://playdeveloperreporting.googleapis.com/v1beta1"
GCS = "https://storage.googleapis.com/storage/v1"
KAPSAM = ("https://www.googleapis.com/auth/playdeveloperreporting "
          "https://www.googleapis.com/auth/devstorage.read_only")


def erisim_anahtari(sa):
    import jwt
    import requests
    simdi = int(time.time())
    iddia = jwt.encode(
        {"iss": sa["client_email"], "scope": KAPSAM,
         "aud": "https://oauth2.googleapis.com/token",
         "iat": simdi, "exp": simdi + 3600},
        sa["private_key"], algorithm="RS256")
    t = requests.post("https://oauth2.googleapis.com/token", timeout=30, data={
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": iddia})
    t.raise_for_status()
    return t.json()["access_token"]


def _gun(d):
    # Reporting API günlük toplamda yalnız Pasifik saatini kabul ediyor.
    return {"year": d.year, "month": d.month, "day": d.day,
            "timeZone": {"id": "America/Los_Angeles"}}


def vitals_ozeti(yanit, metrikler):
    """Günlük satırların ortalaması; oran %'ye çevrilir. Saf, test edilir."""
    toplam, adet = {m: 0.0 for m in metrikler}, {m: 0 for m in metrikler}
    for satir in yanit.get("rows", []):
        for m in satir.get("metrics", []):
            ad = m.get("metric")
            deger = (m.get("decimalValue") or {}).get("value")
            if ad in toplam and deger is not None:
                toplam[ad] += float(deger)
                adet[ad] += 1
    return {m: (toplam[m] / adet[m] * 100 if adet[m] else None) for m in metrikler}


def kurulum_ozeti(csv_metni, bas, bit):
    """Play'in installs_*_overview.csv'si → [bas, bit] toplamları. Saf.

    Sütun adları Play'de zamanla değişti; ada göre seçilir, yoksa atlanır.
    """
    okur = csv.DictReader(io.StringIO(csv_metni))
    sonuc = {"kurulum": 0, "kaldırma": 0, "gün": 0}
    aktif = None
    for s in okur:
        try:
            gun = dt.date.fromisoformat((s.get("Date") or "").strip())
        except ValueError:
            continue
        if not bas <= gun <= bit:
            continue
        sonuc["gün"] += 1
        sonuc["kurulum"] += int(s.get("Daily User Installs") or 0)
        sonuc["kaldırma"] += int(s.get("Daily User Uninstalls") or 0)
        if s.get("Active Device Installs"):
            aktif = int(s["Active Device Installs"])
    sonuc["aktif cihaz"] = aktif
    return sonuc


def _csv_indir(tok, kova, ay):
    import requests
    ad = f"stats/installs/installs_{PAKET}_{ay:%Y%m}_overview.csv"
    r = requests.get(f"{GCS}/b/{kova}/o/{urllib.parse.quote(ad, safe='')}",
                     params={"alt": "media"}, timeout=60,
                     headers={"Authorization": f"Bearer {tok}"})
    if r.status_code == 404:
        return ""
    r.raise_for_status()
    # Play bu raporları UTF-16 yazıyor.
    return r.content.decode("utf-16")


def main():
    import requests
    ham = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON", "")
    if not ham:
        print("atlandı: PLAY_SERVICE_ACCOUNT_JSON yok")
        return 0
    try:
        tok = erisim_anahtari(json.loads(ham))
    except Exception as e:  # noqa: BLE001 — gövde/anahtar basılmaz
        print(f"atlandı: Play erişim anahtarı alınamadı ({type(e).__name__})")
        return 0
    bugun = dt.date.today()
    # Vitals ~2 gün gecikmeli; ASC özetiyle aynı pencere: 2–8 gün önce.
    bas, bit = bugun - dt.timedelta(days=8), bugun - dt.timedelta(days=2)
    print(f"Play, son 7 gün ({bas} – {bit})")

    kova = os.environ.get("PLAY_GCS_BUCKET", "").strip()
    if kova:
        try:
            metin = _csv_indir(tok, kova, bas)
            if bit.month != bas.month:
                metin_bit = _csv_indir(tok, kova, bit)
                # İkinci dosyanın başlık satırını at, satırları ekle.
                metin += "\n".join(metin_bit.splitlines()[1:]) if metin else metin_bit
            k = kurulum_ozeti(metin, bas, bit)
            print(f"  kurulum: {k['kurulum']}  kaldırma: {k['kaldırma']}"
                  f"  aktif cihaz: {k['aktif cihaz'] if k['aktif cihaz'] is not None else '?'}"
                  f"  (raporlu gün {k['gün']}/7)")
        except requests.HTTPError as e:
            print(f"  kurulum: okunamadı (HTTP {e.response.status_code}; "
                  "servis hesabına 'Toplu raporları indirme' izni gerekli)")
    else:
        print("  kurulum: atlandı (PLAY_GCS_BUCKET yok)")

    govde = {"timelineSpec": {"aggregationPeriod": "DAILY",
                              "startTime": _gun(bas),
                              "endTime": _gun(bit + dt.timedelta(days=1))}}
    for kume, metrikler, etiket in (
            ("crashRateMetricSet", ["crashRate", "userPerceivedCrashRate"], "çökme"),
            ("anrRateMetricSet", ["anrRate", "userPerceivedAnrRate"], "ANR")):
        r = requests.post(f"{VITALS}/apps/{PAKET}/{kume}:query", timeout=60,
                          headers={"Authorization": f"Bearer {tok}"},
                          json={**govde, "metrics": metrikler})
        if not r.ok:
            print(f"  {etiket}: okunamadı (HTTP {r.status_code})")
            continue
        o = vitals_ozeti(r.json(), metrikler)
        print(f"  {etiket} oranı: " + "  ".join(
            f"{m} {'?' if v is None else f'%{v:.2f}'}" for m, v in o.items()))
    print("  (Play'in kötü davranış eşiği: kullanıcının gördüğü çökme %1,09, ANR %0,47)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
