-- 0142 — Gösterge parametreleri + Premium hediyesi bitiş hatırlatması
--        (Premium seti netleştirme, 2026-10-10)
--
-- ## 1) `signal_preferences.parametreler`
-- yasin kararı (2026-10-10 20:38): "var olan göstergeler de parametrik
-- kullanılabilmeli premiumda". Kullanıcı Sinyal Ayarları'nda gösterge
-- periyotlarını değiştirir (RSI 14 → 9, MACD 12/26/9 → 8/21/5 …); sunucu
-- bildirimleri AYNI periyotla hesaplamalı, yoksa ekrandaki sinyal ile push
-- birbirini tutmaz.
--   · Biçim: `{"rsi": {"periyot": 9}, "macd": {"hizli": 8, "yavas": 21, "sinyal": 5}}`.
--     Sınırları istemci (`GostergeParametreleri`) ve sunucu
--     (`_shared/technical_analysis.ts` → `parametreDogrula`) AYNI tabloyla
--     doğrular; aralık dışı değer sessizce varsayılana düşer.
--   · NULL = varsayılan periyotlar (bugünkü davranış). Eski istemci kolonu
--     okumaz ve yazmaz; upsert'i kolonu içermediği için mevcut değeri de
--     ezmez. Yani bu migration hiçbir kullanıcının sinyalini değiştirmez.
--   · Premium kapısı istemcide (parametre düğmesi Premium değilse paywall
--     açar). Sunucu kolonu Premium'a bakmadan uygular: yazabilen tek yol
--     Premium (ya da admin önizlemesi) ve hak bitince istemci varsayılana
--     dönmeyi önerir. Kötü niyetli bir istemcinin kazancı kendi push'unun
--     periyodu — ücretli içerik sızmaz (ileri göstergeler ayrıca
--     `premium_mi_kullanici` ile kapılı, analyze-signals).
--   · Boy sınırı: sekiz gösterge × en çok üç tamsayı; 2 KB bol bol yeter.
--     Sınırsız jsonb, RLS'li ama istemcinin yazabildiği bir kolonda disk
--     kotasını (Free plan 500 MB) tüketme yolu olurdu.
--
-- ## 2) Premium hediyesinin bitiş hatırlatması
-- Paywall açıldığı gün mevcut kullanıcılara 90 günlük `erken_kullanici`
-- hakkı verilir (0116). Hediye sessizce biterse kullanıcı bir sabah
-- kilitlerle karşılaşır; bu, "aldatıldım" hissinin ta kendisi. Bitişten
-- 10 gün önce (80. gün) TEK push: ne zaman biteceği ve ne kaybedileceği.
--   · Hedef: `erken_kullanici` satırı 9–11 gün içinde biten, geçerli bir
--     `revenuecat` satırı OLMAYAN (zaten abone olana "bitiyor" demek yanlış)
--     ve defterde kaydı olmayan kullanıcı. Pencere iki gün: cron bir gün
--     kaçarsa ertesi gün yakalar; defter ikinci push'u durdurur.
--   · Bugün hiçbir kullanıcının `erken_kullanici` satırı yok (hediye
--     paywall açılış günü verilir) → bu migration canlıda HİÇ push
--     göndermez; ilk push hediyenin 80. gününde gider.
--   · Defter `premium_hediye_hatirlatma_log(user_id, bitis)`: hediye
--     yeniden verilirse (yeni `bitis`) yeni hatırlatma hakkı doğar.
--     Saklama: edge function 120 günden eskisini siler. Hesap silinince
--     cascade. Yasal metin değişmez: "abonelik ve bildirim kayıtları"
--     zaten kapsıyor; yeni kişisel veri ya da amaç yok.
--   · Aynı edge function (`calendar-nudge`), aynı secret; an gövdeden
--     (`premium_gift_ending`). Diğer tetikleyiciler DEĞİŞMEZ.

-- ── 1) Parametre kolonu ─────────────────────────────────────────────────────
alter table public.signal_preferences
  add column if not exists parametreler jsonb;

alter table public.signal_preferences
  drop constraint if exists signal_preferences_parametreler_bicim;
alter table public.signal_preferences
  add constraint signal_preferences_parametreler_bicim check (
    parametreler is null
    or (jsonb_typeof(parametreler) = 'object'
        and pg_column_size(parametreler) <= 2048)
  );

comment on column public.signal_preferences.parametreler is
  'Premium gosterge periyotlari: {"rsi":{"periyot":9},...}. NULL = varsayilan. '
  'Sinirlar istemci GostergeParametreleri + sunucu parametreDogrula ile ayni (0142).';

-- ── 2) Hatırlatma defteri ───────────────────────────────────────────────────
create table if not exists public.premium_hediye_hatirlatma_log (
  user_id uuid not null references auth.users(id) on delete cascade,
  -- Hatırlatılan hediyenin bitişi; yeni hediye = yeni anahtar.
  bitis timestamptz not null,
  sent_at timestamptz not null default now(),
  primary key (user_id, bitis)
);
alter table public.premium_hediye_hatirlatma_log enable row level security;
-- Yalnız service role yazar/okur; istemcinin işi yok.
revoke all on table public.premium_hediye_hatirlatma_log from anon, authenticated;

-- ── 3) Tetikleyici (0119 deseni) ────────────────────────────────────────────
create or replace function public.trigger_calendar_nudge_premium_hediye()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('calendar-nudge'),
    headers := public.cron_headers('calendar_nudge_cron_secret'),
    body := jsonb_build_object('occasion', 'premium_gift_ending'),
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.trigger_calendar_nudge_premium_hediye() from public, anon, authenticated;

-- ── 4) Zamanlama: her gün 12:15 TR = 09:15 UTC ──────────────────────────────
-- Sabah brifingi (09:45) ve maaş günü hatırlatmasından (10:30) uzak; öğle
-- arası, bir karar verilebilecek saat.
select cron.unschedule(jobid) from cron.job where jobname = 'calendar-nudge-premium-hediye';
select cron.schedule('calendar-nudge-premium-hediye', '15 9 * * *',
  $$select public.trigger_calendar_nudge_premium_hediye()$$);

-- İki sunucu birebir; tek bilinçli fark cron `active` (0087/0119 kuralı).
do $$
begin
  if exists (select 1 from cron.job where jobname <> 'calendar-nudge-premium-hediye')
     and not exists (select 1 from cron.job
                      where jobname <> 'calendar-nudge-premium-hediye' and active) then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job where jobname = 'calendar-nudge-premium-hediye';
    raise notice '0142: projede tum cron isleri kapali — calendar-nudge-premium-hediye da kapali kuruldu.';
  end if;
end $$;

-- ── 5) Doğrulama ────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'signal_preferences'
                    and column_name = 'parametreler') then
    raise exception '0142: signal_preferences.parametreler yok';
  end if;
  if not exists (select 1 from cron.job
                  where jobname = 'calendar-nudge-premium-hediye'
                    and schedule = '15 9 * * *') then
    raise exception '0142: calendar-nudge-premium-hediye cron isi kurulmadi';
  end if;
  if has_function_privilege('authenticated', 'public.trigger_calendar_nudge_premium_hediye()', 'EXECUTE')
     or has_function_privilege('anon', 'public.trigger_calendar_nudge_premium_hediye()', 'EXECUTE') then
    raise exception '0142: trigger_calendar_nudge_premium_hediye istemciden cagrilabilir olmamali';
  end if;
  if has_table_privilege('authenticated', 'public.premium_hediye_hatirlatma_log', 'SELECT')
     or has_table_privilege('anon', 'public.premium_hediye_hatirlatma_log', 'SELECT') then
    raise exception '0142: premium_hediye_hatirlatma_log istemciye acik olmamali';
  end if;
  raise notice '0142 tamam: gosterge parametreleri + hediye bitis hatirlatmasi kuruldu.';
end $$;
