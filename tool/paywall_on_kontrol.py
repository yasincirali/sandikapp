"""Paywall açılışı ön kontrolü — salt okunur (paywall incelemesi, 2026-10-20).

Neden: açılış dört ayrı yerde dört elle adım ister (hediye SQL'i, RC
`premium_hediye_kesim`, RC `paywall_enabled`, sunucu `premium_ayar.kapi_acik`)
ve sırası önemli. 2026-11-01'den beri (0172) RC adımı yok: paywall kodda
açık, kapı ve acil kapatma sunucuda; aynı gün HEDİYE de kalktı (yasin: eski
kullanıcı da yeni gibi görür) — hediye satırları artık bilgi, engel değil. Biri atlanırsa
ya herkes kilit görür ya da ücretli içerik açıkta kalır; bunu bir bakışta
gören bir yer yoktu. Betik SUNUCU tarafını okur ve kontrol listesi basar.

Ne yapar: Frankfurt'ta TEK SELECT (Management API, `db_boyut.py` deseni):
`premium_ayar` (kapı, hediye kesimi, acil kapatma; 0172), `premium_haklari` kaynak dağılımı (sandbox ayrı),
hediyesiz eski kullanıcı sayısı (kesim verilirse), hediye bitiş penceresi,
`calendar-nudge-premium-hediye` cron'u, ve function secret ADLARI
(`/v1/projects/{ref}/secrets`, değer okunmaz). Yazma yok.

Kullanım:
  python tool/paywall_on_kontrol.py [--kesim 2026-10-28T00:00:00+03]
  (SUPABASE_ACCESS_TOKEN_EU ya da SUPABASE_ACCESS_TOKEN ortamda)
"""
import argparse
import io
import json
import os
import sys
import urllib.error
import urllib.request

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

REF = os.environ.get("FRANKFURT_REF", "ynwymnpdiwudrlxfrmuo")

GEREKLI_SECRETLER = (
    "REVENUECAT_WEBHOOK_SECRET",
    "REVENUECAT_API_KEY",
    "CALENDAR_NUDGE_CRON_SECRET",
)


def sorgu(kesim: str | None) -> str:
    # Kesim parametrelenir: tarih literal'i tırnak içinde; tek tırnak
    # kaçırılır (yalnız ISO tarih bekleniyor, yine de).
    kesim_sql = "null" if not kesim else "'" + kesim.replace("'", "''") + "'::timestamptz"
    return f"""
select json_build_object(
  'kapi_acik', (select kapi_acik from public.premium_ayar limit 1),
  'hediye_kesim', (select hediye_kesim from public.premium_ayar limit 1),
  'acil_kapali', (select acil_kapali from public.premium_ayar limit 1),
  'haklar', (select coalesce(json_agg(t), '[]'::json) from (
      select kaynak, sandbox, count(*) as adet,
             count(*) filter (where bitis is null or bitis > now()) as gecerli,
             min(bitis) as ilk_bitis, max(bitis) as son_bitis
        from public.premium_haklari
       group by kaynak, sandbox order by kaynak, sandbox) t),
  'hediyesiz_eski', (
      select count(*) from auth.users u
       where {kesim_sql} is not null
         and u.created_at < {kesim_sql}
         and u.deleted_at is null
         and not exists (select 1 from public.premium_haklari h
                          where h.user_id = u.id and h.kaynak = 'erken_kullanici')),
  'cron', (select json_build_object('active', active, 'schedule', schedule)
             from cron.job where jobname = 'calendar-nudge-premium-hediye')
) as sonuc;
"""


def _istek(token: str, url: str, gov: dict | None = None):
    istek = urllib.request.Request(
        url,
        data=None if gov is None else json.dumps(gov).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="GET" if gov is None else "POST",
    )
    try:
        with urllib.request.urlopen(istek, timeout=120) as y:
            return json.loads(y.read().decode())
    except urllib.error.HTTPError as h:
        # Gövde API'nin yetki mesajıdır; token içermez.
        raise SystemExit(f"Management API HTTP {h.code}: {h.read().decode(errors='replace')[:300]}")


def sorgula(token: str, kesim: str | None) -> dict:
    veri = _istek(token, f"https://api.supabase.com/v1/projects/{REF}/database/query",
                  {"query": sorgu(kesim)})
    satirlar = veri["rows"] if isinstance(veri, dict) else veri
    sonuc = satirlar[0]["sonuc"]
    return json.loads(sonuc) if isinstance(sonuc, str) else sonuc


def secret_adlari(token: str) -> set[str]:
    veri = _istek(token, f"https://api.supabase.com/v1/projects/{REF}/secrets")
    return {s.get("name", "") for s in veri}


def rapor(s: dict, secretler: set[str], kesim: str | None) -> tuple[str, int]:
    """Kontrol listesi ve çıkış kodu (saf; test edilebilir). 1 = engel var."""
    engel = 0
    satirlar = ["## Paywall açılış ön kontrolü (Frankfurt, salt okunur)", ""]

    def madde(ok: bool | None, metin: str):
        nonlocal engel
        isaret = "✅" if ok else ("⬜" if ok is None else "❌")
        if ok is False:
            engel = 1
        satirlar.append(f"- {isaret} {metin}")

    haklar = s.get("haklar") or []
    hediye = [h for h in haklar if h["kaynak"] == "erken_kullanici"]
    hediye_adet = sum(h["adet"] for h in hediye)
    hediyesiz = s.get("hediyesiz_eski")

    satirlar.append("**Sıra: 1 sürümü yayınla → 2 kapi_acik** (hediye yok, yasin 2026-11-01)")
    satirlar.append("")
    # Hediye kaldırıldı (yasin 2026-11-01: eski kullanıcı da yeni gibi görür).
    # Satırlar bilgi amaçlı kalır: eski kampanya satırı ya da yanlışlıkla
    # koşulmuş hediye SQL'i görünsün; engel değildir.
    if hediye_adet > 0:
        madde(None, f"1) Hediye satırı var: {hediye_adet} (erken_kullanici). Hediye planı KALKTI; "
                    "bu satırlar kalıcı Premium verir, bilinçli değilse sil.")
        ilk = min(h["ilk_bitis"] for h in hediye if h["ilk_bitis"])
        son = max(h["son_bitis"] for h in hediye if h["son_bitis"])
        satirlar.append(f"  - hediye bitişleri {ilk[:10]} … {son[:10]}")
    else:
        madde(True, "1) Hediye yok (plan: eski ve yeni kullanıcı aynı kilidi görür).")
    if kesim is not None and hediyesiz not in (None, 0):
        satirlar.append(f"  - bilgi: `--kesim` {kesim} öncesi hak satırsız {hediyesiz} kullanıcı (beklenen; hediye yok).")
    # 0172: acil durum sunucuda; `hediye_kesim` kolonu durur, uygulama OKUMAZ.
    sunucu_kesim = s.get("hediye_kesim")
    if sunucu_kesim:
        madde(None, f"   `premium_ayar.hediye_kesim` = {sunucu_kesim} dolu: hediye SQL'i koşmuş; uygulama bu değeri kullanmaz.")
    madde(None, "2) Paywall kodda açık (iOS, 1.1.7 paywall build'i+); Remote Config'te bayrak yok. Mağazada o sürüm yayında mı (elle).")
    kapi = s.get("kapi_acik")
    madde(True if kapi is not None else False,
          f"3) `premium_ayar.kapi_acik` = {kapi} (açılış günü en son bu çevrilir; "
          "kapalıyken ücretli içerik herkese açık).")
    acil = s.get("acil_kapali")
    madde(not acil, "Acil kapatma `premium_ayar.acil_kapali` = " + ("AÇIK: kilitler herkeste askıda" if acil else "kapalı (normal)") + ".")

    eksik = [a for a in GEREKLI_SECRETLER if a not in secretler]
    madde(not eksik, "Function secret'ları: " + ("tamam" if not eksik else "EKSİK " + ", ".join(eksik)))
    cron = s.get("cron")
    # Hediye yokken hatırlatma cron'u sessiz çalışır (satır bulamaz); bilgi.
    madde(None, "Hediye hatırlatma cron'u (`calendar-nudge-premium-hediye`): "
                + ("yok" if not cron else f"{'aktif' if cron.get('active') else 'kapalı'} ({cron.get('schedule')})")
                + " — hediye yokken etkisiz.")

    satirlar += ["", "| Kaynak | Sandbox | Satır | Geçerli |", "|---|---|---:|---:|"]
    for h in haklar:
        satirlar.append(f"| {h['kaynak']} | {'evet' if h.get('sandbox') else 'hayır'} | {h['adet']} | {h['gecerli']} |")
    return "\n".join(satirlar) + "\n", engel


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--kesim", help="Hediye kesimi (ISO), örn. 2026-10-28T00:00:00+03")
    a = ap.parse_args()
    token = os.environ.get("SUPABASE_ACCESS_TOKEN_EU") or os.environ.get("SUPABASE_ACCESS_TOKEN")
    if not token:
        print("SUPABASE_ACCESS_TOKEN_EU / SUPABASE_ACCESS_TOKEN yok.")
        return 2
    metin, kod = rapor(sorgula(token, a.kesim), secret_adlari(token), a.kesim)
    print(metin)
    return kod


if __name__ == "__main__":
    sys.exit(main())
