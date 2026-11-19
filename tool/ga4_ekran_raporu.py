#!/usr/bin/env python3
"""GA4 haftalık ekran raporu: hangi ekrana kaç kişi girmiş, ne kadar kalmış.

Neden (yasin 2026-11-19, "kim nereye girmiş, nerede ne kadar zaman
geçirmiş"): az kullanılan ekran/özelliği ayıklamak. Ar-Ge eşiği: giriş
yapmış aktif kullanıcıların %3'ü; payda tüm cihazlar değil, GİRİŞ YAPMIŞ
kullanıcı (`signedInWithUserId = yes`; uygulama girişte `setUserId` çağırır).

Üç kırılım, son 7 ve son 30 gün (dün dahil; bugün yarım gün olduğu için yok):
- ekran adı (`unifiedScreenName`): görüntüleme, kullanıcı, kişi başı süre
- `ozellik_kullanildi` → `customEvent:ozellik`
- `widget_tapped` → `customEvent:surface`
İki özel boyut 2026-11-19'da açıldı; öncesi "(not set)" görünür.

Kimlik: hizmet hesabı JSON'u (`GA4_SERVICE_ACCOUNT_JSON`; akış boşsa Play
hesabına düşer, o hesap GA mülkünde Görüntüleyici yapılınca yeni anahtar
gerekmez) + `GA4_PROPERTY_ID` (sayısal mülk kimliği). Salt okunur
(analytics.readonly). Repo herkese açık, Actions logları da öyle: yalnız
toplu sayı basılır, kullanıcı kimliği/cihaz/ülke yok. Hata olursa yalnız
HTTP durumu ve Google'ın durum kodu yazılır, yanıt gövdesi değil.
"""
import json
import os
import sys
import time

API = "https://analyticsdata.googleapis.com/v1beta/properties/{}:runReport"
KAPSAM = "https://www.googleapis.com/auth/analytics.readonly"
ESIK = 0.03
DONEMLER = (7, 30)
# (başlık, boyut, olay süzgeci, sayı metriği etiketi)
KIRILIMLAR = (
    ("Ekranlar", "unifiedScreenName", None, "görüntüleme"),
    ("Özellik kullanımı (ozellik_kullanildi)", "customEvent:ozellik",
     "ozellik_kullanildi", "olay"),
    ("Widget dokunuşu (widget_tapped)", "customEvent:surface",
     "widget_tapped", "olay"),
)
GIRISLI = {"filter": {"fieldName": "signedInWithUserId",
                      "stringFilter": {"value": "yes"}}}


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


def _ve(*parcalar):
    parcalar = [p for p in parcalar if p]
    if not parcalar:
        return None
    return parcalar[0] if len(parcalar) == 1 else {
        "andGroup": {"expressions": parcalar}}


def _olay(ad):
    return ad and {"filter": {"fieldName": "eventName",
                              "stringFilter": {"value": ad}}}


def istekler(gun, boyut, olay):
    """Bir kırılım için iki istek: tümü (sayı, kullanıcı, süre) + girişli kullanıcı."""
    tarih = [{"startDate": f"{gun}daysAgo", "endDate": "yesterday"}]
    sayi = "eventCount" if olay else "screenPageViews"
    tum = {"dateRanges": tarih, "dimensions": [{"name": boyut}],
           "metrics": [{"name": sayi}, {"name": "activeUsers"},
                       {"name": "userEngagementDuration"}],
           "limit": 250}
    girisli = {"dateRanges": tarih, "dimensions": [{"name": boyut}],
               "metrics": [{"name": "activeUsers"}], "limit": 250}
    if _olay(olay):
        tum["dimensionFilter"] = _olay(olay)
    girisli["dimensionFilter"] = _ve(_olay(olay), GIRISLI)
    return tum, girisli


def payda_istegi(gun):
    return {"dateRanges": [{"startDate": f"{gun}daysAgo", "endDate": "yesterday"}],
            "metrics": [{"name": "activeUsers"}], "dimensionFilter": GIRISLI}


def satirlar(yanit):
    """runReport yanıtı → {boyut değeri: [metrikler (float)]}."""
    return {s["dimensionValues"][0]["value"] if s.get("dimensionValues") else "":
            [float(m["value"]) for m in s["metricValues"]]
            for s in yanit.get("rows", [])}


def birlestir(tum, girisli, payda):
    """Satırları tek tabloya çevirir; girişli kullanıcı payına göre büyükten küçüğe."""
    tum, girisli = satirlar(tum), satirlar(girisli)
    sonuc = []
    for ad in set(tum) | set(girisli):
        sayi, kullanici, sure = tum.get(ad, [0, 0, 0])
        g = girisli.get(ad, [0])[0]
        sonuc.append({
            "ad": ad or "(not set)", "sayi": int(sayi), "kullanici": int(kullanici),
            "sure": sure / kullanici if kullanici else 0, "girisli": int(g),
            "pay": g / payda if payda else 0})
    sonuc.sort(key=lambda s: (-s["pay"], -s["sayi"], s["ad"]))
    return sonuc


def _sure(sn):
    sn = round(sn)
    return f"{sn // 60} dk {sn % 60:02d} sn" if sn >= 60 else f"{sn} sn"


def _yuzde(x):
    return f"%{x * 100:.1f}".replace(".", ",")


def tablo(baslik, etiket, liste, payda):
    alt = [s for s in liste if s["pay"] < ESIK]
    satir = [f"#### {baslik}", "",
             f"| Ad | {etiket} | kullanıcı | kişi başı süre | girişli | girişli payı |",
             "|---|---:|---:|---:|---:|---:|"]
    for s in liste:
        isaret = " ⚠" if s["pay"] < ESIK else ""
        satir.append(f"| {s['ad']} | {s['sayi']} | {s['kullanici']} | "
                     f"{_sure(s['sure'])} | {s['girisli']} | {_yuzde(s['pay'])}{isaret} |")
    if not liste:
        satir.append("| (veri yok) | | | | | |")
    satir += ["", f"Eşik altı (%{ESIK * 100:.0f}, payda {payda} girişli kullanıcı): "
              f"{len(alt)} satır" + (": " + ", ".join(s["ad"] for s in alt) if alt else ""),
              ""]
    return "\n".join(satir)


def _sor(tok, mulk, govde):
    import requests
    r = requests.post(API.format(mulk), timeout=60, json=govde,
                      headers={"Authorization": f"Bearer {tok}"})
    if r.status_code != 200:
        try:
            durum = r.json().get("error", {}).get("status", "")
        except ValueError:
            durum = ""
        raise RuntimeError(f"GA4 HTTP {r.status_code} {durum}".strip())
    return r.json()


def main():
    sa_metni = os.environ.get("GA4_SERVICE_ACCOUNT_JSON")
    mulk = os.environ.get("GA4_PROPERTY_ID", "").strip()
    if not sa_metni or not mulk:
        print("atlandı: GA4_SERVICE_ACCOUNT_JSON ya da GA4_PROPERTY_ID yok")
        return 0
    try:
        tok = erisim_anahtari(json.loads(sa_metni))
    except Exception as e:  # noqa: BLE001 — gövde basılmaz, yalnız tür
        print(f"GA4 erişim anahtarı alınamadı ({type(e).__name__})")
        return 1
    rapor = ["## Ekran istatistiği (GA4)", "",
             "Süre = etkileşim süresi / kullanıcı. ⚠ = girişli kullanıcıların "
             f"%{ESIK * 100:.0f}'ünden azı.", ""]
    try:
        for gun in DONEMLER:
            p = satirlar(_sor(tok, mulk, payda_istegi(gun))).get("", [0])[0]
            payda = int(p)
            rapor += [f"### Son {gun} gün (girişli aktif kullanıcı: {payda})", ""]
            for baslik, boyut, olay, etiket in KIRILIMLAR:
                tum, girisli = istekler(gun, boyut, olay)
                liste = birlestir(_sor(tok, mulk, tum), _sor(tok, mulk, girisli), payda)
                rapor.append(tablo(baslik, etiket, liste, payda))
    except RuntimeError as e:
        print(e)
        return 1
    metin = "\n".join(rapor)
    print(metin)
    ozet = os.environ.get("GITHUB_STEP_SUMMARY")
    if ozet:
        with open(ozet, "a", encoding="utf-8") as f:
            f.write(metin + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
