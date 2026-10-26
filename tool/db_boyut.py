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
  * Dışarı trafik (egress, 5 GB/ay): Management API'de proje düzeyinde
    belgeli uç YOK (kullanım organizasyon faturasında). Uydurma sayı
    yazılmaz: rapor "panelden elle bak" der.
  * Edge Function çağrısı (500.000/ay; müşteri raporu 2026-10-26 21:15 #3,
    yasin "yap"): widget her kurulumda sunucu çağrısı demek, kota artık
    ölçülür. Kaynak `analytics/endpoints/logs.all` (belgeli uç) üzerinden
    `function_edge_logs`: son 24 saatteki çağrı, fonksiyon başına. Ücretsiz
    planda log 1 gün saklandığı için ay ölçülemez; aylık sayı "24 saat × 30"
    diye TAHMİN etiketiyle yazılır, %70/%90 eşiği o tahmine uygulanır.
    Uç yanıt vermezse eski satır: "panelden elle bak". Kimlik/IP okunmaz,
    yalnız yol ve sayı.
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
]
FN_SINIR = 500_000

# Son 24 saatte fonksiyon başına çağrı (yol = `/<fonksiyon>`). Satır içeriği
# (gövde, başlık, IP) seçilmez.
FN_SORGU = (
    "select r.pathname as yol, count(*) as n from function_edge_logs "
    "cross join unnest(metadata) as m cross join unnest(m.request) as r "
    "group by yol order by n desc"
)
FN_TOPLAM_SORGU = "select count(*) as n from function_edge_logs"

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


def fonksiyon_cagrilari(token: str) -> dict | None:
    """Son 24 saatin Edge Function çağrıları: `{"toplam": n, "yollar": {ad: n}}`.
    Uç yanıt vermezse None (rapor "elle" der, iş düşmez)."""
    import datetime
    import urllib.parse
    bitis = datetime.datetime.now(datetime.timezone.utc)
    baslangic = bitis - datetime.timedelta(hours=24)
    zaman = lambda d: d.strftime("%Y-%m-%dT%H:%M:%S.000Z")  # noqa: E731
    # İlk deneme fonksiyon başına; uç yolu çözemezse (şema farkı) yalnız
    # toplam. İkisi de düşerse nedeni (HTTP kodu + API'nin kısa mesajı;
    # token içermez) günlüğe yazılır ki "elle bak" satırı sessiz kalmasın
    # (2026-10-26 ilk koşu: neden görünmeden None döndü).
    for sql in (FN_SORGU, FN_TOPLAM_SORGU):
        sorgu = urllib.parse.urlencode({
            "sql": sql,
            "iso_timestamp_start": zaman(baslangic),
            "iso_timestamp_end": zaman(bitis),
        })
        istek = urllib.request.Request(
            f"https://api.supabase.com/v1/projects/{REF}/analytics/endpoints/logs.all?{sorgu}",
            headers={"Authorization": f"Bearer {token}"},
        )
        try:
            with urllib.request.urlopen(istek, timeout=60) as y:
                veri = json.loads(y.read().decode())
        except urllib.error.HTTPError as h:
            print(f"logs.all HTTP {h.code}: {h.read().decode(errors='replace')[:200]}")
            continue
        except (urllib.error.URLError, ValueError) as e:
            print(f"logs.all okunamadı: {type(e).__name__}")
            continue
        fn = fn_coz(veri)
        if fn is not None:
            return fn
        hata = veri.get("error") if isinstance(veri, dict) else None
        print(f"logs.all yanıtı çözülemedi: {str(hata)[:200]}")
    return None


def fn_coz(veri: object) -> dict | None:
    """`logs.all` yanıtı → toplam + fonksiyon başına sayı (saf; test edilir)."""
    if not isinstance(veri, dict) or veri.get("error"):
        return None
    satirlar = veri.get("result")
    if not isinstance(satirlar, list):
        return None
    yollar: dict[str, int] = {}
    for r in satirlar:
        if not isinstance(r, dict) or not isinstance(r.get("n"), (int, float)):
            continue
        ad = str(r.get("yol") or "?").removeprefix("/functions/v1").strip("/") or "?"
        yollar[ad] = yollar.get(ad, 0) + int(r["n"])
    return {"toplam": sum(yollar.values()), "yollar": yollar}


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
    fn = s.get("fn")
    if fn:
        aylik = fn["toplam"] * 30
        i, k = isaret(aylik / FN_SINIR)
        kod = max(kod, k)
        satir.append(
            f"| Edge Function çağrısı (son 24 saat × 30, tahmin) | {sayi(aylik)} | 500.000 / ay "
            f"| {i} %{aylik / FN_SINIR * 100:.0f} |")
        widget = fn["yollar"].get("widget-fiyat", 0)
        satir.append(f"| ↳ son 24 saat ölçüm (widget-fiyat: {sayi(widget)}) | {sayi(fn['toplam'])} | — | — |")
    else:
        satir.append("| Edge Function çağrısı | panelden elle bak | 500.000 / ay | — |")
    for ad, sinir in ELLE:
        satir.append(f"| {ad} | panelden elle bak | {sinir} | — |")
    satir += ["", "_Egress için Management API'de proje düzeyinde uç yok: "
              "Supabase paneli › Organization › Usage. Edge Function satırı log'dan "
              "son 24 saatin ölçümü; aylık sayı ondan tahmin._"]
    if fn and fn["yollar"]:
        satir += ["", "| Fonksiyon (son 24 saat) | Çağrı |", "|---|---:|"]
        for ad, n in sorted(fn["yollar"].items(), key=lambda x: -x[1])[:12]:
            satir.append(f"| `{ad}` | {sayi(n)} |")
    return satir, kod


def main() -> int:
    token = os.environ.get("SUPABASE_ACCESS_TOKEN_EU") or os.environ.get("SUPABASE_ACCESS_TOKEN")
    if not token:
        print("SUPABASE_ACCESS_TOKEN_EU / SUPABASE_ACCESS_TOKEN yok.")
        return 2
    s = sorgula(token)
    s["api"] = api_sayilari(token)
    s["fn"] = fonksiyon_cagrilari(token)
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
