"""App Store In-App Event taslaklarını App Store Connect'e kurar (karar 6.5).

Kaynak: store_listing/ios/in_app_events/etkinlikler.json (+ PNG'ler,
`store_listing/build_event_graphics.py`).

Güvenlik kuralları (kullanıcı kararı 2026-09-30: "gönderimi ben yapayım" —
son hâli incelemeye göndermeden önce kullanıcıya gösterilir):
  * Etkinlik yalnız TASLAK kurulur; incelemeye GÖNDERİLMEZ (o adım App
    Store Connect'te elle, kullanıcı gördükten sonra).
  * İdempotent ve ONARICI: aynı `referans` (referenceName) varsa yeniden
    kurulmaz; eksik dili ve eksik / yarım kalmış görseli tamamlar (ilk
    koşu 2026-09-30'da görsel onayında düştü, Kasım taslağı yarım kaldı).
  * Varsayılan KURU koşu; yazmak için `--uygula`.
  * Uygulamada tanımlı olmayan dil (ör. Türkçe yerelleştirme henüz
    eklenmediyse `tr`) atlanır ve raporlanır.

Kimlik: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_CONTENT (p8, fastlane ile aynı
GitHub secret'ları). Anahtar ekrana basılmaz.

    pip install pyjwt cryptography requests
    python tool/asc_in_app_events.py            # kuru koşu
    python tool/asc_in_app_events.py --uygula   # taslakları kur
"""
import argparse
import json
import os
import sys
import time

import jwt
import requests

KOK = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KLASOR = os.path.join(KOK, "store_listing", "ios", "in_app_events")
BUNDLE_ID = "com.sandik.app"
API = "https://api.appstoreconnect.apple.com/v1"
BOLGE = ["TUR"]  # Enflasyon günü ve yıl sonu Türkiye'ye özgü.
GORSEL_TURLERI = {"EVENT_CARD": "kart_1920x1080", "EVENT_DETAILS_PAGE": "detay_1080x1920"}


def jeton():
    anahtar = os.environ.get("ASC_KEY_CONTENT", "")
    kid = os.environ.get("ASC_KEY_ID", "")
    iss = os.environ.get("ASC_ISSUER_ID", "")
    if not (anahtar and kid and iss):
        sys.exit("ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_CONTENT ortam değişkenleri yok.")
    simdi = int(time.time())
    return jwt.encode(
        {"iss": iss, "iat": simdi, "exp": simdi + 15 * 60, "aud": "appstoreconnect-v1"},
        anahtar, algorithm="ES256", headers={"kid": kid, "typ": "JWT"})


class Asc:
    def __init__(self):
        self.s = requests.Session()
        self.s.headers["Authorization"] = f"Bearer {jeton()}"

    def _cevap(self, r):
        if r.status_code >= 400:
            # Yanıt gövdesi hata ayrıntısıdır (anahtar içermez).
            sys.exit(f"ASC {r.request.method} {r.url} → {r.status_code}: {r.text[:600]}")
        return r.json() if r.content else {}

    def get(self, yol, **p):
        return self._cevap(self.s.get(f"{API}{yol}", params=p, timeout=30))

    def post(self, yol, veri):
        return self._cevap(self.s.post(f"{API}{yol}", json={"data": veri}, timeout=30))

    def patch(self, yol, veri):
        return self._cevap(self.s.patch(f"{API}{yol}", json={"data": veri}, timeout=30))

    def delete(self, yol):
        return self._cevap(self.s.delete(f"{API}{yol}", timeout=30))


def gorsel_yukle(asc, lokal_id, tur, yol):
    veri = open(yol, "rb").read()
    rez = asc.post("/appEventScreenshots", {
        "type": "appEventScreenshots",
        "attributes": {"fileName": os.path.basename(yol), "fileSize": len(veri),
                       "appEventAssetType": tur},
        "relationships": {"appEventLocalization": {
            "data": {"type": "appEventLocalizations", "id": lokal_id}}},
    })["data"]
    for op in rez["attributes"]["uploadOperations"]:
        parca = veri[op["offset"]:op["offset"] + op["length"]]
        basliklar = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        r = requests.request(op["method"], op["url"], data=parca, headers=basliklar, timeout=60)
        if r.status_code >= 400:
            sys.exit(f"Görsel parçası yüklenemedi ({r.status_code}): {yol}")
    # Onayda YALNIZ `uploaded` — bu kaynakta `sourceFileChecksum` yok (409
    # ENTITY_ERROR.ATTRIBUTE.UNKNOWN, 2026-09-30; ekran görüntüsü API'sinden
    # farklı).
    asc.patch(f"/appEventScreenshots/{rez['id']}", {
        "type": "appEventScreenshots", "id": rez["id"],
        "attributes": {"uploaded": True},
    })


def lokal_tamamla(asc, olay_id, e, kullanilacak):
    """Etkinliğin eksik dillerini ve görsellerini tamamlar.

    Yarım kalmış görsel (teslim durumu COMPLETE / UPLOAD_COMPLETE olmayan)
    silinip yeniden yüklenir. Dönen değer: yapılan iş sayısı."""
    is_sayisi = 0
    lokaller = {x["attributes"]["locale"]: x
                for x in asc.get(f"/appEvents/{olay_id}/localizations")["data"]}
    for dil in kullanilacak:
        m = e["metin"][dil]
        lok = lokaller.get(dil)
        if lok is None:
            lok = asc.post("/appEventLocalizations", {
                "type": "appEventLocalizations",
                "attributes": {"locale": dil, "name": m["ad"],
                               "shortDescription": m["kisa"],
                               "longDescription": m["uzun"]},
                "relationships": {"appEvent": {"data": {"type": "appEvents", "id": olay_id}}},
            })["data"]
            is_sayisi += 1
        mevcut_gorsel = {}
        for g in asc.get(f"/appEventLocalizations/{lok['id']}/appEventScreenshots")["data"]:
            durum = ((g["attributes"].get("assetDeliveryState") or {}).get("state") or "")
            if durum in ("COMPLETE", "UPLOAD_COMPLETE"):
                mevcut_gorsel[g["attributes"]["appEventAssetType"]] = g["id"]
            else:
                asc.delete(f"/appEventScreenshots/{g['id']}")
                is_sayisi += 1
        for tur, ek in GORSEL_TURLERI.items():
            if tur in mevcut_gorsel:
                continue
            gorsel_yukle(asc, lok["id"], tur, os.path.join(KLASOR, f"{e['gorsel']}_{ek}.png"))
            is_sayisi += 1
    return is_sayisi


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--uygula", action="store_true", help="taslakları gerçekten kur")
    args = ap.parse_args()

    tanim = json.load(open(os.path.join(KLASOR, "etkinlikler.json"), encoding="utf-8"))
    for e in tanim["etkinlikler"]:
        for tur, ek in GORSEL_TURLERI.items():
            yol = os.path.join(KLASOR, f"{e['gorsel']}_{ek}.png")
            if not os.path.exists(yol):
                sys.exit(f"Görsel yok: {yol} (önce build_event_graphics.py)")

    asc = Asc()
    uygulamalar = asc.get("/apps", **{"filter[bundleId]": BUNDLE_ID})["data"]
    if not uygulamalar:
        sys.exit(f"{BUNDLE_ID} bulunamadı.")
    app_id = uygulamalar[0]["id"]

    diller = set()
    for info in asc.get(f"/apps/{app_id}/appInfos")["data"]:
        for lok in asc.get(f"/appInfos/{info['id']}/appInfoLocalizations")["data"]:
            diller.add(lok["attributes"]["locale"])
    print(f"Uygulamanın dilleri: {sorted(diller)}")

    mevcut = {x["attributes"]["referenceName"]: x["id"]
              for x in asc.get(f"/apps/{app_id}/appEvents", limit=200)["data"]}

    for e in tanim["etkinlikler"]:
        ref = e["referans"]
        kullanilacak = [d for d in e["metin"] if d in diller]
        if ref in mevcut:
            if not args.uygula:
                print(f"= {ref}: zaten var (uygulamada eksikleri tamamlanır)")
                continue
            n = lokal_tamamla(asc, mevcut[ref], e, kullanilacak)
            print(f"= {ref}: zaten var — {n} eksik tamamlandı")
            continue
        atlanan = [d for d in e["metin"] if d not in diller]
        print(f"+ {ref}: {e['etkinlik_baslangic']} → {e['etkinlik_bitis']}, "
              f"diller {kullanilacak}" + (f", ATLANAN {atlanan}" if atlanan else ""))
        if not kullanilacak:
            print(f"  ! {ref}: uygulamada bu dillerin hiçbiri yok — kurulmadı")
            continue
        if not args.uygula:
            continue
        olay = asc.post("/appEvents", {
            "type": "appEvents",
            "attributes": {
                "referenceName": ref,
                "badge": e["rozet"],
                "deepLink": e["derin_baglanti"],
                "primaryLocale": kullanilacak[0],
                "priority": e["oncelik"],
                "purpose": e["amac"],
                "territorySchedules": [{
                    "territories": BOLGE,
                    "publishStart": e["yayin_baslangic"],
                    "eventStart": e["etkinlik_baslangic"],
                    "eventEnd": e["etkinlik_bitis"],
                }],
            },
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        })["data"]
        lokal_tamamla(asc, olay["id"], e, kullanilacak)
        print(f"  ✓ {ref}: TASLAK kuruldu (incelemeye gönderilmedi)")

    if not args.uygula:
        print("\nKuru koşu — hiçbir şey yazılmadı. Kurmak için --uygula.")


if __name__ == "__main__":
    main()
