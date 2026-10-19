"""Canlı veritabanı ne kadar dolu? Haftalık salt okunur ölçüm (2026-10-19).

Neden: Supabase ücretsiz planında veritabanı 500 MB'ı aşarsa proje salt
okunura düşer, uygulama kayıt yapamaz (canlı kullanıcı etkilenir, ana
kural). yasin (2026-10-19): "Veritabanı boyutu: yalnız ölçüm yapılsın,
sıkıştırma için şimdilik migration yazmaya gerek yok." 5 Ekim'de Tokyo
342 MB'ı görmüştü (asıl yük `db_logs` hata ayıklama satırlarıydı, 0114 ile
budandı); o zamandan beri ölçen bir şey yoktu, panele bakmak gerekiyordu.

Ne yapar: canlı sunucuda (Frankfurt) TEK bir SELECT koşar —
veritabanı boyutu, en büyük 15 tablo (boyut + tahmini satır), Storage
toplamı. Yazma yok, veri satırı okunmaz, yalnız katalog sayıları. Tablo
adları zaten migration'larda açık (public repo log'u güvenli).

Eşikler: 350 MB uyarı (sarı not), 450 MB kırmızı — kırmızı iş GitHub'dan
e-posta getirir. 450 MB, 5 Ekim notundaki "Pro'ya geçiş eşiği".
Tokyo yedek sunucudur (cron'lar kapalı, büyümez); ölçülmez.

CI'da:  SUPABASE_ACCESS_TOKEN_EU (yoksa SUPABASE_ACCESS_TOKEN) ile
        Management API. Yerelde: aynı değişkenlerle `python tool/db_boyut.py`.
"""
import io
import json
import os
import sys
import urllib.error
import urllib.request

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

REF = os.environ.get("FRANKFURT_REF", "ynwymnpdiwudrlxfrmuo")
SINIR_MB = 500
UYARI_MB = 350
KIRMIZI_MB = 450

SORGU = """
select json_build_object(
  'db', pg_database_size(current_database()),
  'storage', (select coalesce(sum((metadata->>'size')::bigint), 0)
              from storage.objects),
  'tablolar', (
    select coalesce(json_agg(t), '[]'::json) from (
      select n.nspname || '.' || c.relname as ad,
             pg_total_relation_size(c.oid) as boyut,
             greatest(c.reltuples, 0)::bigint as satir
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where c.relkind in ('r', 'm', 'p')
        and n.nspname not in ('pg_catalog', 'information_schema', 'pg_toast')
      order by pg_total_relation_size(c.oid) desc
      limit 15
    ) t)
) as sonuc;
"""


def sorgula(token: str) -> dict:
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


def mb(b: float) -> str:
    return f"{b / 1024 / 1024:,.1f} MB".replace(",", " ")


def rapor(s: dict) -> tuple[str, int]:
    """Markdown rapor ve çıkış kodu (saf; test edilebilir)."""
    db = s["db"]
    db_mb = db / 1024 / 1024
    if db_mb >= KIRMIZI_MB:
        durum, kod = f"🔴 {KIRMIZI_MB} MB eşiği aşıldı: Pro plana geçiş ya da budama kararı gerekli.", 1
    elif db_mb >= UYARI_MB:
        durum, kod = f"🟡 {UYARI_MB} MB uyarı eşiği aşıldı: büyüyen tabloya bak.", 0
    else:
        durum, kod = "🟢 Rahat.", 0
    satirlar = [
        "## Veritabanı boyutu (Frankfurt, canlı)",
        "",
        f"**{mb(db)} / {SINIR_MB} MB** (%{db_mb / SINIR_MB * 100:.0f}) · Storage {mb(s.get('storage') or 0)} / 1 GB",
        "",
        durum,
        "",
        "| Tablo | Boyut | Tahmini satır |",
        "|---|---:|---:|",
    ]
    for t in s.get("tablolar") or []:
        satirlar.append(f"| `{t['ad']}` | {mb(t['boyut'])} | {t['satir']:,} |".replace(",", "."))
    return "\n".join(satirlar) + "\n", kod


def main() -> int:
    token = os.environ.get("SUPABASE_ACCESS_TOKEN_EU") or os.environ.get("SUPABASE_ACCESS_TOKEN")
    if not token:
        print("SUPABASE_ACCESS_TOKEN_EU / SUPABASE_ACCESS_TOKEN yok.")
        return 2
    metin, kod = rapor(sorgula(token))
    print(metin)
    ozet = os.environ.get("GITHUB_STEP_SUMMARY")
    if ozet:
        with open(ozet, "a", encoding="utf-8") as f:
            f.write(metin)
    if kod:
        print(f"::error::Veritabanı {KIRMIZI_MB} MB eşiğini aştı (sınır {SINIR_MB} MB).")
    return kod


if __name__ == "__main__":
    sys.exit(main())
