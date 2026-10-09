"""Mevduat banka listesi / faiz kaynaklarının erişim ve biçim ölçümü (2026-10-09).

Neden: bulut kabı TCMB/BDDK/TBB hostlarını reddediyor. Salt okunur,
anahtarsız; secret kullanmaz (public repo, log herkese açık).
"""
import io
import re
import sys
import urllib.request

UA = {"User-Agent": "Mozilla/5.0 (sandik kaynak olcum)"}


def al(url, n=None):
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=30) as r:
            b = r.read()
            print(f"\n=== {r.status} {len(b)}B {r.headers.get('Content-Type')} {url}")
            return b
    except Exception as e:  # noqa: BLE001
        print(f"\n=== HATA {url}: {e}")
        return None


def linkler(html, desen):
    s = html.decode("utf-8", "ignore")
    out = []
    for m in re.finditer(r'href="([^"]+)"[^>]*>(.*?)</a>', s, re.S):
        h, t = m.group(1), re.sub(r"<[^>]+>|\s+", " ", m.group(2)).strip()
        if re.search(desen, h + " " + t, re.I):
            out.append((t[:120], h))
    return out


def tablo_dok(b, ad):
    try:
        import pandas as pd
        sayfalar = pd.read_excel(io.BytesIO(b), sheet_name=None, header=None)
        for sn, df in sayfalar.items():
            print(f"--- {ad} / sayfa {sn} {df.shape}")
            print(df.head(40).to_string(max_colwidth=40))
    except Exception as e:  # noqa: BLE001
        print(f"--- {ad} excel okunamadı: {e}; ilk 600B: {b[:600]!r}")


TCMB = "https://www.tcmb.gov.tr/wps/wcm/connect/TR/TCMB+TR/Main+Menu/Istatistikler/Faiz+Istatistikleri/"
sayfalar = [
    TCMB + "Mevzuat/Banka+Mevduat+Azami+Faiz/",
    TCMB + "Mevzuat/Kamu+Banka+Mevduat+Azami+Faiz/",
]
indirilecek = []
for u in sayfalar:
    b = al(u)
    if not b:
        continue
    metin = re.sub(r"<script.*?</script>|<style.*?</style>", " ", b.decode("utf-8", "ignore"), flags=re.S)
    metin = re.sub(r"<[^>]+>", " ", metin)
    metin = re.sub(r"\s+", " ", metin)
    i = metin.find("Azami Faiz")
    print("  METIN:", metin[max(0, i - 200): i + 2500])
    for t, h in linkler(b, r"xls|xlsx|csv|AJPERES|html"):
        print(f"  {t!r} -> {h}")
        if re.search(r"xls|csv", h, re.I) or re.search(r"\.xls|excel", t, re.I):
            if h.startswith("/"):
                h = "https://www.tcmb.gov.tr" + h
            indirilecek.append((t, h))

for t, h in [("TRLtum_html", "https://www.tcmb.gov.tr/wps/wcm/connect/TR/TCMB+TR/File+Resources/YFA/TRLtum_html")]:
    b = al(h)
    if b:
        m = re.sub(r"<[^>]+>", " | ", b.decode("utf-8", "ignore"))
        print(re.sub(r"(\s*\|\s*)+", " | ", m)[:3000])
for t, h in indirilecek[:8]:
    b = al(h)
    if b:
        tablo_dok(b, t)

# Banka listesi adayları
for u in [
    "https://www.bddk.org.tr/Kurulus/Liste/77",
    "https://www.tbb.org.tr/tr/bankacilik/banka-ve-sube-bilgileri/bankalarimiz/22",
]:
    b = al(u)
    if b:
        s = b.decode("utf-8", "ignore")
        adlar = sorted(set(re.findall(r"([^<>\"]{2,80}(?:Bank|BANK|Bankası|BANKASI)[^<>\"]{0,40})", s)))
        print(f"  banka benzeri ad: {len(adlar)}")
        for a in adlar[:120]:
            print("   ", a.strip()[:120])
        for t, h in linkler(b, r"bank")[:40]:
            print(f"  L {t!r} -> {h}")

# EVDS anahtarsız uç (yalnız erişim)

sys.exit(0)
