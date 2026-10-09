"""Mevduat banka listesi / faiz kaynaklarının erişim ve biçim ölçümü (2026-10-09).

Neden: bulut kabı TCMB/BDDK/TBB hostlarını reddediyor. Salt okunur,
anahtarsız; secret kullanmaz (public repo, log herkese açık).
"""
import re
import urllib.request

UA = {"User-Agent": "Mozilla/5.0 (sandik kaynak olcum)"}


def al(url):
    try:
        req = urllib.request.Request(url, headers=UA)
        with urllib.request.urlopen(req, timeout=30) as r:
            b = r.read()
            print(f"\n=== {r.status} {len(b)}B {r.headers.get('Content-Type')} {url}")
            return b
    except Exception as e:  # noqa: BLE001
        print(f"\n=== HATA {url}: {e}")
        return None


def pdf_metin(b, n=6000):
    import io
    from pypdf import PdfReader
    t = "\n".join(p.extract_text() or "" for p in PdfReader(io.BytesIO(b)).pages)
    print(t[:n])


T = "https://www.tcmb.gov.tr"
for u in [
    T + "/wps/wcm/connect/8cb713a6-4b02-4835-a372-d3232a08b2e5/RIPMetaveri-3_Bankalar_Ayl%C4%B1k_Fiilen_Uygulanan_Mevduat_Faiz.pdf?MOD=AJPERES",
    T + "/wps/wcm/connect/933493cb-5251-43f3-af70-920eee213041/RIPMetaveri-1_Haftal%C4%B1k_Mevduat_Ag%C4%B1rl%C4%B1kl%C4%B1_Ortalama_Faiz.pdf?MOD=AJPERES",
]:
    b = al(u)
    if b:
        pdf_metin(b)

b = al("https://www.tbb.org.tr/banka-ve-sektor-bilgileri/banka-bilgileri/bankalarimiz")
if b:
    s = b.decode("utf-8", "ignore")
    s = re.sub(r"<script.*?</script>|<style.*?</style>", " ", s, flags=re.S)
    t = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " | ", s))
    t = re.sub(r"(\s*\|\s*)+", " | ", t)
    i = t.find("Mevduat Bankaları")
    print("TBB:", t[max(0, i - 300): i + 6000])
