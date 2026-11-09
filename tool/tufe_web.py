"""Web enflasyon hesaplayıcısının TÜFE verisini yazar (docs/data/tufe.json).

Neden (yasin onayı 2026-10-20, Ar-Ge raporu 2026-10-20_1315 #2): sitede
"Param enflasyona karşı ne oldu?" sayfası. Her ay TÜFE açıklandığı gün
aramalar zirve yapıyor; sayfa o gün güncel ayı göstermeli.

Kaynak: uygulamanın kullandığı tablo, `public.inflation_index`. Onu
`fetch-inflation` doldurur (TCMB EVDS, TÜİK TÜFE genel endeksi; EVDS
anahtarı yalnız sunucuda). Yeni bir API ya da anahtar eklenmedi: iş
`db_boyut.py` ile aynı Management API yolunu ve aynı secret'ı kullanır,
canlı sunucuda (Frankfurt) TEK bir salt okunur SELECT koşar.

Kurallar:
- **Uydurma sayı yok.** Tablo neyse o; boşsa JSON'daki `aylar` boş kalır,
  sayfa "veri henüz yüklenmedi" der. Ara ay doldurulmaz.
- **Baz yılı karışmaz.** Yalnız EN SON satırın `source`'u ile aynı seri
  yazılır (2003=100 ile 2025=100 bölünürse "%-95 enflasyon" çıkar; bkz.
  supabase/functions/fetch-inflation/README.md "Baz yılı değişimi").
- **Açıklanmamış ay yok.** `fetch-inflation` içinde bulunulan ayı hiç
  yazmaz; burada ayrıca bugünün ayı ve sonrası süzülür.
- Repo herkese açık: token ya da yanıt gövdesi loga basılmaz; yalnız
  API'nin hata mesajı (token içermez) ve ay sayısı.

Kullanım:
    SUPABASE_ACCESS_TOKEN_EU=... python tool/tufe_web.py            # yazar
    SUPABASE_ACCESS_TOKEN_EU=... python tool/tufe_web.py --dry-run  # yazmaz
Çıkış satırı `DEGISIKLIK_VAR` ya da `DEGISIKLIK_YOK` (iş akışı buna bakar).
"""
from __future__ import annotations

import datetime as dt
import io
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

if __name__ == "__main__":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

KOK = Path(__file__).resolve().parent.parent
JSON_YOLU = KOK / "docs/data/tufe.json"
REF = os.environ.get("FRANKFURT_REF", "ynwymnpdiwudrlxfrmuo")

SORGU = """
select coalesce(json_agg(json_build_object(
  'period', to_char(period, 'YYYY-MM'),
  'endeks', tufe_index,
  'source', source) order by period), '[]'::json) as sonuc
from public.inflation_index;
"""


def sorgula(token: str) -> list[dict]:
    istek = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{REF}/database/query",
        data=json.dumps({"query": SORGU}).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(istek, timeout=120) as y:
            veri = json.loads(y.read().decode())
    except urllib.error.HTTPError as h:
        # Gövde API'nin yetki mesajıdır; token içermez.
        raise SystemExit(f"Management API HTTP {h.code}: {h.read().decode(errors='replace')[:300]}")
    satirlar = veri["rows"] if isinstance(veri, dict) else veri
    sonuc = satirlar[0]["sonuc"]
    return json.loads(sonuc) if isinstance(sonuc, str) else sonuc


def json_kur(satirlar: list[dict], bugun: dt.date) -> dict:
    """Tablo satırlarından sayfanın okuduğu JSON (saf; test edilebilir).

    `guncellendi` bilerek yok: her koşuda değişen bir zaman damgası, veri
    aynıyken de PR açtırırdı. Tazelik `aylar`'ın son elemanından okunur.
    """
    bu_ay = f"{bugun.year:04d}-{bugun.month:02d}"
    temiz = []
    for s in satirlar:
        ay, endeks, kaynak = s.get("period"), s.get("endeks"), s.get("source")
        try:
            endeks = float(endeks)
        except (TypeError, ValueError):
            continue
        if not ay or not kaynak or endeks <= 0 or ay >= bu_ay:
            continue
        temiz.append((ay, endeks, kaynak))
    temiz.sort()
    if not temiz:
        return {"kaynak": "TÜİK", "seri": None, "aylar": []}
    seri = temiz[-1][2]
    aylar = [{"ay": ay, "endeks": round(e, 4)} for ay, e, k in temiz if k == seri]
    return {"kaynak": "TÜİK", "seri": seri, "aylar": aylar}


def yazi(veri: dict) -> str:
    return json.dumps(veri, ensure_ascii=False, indent=1) + "\n"


def main() -> None:
    kuru = "--dry-run" in sys.argv
    token = os.environ.get("SUPABASE_ACCESS_TOKEN_EU") or os.environ.get("SUPABASE_ACCESS_TOKEN")
    if not token:
        raise SystemExit("SUPABASE_ACCESS_TOKEN_EU / SUPABASE_ACCESS_TOKEN yok")
    veri = json_kur(sorgula(token), dt.date.today())
    yeni = yazi(veri)
    eski = JSON_YOLU.read_text(encoding="utf-8") if JSON_YOLU.exists() else ""
    aylar = veri["aylar"]
    print(f"seri: {veri['seri']}, ay sayısı: {len(aylar)}, son ay: {aylar[-1]['ay'] if aylar else '-'}")
    if yeni.replace("\r\n", "\n") == eski.replace("\r\n", "\n"):
        print("DEGISIKLIK_YOK")
        return
    if not kuru:
        JSON_YOLU.write_text(yeni, encoding="utf-8")
    print("DEGISIKLIK_VAR")


if __name__ == "__main__":
    main()
