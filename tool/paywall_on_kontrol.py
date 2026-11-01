"""Paywall açılışı ön kontrolü — salt okunur (paywall incelemesi, 2026-10-20).

Neden: açılış dört ayrı yerde dört elle adım ister (hediye SQL'i, RC
`premium_hediye_kesim`, RC `paywall_enabled`, sunucu `premium_ayar.kapi_acik`)
ve sırası önemli. 2026-11-01'den beri (0172) RC adımı yok: kesim hediye
SQL'iyle sunucuya yazılır, paywall kodda açık, kapı sunucuda. Biri atlanırsa
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

    satirlar.append("**Sıra: 1 hediye SQL'i (kesimi de yazar) → 2 sürümü yayınla → 3 kapi_acik**")
    satirlar.append("")
    if kesim is None:
        madde(None, "1) Hediye: `--kesim` verilmedi; hediyesiz eski kullanıcı sayılamadı. "
                    f"Mevcut hediye satırı: {hediye_adet}.")
    elif hediyesiz == 0 and hediye_adet > 0:
        madde(True, f"1) Hediye yazılmış: {hediye_adet} satır, kesimden eski hediyesiz kullanıcı yok.")
    elif hediyesiz == 0 and hediye_adet == 0:
        madde(None, "1) Kesimden eski kullanıcı yok ve hediye satırı yok (yeni proje?).")
    else:
        madde(False, f"1) Hediye EKSİK: kesimden eski {hediyesiz} kullanıcının hediye satırı yok. "
                     "Önce `erken_kullanici_hediyesi_ver(kesim, 90, 14)` çalıştır.")
    if hediye:
        ilk = min(h["ilk_bitis"] for h in hediye if h["ilk_bitis"])
        son = max(h["son_bitis"] for h in hediye if h["son_bitis"])
        satirlar.append(f"  - hediye bitişleri {ilk[:10]} … {son[:10]}"
                        + (" (tek güne yığılı: 0160 yayılımı kullanılmamış)" if ilk[:10] == son[:10] and hediye_adet > 1 else ""))
    # 0172: kesim ve acil durum sunucuda; Remote Config satırı kalmadı.
    sunucu_kesim = s.get("hediye_kesim")
    if kesim is not None and sunucu_kesim and str(sunucu_kesim)[:10] != kesim[:10]:
        madde(False, f"   `premium_ayar.hediye_kesim` = {sunucu_kesim} ama `--kesim` {kesim}: "
                     "uygulama sunucudaki kesimi okur; hediye SQL'i hangi kesimle koştuysa odur.")
    elif sunucu_kesim:
        madde(True, f"   `premium_ayar.hediye_kesim` = {sunucu_kesim} (uygulama bunu okur, 0172).")
    else:
        madde(None, "   `premium_ayar.hediye_kesim` boş: hediye SQL'i henüz koşmamış; uygulama herkesi 'eski' sayar, kimse kilit görmez.")
    madde(None, "2) Paywall kodda açık (iOS, 1.1.7 paywall build'i+); Remote Config'te bayrak yok. Mağazada o sürüm yayında mı (elle).")
    kapi = s.get("kapi_acik")
    if kapi is True and hediyesiz not in (0, None):
        madde(False, "3) `premium_ayar.kapi_acik` AÇIK ama hediye eksik: hediyesiz eski kullanıcıların ücretli içeriği kilitli.")
    else:
        madde(True if kapi is not None else False,
              f"3) `premium_ayar.kapi_acik` = {kapi} (açılış günü en son bu çevrilir; "
              "kapalıyken ücretli içerik herkese açık).")
    acil = s.get("acil_kapali")
    madde(not acil, "Acil kapatma `premium_ayar.acil_kapali` = " + ("AÇIK: kilitler herkeste askıda" if acil else "kapalı (normal)") + ".")

    eksik = [a for a in GEREKLI_SECRETLER if a not in secretler]
    madde(not eksik, "Function secret'ları: " + ("tamam" if not eksik else "EKSİK " + ", ".join(eksik)))
    cron = s.get("cron")
    if not cron:
        madde(False, "Hediye hatırlatma cron'u (`calendar-nudge-premium-hediye`) kurulu değil (0142).")
    else:
        madde(bool(cron.get("active")),
              f"Hediye hatırlatma cron'u {'aktif' if cron.get('active') else 'KAPALI'} ({cron.get('schedule')}).")

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
