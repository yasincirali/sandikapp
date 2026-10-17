"""ASO ölçümü — App Store + Google Play TR, salt okunur, tek JSON.

Neden ayrı betik ve CI'da: bulut oturumunun ağ politikası Apple ve Google
mağaza uçlarını kapatıyor; `aso_siralama.py` yalnız yasin'in makinesinde
koşuyordu ve ölçüm defteri 20 Eylül'den beri boş kaldı. Bu betik GitHub
Actions'ta (`aso-olcum.yml`) haftalık koşar, sonucu artifact olarak bırakır.

Ölçtükleri:
  1. App Store TR arama sırası (iTunes Search API) + her sorgunun ilk 10'u
  2. Google Play TR arama sırası (google-play-scraper) + ilk 10
  3. Kendi kayıtlarımız: puan, yorum, diller, sürüm (iTunes lookup, Play)
  4. ASC'de CANLI ve hazırlanan metadata: ad, alt başlık, anahtar kelime,
     tanıtım metni — YALNIZ GET (ASC_* secret'ları varsa). Hiçbir şey yazmaz.

    pip install requests pyjwt cryptography google-play-scraper
    python tool/aso_olcum.py > aso.json
"""
import json
import os
import sys
import time
import urllib.parse
from datetime import date

import requests

APP_ID = 6786837699
BUNDLE_ID = "com.sandik.app"
PLAY_ID = "com.sandik.app"
ULKE = "tr"

# Eylül planının sorguları + marka varyantları + kategori kelimeleri.
# Marka sorguları bilinçli olarak çok: "adı yazıldığında üstte çıkmak"
# (yasin 2026-10-17) doğrudan bunlarla ölçülür.
SORGULAR = [
    "sandık", "sandik", "Sandık", "sandık portföy", "sandık uygulama",
    "sandık portföy takibi", "sandik portfoy",
    "portföy takibi", "portföy takip", "portföy", "portfoy",
    "hisse takip", "hisse senedi takip", "borsa takip", "bist",
    "fon takip", "tefas", "yatırım takip", "varlık takip",
    "altın takip", "döviz takip", "temettü takip", "temettü",
    "enflasyon", "reel getiri", "kâr zarar", "birikim",
]


def itunes_ara(term, limit=200):
    q = urllib.parse.urlencode(
        {"term": term, "country": ULKE, "entity": "software", "limit": limit})
    r = requests.get("https://itunes.apple.com/search?" + q, timeout=30)
    r.raise_for_status()
    return r.json()["results"]


def ozet(x):
    return {
        "ad": x.get("trackName"), "id": x.get("trackId"),
        "puan": round(x.get("averageUserRating") or 0, 2),
        "yorum": x.get("userRatingCount") or 0,
        "satici": x.get("sellerName"),
        "cikis": (x.get("releaseDate") or "")[:10],
        "guncel": (x.get("currentVersionReleaseDate") or "")[:10],
    }


def app_store():
    out = {}
    for t in SORGULAR:
        try:
            res = itunes_ara(t)
            ids = [x["trackId"] for x in res]
            out[t] = {
                "toplam": len(res),
                "sira": ids.index(APP_ID) + 1 if APP_ID in ids else None,
                "ilk10": [ozet(x) for x in res[:10]],
            }
        except Exception as e:  # tek sorgu ölçümü kesmesin
            out[t] = {"hata": type(e).__name__}
        time.sleep(1.5)  # API ~20 istek/dk sınırı
    return out


def kendi_app_store():
    r = requests.get("https://itunes.apple.com/lookup",
                     params={"id": APP_ID, "country": ULKE}, timeout=30)
    d = r.json().get("results") or []
    if not d:
        return None
    a = d[0]
    return {**ozet(a), "surum": a.get("version"),
            "diller": a.get("languageCodesISO2A"),
            "tur": a.get("primaryGenreName"), "turler": a.get("genres"),
            "boyut_mb": round(int(a.get("fileSizeBytes") or 0) / 1e6, 1),
            "aciklama_bas": (a.get("description") or "")[:400],
            "surum_notu": (a.get("releaseNotes") or "")[:300],
            "ekran_sayisi": len(a.get("screenshotUrls") or []),
            "ipad": len(a.get("ipadScreenshotUrls") or [])}


def play():
    try:
        from google_play_scraper import app as papp, search
    except ImportError:
        return {"hata": "google-play-scraper yok"}
    out = {"sorgular": {}}
    try:
        a = papp(PLAY_ID, lang="tr", country="tr")
        out["kendi"] = {k: a.get(k) for k in (
            "title", "summary", "score", "ratings", "reviews", "installs",
            "realInstalls", "version", "updated", "genre", "contentRating")}
    except Exception as e:
        out["kendi"] = {"hata": type(e).__name__}
    for t in SORGULAR:
        try:
            res = search(t, lang="tr", country="tr", n_hits=30)
            ids = [x.get("appId") for x in res]
            out["sorgular"][t] = {
                "toplam": len(res),
                "sira": ids.index(PLAY_ID) + 1 if PLAY_ID in ids else None,
                "ilk10": [{"ad": x.get("title"), "id": x.get("appId"),
                           "puan": x.get("score"), "kurulum": x.get("installs")}
                          for x in res[:10]],
            }
        except Exception as e:
            out["sorgular"][t] = {"hata": type(e).__name__}
        time.sleep(1)
    return out


def asc_metadata():
    """ASC'den salt okunur metadata. Secret yoksa sessizce atlanır."""
    if not os.environ.get("ASC_KEY_CONTENT"):
        return {"atlandi": "ASC_* secret yok"}
    import jwt
    simdi = int(time.time())
    tok = jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": simdi, "exp": simdi + 900,
         "aud": "appstoreconnect-v1"},
        os.environ["ASC_KEY_CONTENT"], algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
    s = requests.Session()
    s.headers["Authorization"] = f"Bearer {tok}"
    api = "https://api.appstoreconnect.apple.com/v1"

    def get(yol, **p):
        r = s.get(api + yol, params=p, timeout=30)
        if r.status_code >= 400:
            return {"hata": r.status_code}
        return r.json()

    app = get("/apps", **{"filter[bundleId]": BUNDLE_ID})
    if "hata" in app or not app.get("data"):
        return {"hata": "uygulama bulunamadı"}
    aid = app["data"][0]["id"]
    out = {"primaryLocale": app["data"][0]["attributes"].get("primaryLocale"),
           "appInfos": [], "surumler": []}
    infos = get(f"/apps/{aid}/appInfos")
    for inf in infos.get("data", []):
        locs = get(f"/appInfos/{inf['id']}/appInfoLocalizations")
        out["appInfos"].append({
            "durum": inf["attributes"].get("appStoreState") or inf["attributes"].get("state"),
            "yerel": [{"dil": l["attributes"].get("locale"),
                       "ad": l["attributes"].get("name"),
                       "altbaslik": l["attributes"].get("subtitle")}
                      for l in locs.get("data", [])]})
    vers = get(f"/apps/{aid}/appStoreVersions", limit=4,
               **{"filter[platform]": "IOS"})
    for v in vers.get("data", []):
        locs = get(f"/appStoreVersions/{v['id']}/appStoreVersionLocalizations")
        out["surumler"].append({
            "surum": v["attributes"].get("versionString"),
            "durum": v["attributes"].get("appStoreState"),
            "yerel": [{"dil": l["attributes"].get("locale"),
                       "anahtar": l["attributes"].get("keywords"),
                       "tanitim": l["attributes"].get("promotionalText"),
                       "aciklama_bas": (l["attributes"].get("description") or "")[:200]}
                      for l in locs.get("data", [])]})
    return out


def main():
    sonuc = {"tarih": date.today().isoformat(),
             "app_store_kendi": kendi_app_store(),
             "asc": asc_metadata(),
             "app_store": app_store(),
             "play": play()}
    # Bölüm başına TEK satır: Actions logu satır başına zaman damgası ekler
    # ve uzun çıktının başını kırpabilir; satır satır okunur kalsın.
    for k, v in sonuc.items():
        print(f"ASO|{k}|" + json.dumps(v, ensure_ascii=False), flush=True)
    # Kısa tablo stderr'e: Actions logunda okunur.
    print("\nsorgu | App Store sıra | Play sıra", file=sys.stderr)
    for t in SORGULAR:
        a = sonuc["app_store"].get(t, {}).get("sira")
        p = (sonuc["play"].get("sorgular") or {}).get(t, {}).get("sira")
        print(f"{t} | {a} | {p}", file=sys.stderr)


if __name__ == "__main__":
    main()
