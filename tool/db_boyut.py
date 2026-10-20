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

Diğer ücretsiz plan sınırları (2026-10-20, müşteri raporu 20 Eki 13:15 #3:
"disk en yavaş dolan kaynak çıkabilir"): aynı rapora eklenir.
  * Storage (1 GB) ve aylık aktif kullanıcı (50.000): aynı SELECT'ten.
    Aktif kullanıcı = son 30 günde oturum açan hesap sayısı (`auth.users.
    last_sign_in_at`). Supabase'in MAU'su jeton yenilemeyi de sayar; bu
    sayı ALT SINIR, etiketinde öyle yazar. Yalnız sayı, kimlik okunmaz.
  * API istek sayıları: Management API `analytics/endpoints/usage.api-counts`
    (son 7 gün, belgeli uç). Ücretsiz planın istek sınırı yok, yalnız bilgi.
  * Dışarı trafik (egress, 5 GB/ay) ve Edge Function çağrısı (500.000/ay):
    Management API'de proje düzeyinde belgeli uç YOK (kullanım organizasyon
    faturasında). Uydurma sayı yazılmaz: rapor "panelden elle bak" der.
Her ölçülen sınırda %70 sarı, %90 kırmızı (iş kırmızı → e-posta). DB'nin
350/450 MB eşiği de tam bu orana denk.

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

# Ücretsiz plan sınırları (supabase.com/pricing, 2026-10). Oranlar %70/%90.
STORAGE_SINIR = 1024 * 1024 * 1024
MAU_SINIR = 50_000
UYARI_ORAN = 0.70
KIRMIZI_ORAN = 0.90
# Ölçülemeyenler: belgeli proje uç noktası yok → elle.
ELLE = [
    ("Dışarı trafik (egress)", "5 GB / ay"),
    ("Edge Function çağrısı", "500.000 / ay"),
]

SORGU = """
select json_build_object(
  'db', pg_database_size(current_database()),
  'storage', (select coalesce(sum((metadata->>'size')::bigint), 0)
              from storage.objects),
  'aktif_30g', (select count(*) from auth.users
                where last_sign_in_at >= now() - interval '30 days'),
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


def api_sayilari(token: str) -> dict | None:
    """Son 7 günün API istek sayıları; uç yanıt vermezse None (rapor "elle"
    der, iş düşmez — bilgi amaçlı)."""
    istek = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{REF}/analytics/endpoints/usage.api-counts?interval=7day",
        headers={"Authorization": f"Bearer {token}"},
    )
    try:
        with urllib.request.urlopen(istek, timeout=60) as y:
            veri = json.loads(y.read().decode())
    except (urllib.error.URLError, ValueError):
        return None
    satirlar = veri.get("result") if isinstance(veri, dict) else None
    if not isinstance(satirlar, list):
        return None
    toplam: dict[str, int] = {}
    for r in satirlar:
        for k, v in r.items():
            if k.startswith("total_") and isinstance(v, (int, float)):
                toplam[k] = toplam.get(k, 0) + int(v)
    return toplam


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
    kotalar, kota_kod = kota_satirlari(s)
    kod = max(kod, kota_kod)
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
    satirlar += ["", "## Diğer ücretsiz plan sınırları", ""] + kotalar
    return "\n".join(satirlar) + "\n", kod


def sayi(n: int) -> str:
    return f"{n:,}".replace(",", ".")


def isaret(oran: float) -> tuple[str, int]:
    if oran >= KIRMIZI_ORAN:
        return "🔴", 1
    if oran >= UYARI_ORAN:
        return "🟡", 0
    return "🟢", 0


def kota_satirlari(s: dict) -> tuple[list[str], int]:
    """Storage, aktif kullanıcı, API sayıları ve elle bakılacaklar (saf)."""
    satir = ["| Kaynak | Kullanım | Sınır | Oran |", "|---|---:|---:|---:|"]
    kod = 0
    st = s.get("storage") or 0
    i, k = isaret(st / STORAGE_SINIR)
    kod = max(kod, k)
    satir.append(f"| Storage | {mb(st)} | 1 GB | {i} %{st / STORAGE_SINIR * 100:.0f} |")
    if s.get("aktif_30g") is not None:
        a = int(s["aktif_30g"])
        i, k = isaret(a / MAU_SINIR)
        kod = max(kod, k)
        satir.append(
            f"| Aktif kullanıcı (30 gün oturum, alt sınır) | {sayi(a)} | 50.000 | {i} %{a / MAU_SINIR * 100:.1f} |")
    api = s.get("api")
    if api:
        for anahtar, deger in sorted(api.items()):
            ad = anahtar.removeprefix("total_").removesuffix("_requests")
            satir.append(f"| API istekleri, 7 gün ({ad}) | {sayi(deger)} | sınırsız | — |")
    else:
        satir.append("| API istekleri, 7 gün | panelden elle bak | sınırsız | — |")
    for ad, sinir in ELLE:
        satir.append(f"| {ad} | panelden elle bak | {sinir} | — |")
    satir += ["", "_Egress ve Edge Function çağrısı için Management API'de proje düzeyinde uç yok: "
              "Supabase paneli › Organization › Usage._"]
    return satir, kod


def main() -> int:
    token = os.environ.get("SUPABASE_ACCESS_TOKEN_EU") or os.environ.get("SUPABASE_ACCESS_TOKEN")
    if not token:
        print("SUPABASE_ACCESS_TOKEN_EU / SUPABASE_ACCESS_TOKEN yok.")
        return 2
    s = sorgula(token)
    s["api"] = api_sayilari(token)
    metin, kod = rapor(s)
    print(metin)
    ozet = os.environ.get("GITHUB_STEP_SUMMARY")
    if ozet:
        with open(ozet, "a", encoding="utf-8") as f:
            f.write(metin)
    if kod:
        print("::error::Bir ücretsiz plan sınırı %90'ı (DB için 450 MB) aştı; iş özetine bak.")
    return kod


if __name__ == "__main__":
    sys.exit(main())
