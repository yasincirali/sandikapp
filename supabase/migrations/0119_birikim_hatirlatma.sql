-- 0119 — Maaş günü birikim hatırlatması (2026-10-05, birikim serisi Faz 2)
--
-- ## Neden
-- yasin kararı (2026-10-05): aylık birikim serisine (PR #102, bayrak
-- `birikim_serisi`) maaş günü hatırlatması eklensin. Kullanıcı Ayarlar'da
-- ayın bir gününü seçer; o gün TR 10:30'da, o ay HİÇ alım satırı yoksa tek
-- push gider. Alım varsa gitmez — hatırlatmanın tek işi unutulan bir
-- ekleme varsa onu yakalamak (RETENTION_STRATEJISI §5.I "maaş günü").
--
-- ## Opt-in, varsayılan KAPALI
-- `birikim_hatirlatma_gunu` null doğar = kapalı. Eski istemci bu kolonu
-- okumaz ve yazmaz; yeni istemcide anahtar `birikim_serisi` bayrağının
-- arkasında. Yani bu migration canlıda HİÇBİR kullanıcıya push göndermez;
-- ilk push, bayrak açık bir cihazda biri günü seçtiğinde gider.
--
-- ## Gün 1–31
-- Maaş 30'unda yatan kullanıcı 30'u seçebilmeli. Ayın son gününden büyük
-- seçim (Şubat'ta 30) o ayın SON gününe düşer — fonksiyon hesaplar.
--
-- ## Defter
-- `birikim_hatirlatma_log(user_id, period)`: ay başına kullanıcı başına tek
-- push. Cron günde bir koşar; elle ikinci tetik ikinci push göndermez.
-- `calendar_nudge_log` kullanıcı bazlı değil (herkese tek an), bu yüzden
-- ayrı defter.
-- Saklama: fonksiyon her koşuda bir önceki aydan eskisini siler (en çok
-- ~2 ay) — aydınlatma metnindeki "bildirim kayıtları 90 gün" sınırı içinde.
-- Hesap silinince `on delete cascade` ile gider. Yasal metin değişmez:
-- "takvim hatırlatmaları" ve "bildirim tercihleri" zaten kapsıyor.

-- ── 1) Tercih ──────────────────────────────────────────────────────────────
alter table public.profiles
  add column if not exists birikim_hatirlatma_gunu smallint;

alter table public.profiles
  drop constraint if exists profiles_birikim_hatirlatma_gunu_aralik;
alter table public.profiles
  add constraint profiles_birikim_hatirlatma_gunu_aralik check (
    birikim_hatirlatma_gunu is null
    or birikim_hatirlatma_gunu between 1 and 31
  );

comment on column public.profiles.birikim_hatirlatma_gunu is
  'Maas gunu birikim hatirlatmasi: ayin gunu (1-31), null = kapali. '
  'Ayin son gununden buyukse o ayin son gunu gider.';

-- ── 2) Defter ──────────────────────────────────────────────────────────────
create table if not exists public.birikim_hatirlatma_log (
  user_id uuid not null references auth.users(id) on delete cascade,
  -- Hatırlatmanın ait olduğu ay (`YYYY-MM-01`, TR).
  period date not null,
  sent_at timestamptz not null default now(),
  primary key (user_id, period)
);
alter table public.birikim_hatirlatma_log enable row level security;
-- Yalnız service role yazar/okur; istemcinin işi yok.
revoke all on table public.birikim_hatirlatma_log from anon, authenticated;

-- ── 3) Tetikleyici (0087 deseni) ───────────────────────────────────────────
-- Aynı fonksiyon ve aynı secret (`calendar_nudge_cron_secret`); an gövdeden
-- seçilir. `trigger_calendar_nudge()` ve yıl sonu tetikleyicisi DEĞİŞMEZ.
create or replace function public.trigger_calendar_nudge_birikim()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('calendar-nudge'),
    headers := public.cron_headers('calendar_nudge_cron_secret'),
    body := jsonb_build_object('occasion', 'saving_reminder'),
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.trigger_calendar_nudge_birikim() from public, anon, authenticated;

-- ── 4) Zamanlama: her gün 10:30 TR = 07:30 UTC ─────────────────────────────
-- Sabah brifingi 09:45'te; 45 dk sonra ikinci push aynı kişiye ancak o gün
-- maaş günü seçtiyse ve o ay hiç ekleme yapmadıysa gider — ayda en çok bir.
select cron.unschedule(jobid) from cron.job where jobname = 'calendar-nudge-birikim';
select cron.schedule('calendar-nudge-birikim', '30 7 * * *',
  $$select public.trigger_calendar_nudge_birikim()$$);

-- İki sunucu birebir; tek bilinçli fark cron `active` (0087 ile aynı kural):
-- projedeki bütün işler kapalıysa (Frankfurt) yeni iş de kapalı kurulur,
-- yoksa iki sunucu aynı kişiye iki push atardı.
do $$
begin
  if exists (select 1 from cron.job where jobname <> 'calendar-nudge-birikim')
     and not exists (select 1 from cron.job
                      where jobname <> 'calendar-nudge-birikim' and active) then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job where jobname = 'calendar-nudge-birikim';
    raise notice '0119: projede tum cron isleri kapali — calendar-nudge-birikim da kapali kuruldu.';
  end if;
end $$;

-- ── 5) Doğrulama ───────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'profiles'
                    and column_name = 'birikim_hatirlatma_gunu') then
    raise exception '0119: profiles.birikim_hatirlatma_gunu yok';
  end if;
  if not exists (select 1 from cron.job
                  where jobname = 'calendar-nudge-birikim'
                    and schedule = '30 7 * * *') then
    raise exception '0119: calendar-nudge-birikim cron isi kurulmadi';
  end if;
  if has_function_privilege('authenticated', 'public.trigger_calendar_nudge_birikim()', 'EXECUTE')
     or has_function_privilege('anon', 'public.trigger_calendar_nudge_birikim()', 'EXECUTE') then
    raise exception '0119: trigger_calendar_nudge_birikim istemciden cagrilabilir olmamali';
  end if;
  if has_table_privilege('authenticated', 'public.birikim_hatirlatma_log', 'SELECT')
     or has_table_privilege('anon', 'public.birikim_hatirlatma_log', 'SELECT') then
    raise exception '0119: birikim_hatirlatma_log istemciye acik olmamali';
  end if;
  raise notice '0119 tamam: maas gunu birikim hatirlatmasi (10:30 TR) kuruldu.';
end $$;
