"""Mağaza yorumları: haftalık okuma + Türkçe yanıt taslağı (2026-10-20).

Neden (müşteri raporu 20 Eki 17:15 #1, yasin "yap"): kitle küçük, her tek
yıldızlı yorum ortalamayı oynatıyor; geliştirici yanıtı yorumun altında
görünür ve kullanıcı puanını güncelleyebilir. `aso_olcum.py` yorum SAYISINI
ölçüyordu, içeriğini okuyan ve hata bildirimlerini toplayan bir şey yoktu.

Ne yapar: son `--gun` (varsayılan 8) günün App Store ve Google Play
yorumlarını çeker, her biri için şablonla Türkçe yanıt TASLAĞI yazar ve
hata bildiren yorumları ayrı listeler. Çıktı Markdown dosyasıdır
(`--cikti`); iş akışı onu kısa ömürlü artifact olarak saklar.

Bilerek YOK:
  * Yanıt GÖNDERME. Yanıt dışarıya mesajdır; her biri yasin'in tek tek
    onayıyla, ayrı bir adımda (sonraki iş). Bu betik yalnız GET yapar.
  * Yapay zekâ çağrısı ve yeni secret. Taslak puan + anahtar kelime şablonu.
  * Yorumcu adı. Dosyaya yazılmaz (mağazada herkese açık olsa da tekrar
    yayınlamaya gerek yok). Repo herkese açık: yorum metni LOG'a basılmaz,
    adım özetine yalnız sayılar yazılır.

Kimlik: ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_CONTENT (fastlane ve In-App
Event işiyle aynı) ve PLAY_SERVICE_ACCOUNT_JSON (Play yükleme işiyle aynı).
Biri yoksa o mağaza atlanır, iş düşmez.

    pip install pyjwt cryptography requests
    python tool/magaza_yorumlari.py --cikti yorumlar.md
"""
import argparse
import datetime as dt
import json
import os
import re
import sys
import time

APP_ID = "6786837699"           # aso_olcum.py ile aynı
PAKET = "com.sandik.app"
ASC_API = "https://api.appstoreconnect.apple.com/v1"
PLAY_API = "https://androidpublisher.googleapis.com/androidpublisher/v3"

# Hata bildirimi sayılan kelimeler (küçük harf, Türkçe + İngilizce).
HATA = re.compile(
    r"çök|crash|açılmıyor|acilmiyor|açılmadı|hata|error|donuyor|dondu|kapanıyor|"
    r"güncellenmiyor|guncellenmiyor|yanlış|yanlis|giriş yapam|giris yapam|"
    r"bug|çalışmıyor|calismiyor|yüklenmiyor|yuklenmiyor|boş ekran|bos ekran")


def taslak(puan: int, metin: str) -> str:
    """Şablon yanıt (saf; test edilir). Söz verilmez, tarih verilmez."""
    hata = hata_mi(metin)
    if hata:
        return ("Yazdığın için teşekkürler, bu bizim için çok değerli. Yaşadığın sorunu "
                "inceliyoruz. Ayarlar › Destek'ten telefon modelini ve uygulama sürümünü "
                "yazarsan daha hızlı çözeriz.")
    if puan <= 2:
        return ("Geri bildirimin için teşekkürler, beklentini karşılayamadığımız için üzgünüz. "
                "Neyi daha iyi yapabileceğimizi Ayarlar › Destek'ten yazarsan doğrudan "
                "bakarız.")
    if puan == 3:
        return ("Teşekkürler! Sandık'ı neyin daha iyi yapacağını merak ediyoruz; "
                "önerini Ayarlar › Destek'ten yazabilirsin.")
    return ("Güzel sözlerin için çok teşekkürler! Sandık'ı her sürümde daha iyi yapmaya "
            "devam ediyoruz.")


def kucuk(metin: str) -> str:
    # Python "İ".lower() = "i̇" (i + U+0307) verir; büyük harfle yazılmış
    # "GÜNCELLENMİYOR" kalıba uymaz. Türkçe I/İ önce elle çevrilir.
    return (metin or "").replace("I", "ı").replace("İ", "i").lower()


def hata_mi(metin: str) -> bool:
    return bool(HATA.search(kucuk(metin)))


# ── App Store ───────────────────────────────────────────────────────────
def asc_yorumlari(esik: dt.datetime) -> list[dict] | None:
    anahtar = os.environ.get("ASC_KEY_CONTENT", "")
    kid = os.environ.get("ASC_KEY_ID", "")
    iss = os.environ.get("ASC_ISSUER_ID", "")
    if not (anahtar and kid and iss):
        return None
    import jwt
    import requests
    simdi = int(time.time())
    jeton = jwt.encode(
        {"iss": iss, "iat": simdi, "exp": simdi + 15 * 60, "aud": "appstoreconnect-v1"},
        anahtar, algorithm="ES256", headers={"kid": kid, "typ": "JWT"})
    url = f"{ASC_API}/apps/{APP_ID}/customerReviews"
    p = {"sort": "-createdDate", "limit": 200,
         "fields[customerReviews]": "rating,title,body,createdDate,territory"}
    out = []
    while url:
        r = requests.get(url, params=p, headers={"Authorization": f"Bearer {jeton}"}, timeout=30)
        if r.status_code >= 400:
            # Gövde Apple'ın hata metnidir; anahtar ve yorum içermez.
            raise RuntimeError(f"ASC {r.status_code}: {r.text[:300]}")
        veri = r.json()
        dur = False
        for d in veri.get("data", []):
            a = d.get("attributes", {})
            t = dt.datetime.fromisoformat(a["createdDate"].replace("Z", "+00:00"))
            if t < esik:
                dur = True
                break
            out.append({"magaza": "App Store", "puan": int(a.get("rating") or 0),
                        "tarih": t, "surum": None, "ulke": a.get("territory"),
                        "metin": " — ".join(x for x in (a.get("title"), a.get("body")) if x)})
        url = None if dur else veri.get("links", {}).get("next")
        p = None
    return out


# ── Google Play ─────────────────────────────────────────────────────────
def play_yorumlari(esik: dt.datetime) -> list[dict] | None:
    ham = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON", "")
    if not ham:
        return None
    import jwt
    import requests
    sa = json.loads(ham)
    simdi = int(time.time())
    iddia = jwt.encode(
        {"iss": sa["client_email"], "scope": "https://www.googleapis.com/auth/androidpublisher",
         "aud": "https://oauth2.googleapis.com/token", "iat": simdi, "exp": simdi + 3600},
        sa["private_key"], algorithm="RS256")
    t = requests.post("https://oauth2.googleapis.com/token", timeout=30, data={
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": iddia})
    if t.status_code >= 400:
        raise RuntimeError(f"Google OAuth {t.status_code}")
    erisim = t.json()["access_token"]
    url = f"{PLAY_API}/applications/{PAKET}/reviews"
    p = {"maxResults": 100, "translationLanguage": "tr"}
    out = []
    while True:
        r = requests.get(url, params=p, headers={"Authorization": f"Bearer {erisim}"}, timeout=30)
        if r.status_code >= 400:
            raise RuntimeError(f"Play {r.status_code}: {r.text[:300]}")
        veri = r.json()
        for y in veri.get("reviews", []):
            for c in y.get("comments", []):
                u = c.get("userComment")
                if not u:
                    continue
                zaman = dt.datetime.fromtimestamp(
                    int(u.get("lastModified", {}).get("seconds", 0)), tz=dt.timezone.utc)
                if zaman < esik:
                    continue
                out.append({"magaza": "Google Play", "puan": int(u.get("starRating") or 0),
                            "tarih": zaman, "surum": u.get("appVersionName"),
                            "ulke": u.get("reviewerLanguage"),
                            "metin": (u.get("text") or "").strip()})
        sayfa = (veri.get("tokenPagination") or {}).get("nextPageToken")
        if not sayfa:
            break
        p = {"maxResults": 100, "translationLanguage": "tr", "token": sayfa}
    return out


# ── Rapor ───────────────────────────────────────────────────────────────
def rapor(yorumlar: list[dict], atlanan: list[str], gun: int) -> str:
    """Markdown (saf; test edilir). Yorumcu adı yok."""
    yorumlar = sorted(yorumlar, key=lambda y: (y["puan"], -y["tarih"].timestamp()))
    s = [f"# Mağaza yorumları — son {gun} gün", ""]
    for a in atlanan:
        s.append(f"_{a} atlandı (kimlik yok ya da erişim reddedildi)._")
    if atlanan:
        s.append("")
    hatalar = [y for y in yorumlar if hata_mi(y["metin"])]
    s += ["## Hata bildirimleri", ""]
    if hatalar:
        for y in hatalar:
            s.append(f"- {y['magaza']} · {y['puan']}★ · sürüm {y['surum'] or '?'} · "
                     f"{y['tarih']:%d.%m.%Y}: {y['metin']}")
    else:
        s.append("Yok.")
    s += ["", "## Yorumlar ve yanıt taslakları", ""]
    if not yorumlar:
        s.append("Bu dönemde yeni yorum yok.")
    for y in yorumlar:
        s += [f"### {y['magaza']} · {y['puan']}★ · {y['tarih']:%d.%m.%Y}"
              + (f" · sürüm {y['surum']}" if y["surum"] else "")
              + (f" · {y['ulke']}" if y["ulke"] else ""),
              "", f"> {y['metin'] or '(yalnız puan)'}", "",
              f"**Taslak yanıt:** {taslak(y['puan'], y['metin'])}", ""]
    s += ["---", "Yanıtlar GÖNDERİLMEDİ. Göndermek için yasin'in tek tek onayı gerekir."]
    return "\n".join(s) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gun", type=int, default=8)
    ap.add_argument("--cikti", default="magaza_yorumlari.md")
    a = ap.parse_args()
    esik = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=a.gun)
    yorumlar, atlanan = [], []
    for ad, f in (("App Store", asc_yorumlari), ("Google Play", play_yorumlari)):
        try:
            r = f(esik)
        except Exception as e:  # noqa: BLE001 — bir mağaza düşerse diğeri sürer
            # Yalnız hata türü ve HTTP kodu: mesaj gövdesi yanıt/anahtar
            # parçası taşıyabilir, repo herkese açık.
            kod = getattr(getattr(e, "response", None), "status_code", "")
            print(f"{ad}: {type(e).__name__} {kod}".rstrip())
            r = None
        if r is None:
            atlanan.append(ad)
        else:
            yorumlar += r
    with open(a.cikti, "w", encoding="utf-8") as f:
        f.write(rapor(yorumlar, atlanan, a.gun))
    # Log'a ve özete YALNIZ sayılar (repo herkese açık).
    ozet = (f"## Mağaza yorumları (son {a.gun} gün)\n\n"
            f"- Yeni yorum: {len(yorumlar)}\n"
            f"- Hata bildirimi: {sum(hata_mi(y['metin']) for y in yorumlar)}\n"
            f"- 1–2 yıldız: {sum(y['puan'] <= 2 for y in yorumlar)}\n"
            + "".join(f"- {x}: atlandı\n" for x in atlanan)
            + "\nAyrıntı ve yanıt taslakları iş artifact'inde (`magaza-yorumlari`).\n")
    print(ozet)
    yol = os.environ.get("GITHUB_STEP_SUMMARY")
    if yol:
        with open(yol, "a", encoding="utf-8") as f:
            f.write(ozet)
    return 0


if __name__ == "__main__":
    sys.exit(main())
