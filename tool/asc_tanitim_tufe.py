"""App Store "Tanıtım metni"ni (TR) her ay TÜFE cümlesiyle günceller.

Neden (müşteri raporu 30 Eki 21:15 #3, yasin "yap"): Tanıtım metni
(Promotional Text, 170 karakter) sürüm göndermeden ve incelemesiz değişir.
Ayın 3'ü enflasyon merakının zirvesi; "Ekim ayında yıllık enflasyon %x oldu.
Birikimin enflasyonu geçti mi?" sayfaya gelen kişinin okuduğu ilk satır olur.
`ASO_2026_09.md` §3 bunu "her ay elle" diyordu, elle yapılmıyordu.

Kurallar:
- **İlk metin onaylı.** Kalıp `store_listing/ios/tr/tanitim_tufe.json`;
  `onay: true` olmadan `--uygula` da KURU koşar (metni yazar, mağazaya
  dokunmaz). yasin ilk metni görüp onaylayınca bayrak true yapılır.
- **Uydurma sayı yok.** Yıllık oran `inflation_index`'ten (uygulamanın ve
  web hesaplayıcısının kullandığı tablo; `tufe_web.py` ile aynı salt okunur
  sorgu, aynı seri süzgeci) hesaplanır: bu ay / 12 ay önce − 1. Geçen ayın
  verisi henüz yoksa (TÜİK açıklamadı, çekim gecikti) HİÇBİR ŞEY yazılmaz;
  iş 3-5'inde tekrar dener. 12 ay önceki ay aynı seride yoksa yine yazılmaz.
- **170 karakter.** Aşarsa yazılmaz (Apple reddeder; kesilmiş cümle olmaz).
- **İdempotent.** Mağazadaki metin aynıysa PATCH yok.
- Yazılan yer: yayındaki (READY_FOR_SALE) sürümün `tr` yerelleştirmesi ve
  varsa hazırlanan sürümünki (sonraki sürüm eski metni geri getirmesin).
  Play'de karşılığı yok (kapsam dışı).
- Repo herkese açık: anahtar/token basılmaz; yalnız metin (kamuya açık
  bilgi) ve ASC'nin hata mesajı.

    SUPABASE_ACCESS_TOKEN_EU=... ASC_*=... python tool/asc_tanitim_tufe.py            # kuru
    SUPABASE_ACCESS_TOKEN_EU=... ASC_*=... python tool/asc_tanitim_tufe.py --uygula   # yazar (onay: true ise)
"""
from __future__ import annotations

import argparse
import datetime as dt
import importlib.util
import io
import json
import os
import sys
from pathlib import Path

if __name__ == "__main__":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

KOK = Path(__file__).resolve().parent.parent
AYAR = KOK / "store_listing/ios/tr/tanitim_tufe.json"
BUNDLE_ID = "com.sandik.app"
API = "https://api.appstoreconnect.apple.com/v1"
SINIR = 170
AYLAR = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz",
         "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]
# Mağazada değişebilen sürüm durumları (Tanıtım metni incelemesiz yazılır).
YAZILABILIR = {"READY_FOR_SALE", "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
               "REJECTED", "METADATA_REJECTED"}


def _tufe_web():
    yol = Path(__file__).with_name("tufe_web.py")
    spec = importlib.util.spec_from_file_location("tufe_web", yol)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _onceki_ay(bugun: dt.date) -> str:
    y, m = (bugun.year, bugun.month - 1) if bugun.month > 1 else (bugun.year - 1, 12)
    return f"{y:04d}-{m:02d}"


def tr_yuzde(x: float) -> str:
    """32.8749 → '32,87' (TÜİK gibi iki hane)."""
    return f"{x:.2f}".replace(".", ",")


def metin_kur(aylar: list[dict], bugun: dt.date, kalip: str) -> tuple[str | None, str]:
    """(metin, açıklama). Metin yoksa None ve neden. Saf; test edilir.

    `aylar` = `tufe_web.json_kur(...)["aylar"]` (tek seri, sıralı, bu ay hariç).
    """
    hedef = _onceki_ay(bugun)
    endeks = {a["ay"]: float(a["endeks"]) for a in aylar}
    if hedef not in endeks:
        son = aylar[-1]["ay"] if aylar else "yok"
        return None, f"{hedef} verisi henüz yok (son ay: {son}); yazılmadı."
    y, m = int(hedef[:4]), int(hedef[5:])
    gecen_yil = f"{y - 1:04d}-{m:02d}"
    if gecen_yil not in endeks or endeks[gecen_yil] <= 0:
        return None, f"{gecen_yil} aynı seride yok; yıllık oran hesaplanamaz."
    yillik = (endeks[hedef] / endeks[gecen_yil] - 1) * 100
    metin = kalip.format(ay=AYLAR[m - 1], yillik=tr_yuzde(yillik))
    if len(metin) > SINIR:
        return None, f"metin {len(metin)} karakter (> {SINIR}); yazılmadı."
    return metin, f"{hedef}: yıllık %{tr_yuzde(yillik)} ({len(metin)} karakter)."


class Asc:
    def __init__(self):
        import jwt
        import requests
        import time
        anahtar = os.environ.get("ASC_KEY_CONTENT", "")
        kid = os.environ.get("ASC_KEY_ID", "")
        iss = os.environ.get("ASC_ISSUER_ID", "")
        if not (anahtar and kid and iss):
            sys.exit("ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_CONTENT yok.")
        simdi = int(time.time())
        tok = jwt.encode(
            {"iss": iss, "iat": simdi, "exp": simdi + 900, "aud": "appstoreconnect-v1"},
            anahtar, algorithm="ES256", headers={"kid": kid, "typ": "JWT"})
        self.s = requests.Session()
        self.s.headers["Authorization"] = f"Bearer {tok}"

    def _c(self, r):
        if r.status_code >= 400:
            # Gövde ASC'nin hata mesajıdır; anahtar içermez.
            sys.exit(f"ASC {r.request.method} {r.url} → {r.status_code}: {r.text[:500]}")
        return r.json() if r.content else {}

    def get(self, yol, **p):
        return self._c(self.s.get(f"{API}{yol}", params=p, timeout=30))

    def patch(self, yol, veri):
        return self._c(self.s.patch(f"{API}{yol}", json={"data": veri}, timeout=30))


def magazaya_yaz(metin: str) -> None:
    asc = Asc()
    app = asc.get("/apps", **{"filter[bundleId]": BUNDLE_ID})["data"]
    if not app:
        sys.exit("Uygulama bulunamadı.")
    surumler = asc.get(f"/apps/{app[0]['id']}/appStoreVersions", limit=5,
                       **{"filter[platform]": "IOS"})["data"]
    yazilan = 0
    for v in surumler:
        durum = v["attributes"].get("appStoreState")
        if durum not in YAZILABILIR:
            continue
        for loc in asc.get(f"/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"]:
            if not str(loc["attributes"].get("locale", "")).lower().startswith("tr"):
                continue
            ad = f"{v['attributes'].get('versionString')} ({durum})"
            if loc["attributes"].get("promotionalText") == metin:
                print(f"{ad}: zaten aynı, değişiklik yok.")
                continue
            asc.patch(f"/appStoreVersionLocalizations/{loc['id']}", {
                "type": "appStoreVersionLocalizations", "id": loc["id"],
                "attributes": {"promotionalText": metin}})
            print(f"{ad}: Tanıtım metni yazıldı.")
            yazilan += 1
    if yazilan == 0:
        print("Yazılan yerelleştirme yok (aynı ya da tr yerelleştirmesi yok).")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--uygula", action="store_true")
    ap.add_argument("--bugun", help="YYYY-MM-DD (deneme için)")
    a = ap.parse_args()
    ayar = json.loads(AYAR.read_text(encoding="utf-8"))
    token = os.environ.get("SUPABASE_ACCESS_TOKEN_EU") or os.environ.get("SUPABASE_ACCESS_TOKEN")
    if not token:
        sys.exit("SUPABASE_ACCESS_TOKEN_EU / SUPABASE_ACCESS_TOKEN yok")
    bugun = dt.date.fromisoformat(a.bugun) if a.bugun else dt.date.today()
    tw = _tufe_web()
    aylar = tw.json_kur(tw.sorgula(token), bugun)["aylar"]
    metin, aciklama = metin_kur(aylar, bugun, ayar["kalip"])
    print(aciklama)
    ozet = os.environ.get("GITHUB_STEP_SUMMARY")
    if metin:
        print(f"METİN: {metin}")
        if ozet:
            with open(ozet, "a", encoding="utf-8") as f:
                f.write(f"### Tanıtım metni\n\n> {metin}\n\n{aciklama}\n")
    if not metin:
        return
    if not a.uygula:
        print("Kuru koşu: mağazaya yazılmadı.")
        return
    if not ayar.get("onay"):
        print("Kalıp henüz onaylı değil (tanitim_tufe.json 'onay': false): mağazaya yazılmadı.")
        return
    magazaya_yaz(metin)


if __name__ == "__main__":
    main()
