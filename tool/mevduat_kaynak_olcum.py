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
    TCMB + "Mevzuat/",
    TCMB + "Mevduat+Faiz+Oranlari/",
    TCMB,
    "https://tcmb.gov.tr/wps/wcm/connect/TR/TCMB+TR/File+Resources/YFA/Metaveri_Bankalar+Mevduat+Fiilen+Uygulanan+Faiz",
]
indirilecek = []
for u in sayfalar:
    b = al(u)
    if not b:
        continue
    for t, h in linkler(b, r"xls|xlsx|csv|mevduat|fiilen|azami|banka"):
        print(f"  {t!r} -> {h}")
        if re.search(r"xls|csv", h, re.I) or re.search(r"\.xls|excel", t, re.I):
            if h.startswith("/"):
                h = "https://www.tcmb.gov.tr" + h
            indirilecek.append((t, h))

for t, h in indirilecek[:8]:
    b = al(h)
    if b:
        tablo_dok(b, t)

# Banka listesi adayları
for u in [
    "https://www.bddk.org.tr/Kurulus/Liste/77",
    "https://www.tbb.org.tr/tr/bankacilik/banka-ve-sube-bilgileri/bankalarimiz/22",
    "https://www.tbb.org.tr/en/banks-and-banking-sector-information/banks/22",
    "https://www.tbb.org.tr/tr/bankacilik/banka-ve-sube-bilgileri/banka-bilgileri/22",
]:
    b = al(u)
    if b:
        s = b.decode("utf-8", "ignore")
        adlar = sorted(set(re.findall(r">\s*([A-ZÇĞİÖŞÜ][^<>]{3,80}?(?:A\.Ş\.|BANK[^<>]{0,40}))\s*<", s)))
        print(f"  banka benzeri ad: {len(adlar)}")
        for a in adlar[:80]:
            print("   ", a)

# EVDS anahtarsız uç (yalnız erişim)
al("https://evds3.tcmb.gov.tr/")
al("https://evds2.tcmb.gov.tr/")
sys.exit(0)
