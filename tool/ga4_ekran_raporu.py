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
import pathlib
import re
import sys
import time

API = "https://analyticsdata.googleapis.com/v1beta/properties/{}:runReport"
KAPSAM = "https://www.googleapis.com/auth/analytics.readonly"
ESIK = 0.03
DONEMLER = (7, 30)
# Kayıt hunisi (2026-11-20): kayıt formunun ince adımları ayrı olay ADI
# olarak gider (`AnalyticsService.logKayitAdimi`), boyut tanımı gerekmez.
HUNI = {"orGroup": {"expressions": [
    {"filter": {"fieldName": "eventName",
                "stringFilter": {"matchType": "BEGINS_WITH", "value": on}}}
    for on in ("kayit_", "sifre_sifirlama_", "sign_up", "demo_", "login")]}}
# Premium hunisi (2026-11-26): RevenueCat'te 0 deneme/0 abone çıktı; kapı gösterimi
# → satın alma başlatma → tamamlama olay adıyla okunur (boyut tanımı gerekmez).
# Başlatma 0 ise teklif/ekran sorunu, doluysa ve tamamlama 0 ise akış sorunu.
PREMIUM_HUNI = {"orGroup": {"expressions": [
    {"filter": {"fieldName": "eventName",
                "stringFilter": {"matchType": "BEGINS_WITH", "value": "premium_"}}}]}}
# Türkçe ad ve Premium işareti (yasin 2026-11-21, "burada açık
# bırakmamalıyız, hangi featureların kullanıldığını net şekilde görmeliyiz").
# Özellikler `Ozellik` enum'undan OKUNUR (tek kaynak, rapor kayamaz). Ekran
# adları burada; `ekran_olcumu_test` her rota adının, sekmenin ve kök kapı
# anahtarının bu sözlükte olduğunu kilitler: adı olmayan yeni ekran CI'da
# kırılır. Bilinen ama dönemde hiç görülmeyen satır tabloya 0 ile girer:
# "kimse kullanmadı" da bir sonuç, eksik satır sanılmasın.
EKRANLAR = {
    "sekme_ana": ("Ana sayfa", False),
    "sekme_portfoy": ("Portföy sekmesi", False),
    "sekme_performans": ("Performans sekmesi", False),
    "sekme_profil": ("Profil sekmesi", False),
    "add_asset": ("Varlık ekle", False),
    "add_watchlist": ("Takibe ekle", False),
    "all_transactions": ("Tüm hareketler", False),
    "analiz_notu": ("Analiz notu", True),
    "asset_detail": ("Varlık sayfası", False),
    "asset_not_found": ("Varlık bulunamadı", False),
    "aylik_rapor": ("Aylık rapor", True),
    "bulk_add_asset": ("Toplu ekleme", False),
    "comparison": ("Karşılaştırma", False),
    "csv_import": ("Ekstreden içe aktarma", False),
    "demo_kabugu": ("Demo", False),
    "demo_sekmeleri": ("Demo sekmeleri", False),
    "forgot_password": ("Şifremi unuttum", False),
    "genel_arama": ("Genel arama", False),
    "hacim_detay": ("Hacim radarı ayrıntısı", True),
    "hafta_ozeti": ("Haftanın özeti", False),
    "halka_arz": ("Halka arz", False),
    "kayitli_cihazlar": ("Kayıtlı cihazlar", False),
    "kullanici_adi": ("Kullanıcı adı", False),
    "legal_doc": ("Yasal metin", False),
    "legal_doc_okuma": ("Yasal metin (okuma)", False),
    "otp_verification": ("Doğrulama kodu", False),
    "ozel_gosterge_editor": ("Özel gösterge düzenleyici", True),
    "para_akisi_detay": ("Fon para akışı ayrıntısı", True),
    "partnership_requests": ("Ortaklık istekleri", False),
    "paywall": ("Premium satın alma", False),
    "portfolio_performance": ("Performans ayrıntısı", False),
    "portfoy_xray": ("Portföy X-Ray", True),
    "portfoy_yonetimi": ("Portföy yönetimi", False),
    "price_alerts": ("Fiyat alarmları", False),
    "price_alert_created": ("Alarm kuruldu", False),
    "push_diagnostics": ("Bildirim tanılama", False),
    "recap": ("Dönem özeti", False),
    "register": ("Kayıt", False),
    "settings": ("Ayarlar", False),
    "signal_settings": ("Sinyal ayarları", False),
    "tam_ekran_grafik": ("Tam ekran grafik", False),
    "temettu_tahmini": ("Temettü tahmini", True),
    "widget_install_sheet": ("Widget kurulum rehberi", False),
    "yaris_giris_ekrani": ("Yarış", False),
    "yillik_rapor": ("Yıllık rapor", True),
    "zirve_giris_ekrani": ("Zirve", False),
    # Kök kapı ekranları (`_AuthGate` anahtarı, `-` → `_`).
    "auth_offline": ("Bağlantı yok (açılış)", False),
    "cihaz_hata": ("Cihaz doğrulama hatası", False),
    "cihaz_otp": ("Cihaz doğrulama kodu", False),
    "disclaimer": ("Yatırım uyarısı onayı", False),
    "karsilama": ("Karşılama", False),
    "lock": ("Kilit ekranı", False),
    "lock_offer": ("Kilit önerisi", False),
    "login": ("Giriş", False),
    "onboarding": ("Tanıtım turu", False),
    "yasal_kapi": ("Yasal onay kapısı", False),
}
YUZEYLER = {
    "home_widget": ("Ana ekran widget'ı ve Canlı Etkinlik", False),
    "varlik_widget": ("Tek varlık widget'ı", False),
}
# "(not set)": özel boyut 2026-11-19'da açıldı, öncesindeki olaylar boyutsuz
# kalır; ekranlarda 2026-11-20 öncesi build'lerin adsız otomatik kaydı.
ADSIZ = "(not set): boyut öncesi ya da eski sürüm"
OZELLIK_DOSYASI = (pathlib.Path(__file__).resolve().parent.parent
                   / "lib/services/ozellik_olcumu.dart")


def dart_ozellikleri(metin):
    """`Ozellik` enum'u → {kod: (Türkçe ad, premium)}."""
    desen = re.compile(
        r"^\s*[a-z]\w*\(\s*'([a-z0-9_]+)',\s*'((?:[^'\\]|\\.)*)'"
        r"\s*(,\s*premium:\s*true)?\s*,?\s*\)[,;]", re.M)
    return {m.group(1): (m.group(2).replace("\\'", "'"), bool(m.group(3)))
            for m in desen.finditer(metin)}


def _ozellik_adlari():
    try:
        return dart_ozellikleri(OZELLIK_DOSYASI.read_text(encoding="utf-8"))
    except OSError:
        return {}


# (başlık, boyut, olay süzgeci: ad ya da hazır ifade, sayı metriği etiketi,
#  ad sözlüğü: kod → (Türkçe ad, premium) ya da None)
KIRILIMLAR = (
    ("Ekranlar", "unifiedScreenName", None, "görüntüleme", EKRANLAR),
    ("Özellik kullanımı (ozellik_kullanildi)", "customEvent:ozellik",
     "ozellik_kullanildi", "olay", "ozellik"),
    ("Widget dokunuşu (widget_tapped)", "customEvent:surface",
     "widget_tapped", "olay", YUZEYLER),
    ("Premium hunisi (premium_gate_shown → premium_upgrade_started → "
     "premium_upgrade_completed)", "eventName", PREMIUM_HUNI, "olay", None),
    ("Kayıt hunisi (girişten önce: girişli payı burada anlamsız)", "eventName",
     HUNI, "olay", None),
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
    if isinstance(ad, dict):
        return ad
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


def tamamla(liste, adlar):
    """Bilinen ama dönemde hiç görülmeyen kodları 0 satırıyla ekler, sona."""
    gorulen = {s["ad"] for s in liste}
    return liste + [{"ad": k, "sayi": 0, "kullanici": 0, "sure": 0,
                     "girisli": 0, "pay": 0} for k in sorted(adlar)
                    if k not in gorulen]


def _goster(kod, adlar):
    if kod == "(not set)":
        return ADSIZ
    if adlar is None:
        return kod
    if kod not in adlar:
        return f"{kod} (adsız kod)"
    ad, premium = adlar[kod]
    return f"{ad}{' ★' if premium else ''} `{kod}`"


def tablo(baslik, etiket, liste, payda, adlar=None):
    alt = [s for s in liste if s["pay"] < ESIK]
    satir = [f"#### {baslik}", "",
             f"| Ad | {etiket} | kullanıcı | kişi başı süre | girişli | girişli payı |",
             "|---|---:|---:|---:|---:|---:|"]
    for s in liste:
        isaret = " ⚠" if s["pay"] < ESIK else ""
        satir.append(f"| {_goster(s['ad'], adlar)} | {s['sayi']} | {s['kullanici']} | "
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
             f"%{ESIK * 100:.0f}'ünden azı. ★ = Premium (kilit açıkken sayılır). "
             "Özellik ve kart satırları kişi başına günde bir kez sayılır.", ""]
    ozellikler = _ozellik_adlari()
    try:
        for gun in DONEMLER:
            p = satirlar(_sor(tok, mulk, payda_istegi(gun))).get("", [0])[0]
            payda = int(p)
            rapor += [f"### Son {gun} gün (girişli aktif kullanıcı: {payda})", ""]
            for baslik, boyut, olay, etiket, adlar in KIRILIMLAR:
                adlar = ozellikler if adlar == "ozellik" else adlar
                tum, girisli = istekler(gun, boyut, olay)
                liste = birlestir(_sor(tok, mulk, tum), _sor(tok, mulk, girisli), payda)
                if adlar:
                    liste = tamamla(liste, adlar)
                rapor.append(tablo(baslik, etiket, liste, payda, adlar))
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
