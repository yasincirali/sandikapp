-- 0174 — Mevduat vadesi doldu bildirimi (Ar-Ge turu 2026-11-07, madde 2)
--
-- Vadeli mevduat dönemi `mevduat_donemleri.vade_sonu`da biter (0088).
-- Uygulama o gün "Vadesi doldu" şeridini gösteriyordu ama push yoktu;
-- kullanıcı yeni faizi girmezse mevduatın değeri donuk kalıyor ve portföy
-- toplamı eskiyordu. Vade gününün sabahı TEK push: "Mevduatının vadesi
-- doldu · Yeni faiz oranını girersen değeri güncel kalır."
--   · Aynı edge function (`calendar-nudge`), aynı secret; an gövdeden
--     (`deposit_matured`). Diğer tetikleyiciler DEĞİŞMEZ. Hedef seçimi ve
--     gerekçeleri `calendar-nudge/index.ts` › "Mevduat vadesi doldu".
--   · Ekleyerek: yeni tablo + yeni fonksiyon + yeni cron işi. Eski istemci
--     `occasion`'ı tanımaz, push'a dokununca uygulamayı açar (genel dal).
--   · Defter `mevduat_vade_bildirim_log(donem_id)`: dönem başına bir
--     gönderim. Yeni dönem (yenileme) = yeni anahtar = yeni bildirim hakkı.
--     Dönem ya da hesap silinince cascade; edge function 60 günden eskisini
--     siler. Yasal metin değişmez: "bildirim kayıtları" zaten kapsıyor,
--     yeni kişisel veri ya da amaç yok (vade tarihi kullanıcının girdiği
--     mevcut veri).

-- ── 1) Gönderim defteri ─────────────────────────────────────────────────────
create table if not exists public.mevduat_vade_bildirim_log (
  donem_id uuid primary key
           references public.mevduat_donemleri(id) on delete cascade,
  user_id  uuid not null references auth.users(id) on delete cascade,
  sent_at  timestamptz not null default now()
);
alter table public.mevduat_vade_bildirim_log enable row level security;
alter table public.mevduat_vade_bildirim_log force  row level security;
-- Yalnız service role yazar/okur; istemcinin işi yok (politika da yok).
revoke all on table public.mevduat_vade_bildirim_log from public, anon, authenticated;
grant select, insert, update, delete on table public.mevduat_vade_bildirim_log to service_role;

-- ── 2) Tetikleyici (0119/0142 deseni) ───────────────────────────────────────
create or replace function public.trigger_calendar_nudge_mevduat_vade()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('calendar-nudge'),
    headers := public.cron_headers('calendar_nudge_cron_secret'),
    body := jsonb_build_object('occasion', 'deposit_matured'),
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.trigger_calendar_nudge_mevduat_vade() from public, anon, authenticated;

-- ── 3) Zamanlama: her gün 09:30 TR = 06:30 UTC ──────────────────────────────
-- Banka mesai başı: kullanıcı aynı sabah bankasının yeni oranını görür.
-- Sabah brifinginden (09:45), maaş günü (10:30) ve hediye (12:15)
-- hatırlatmalarından ayrı saatte.
select cron.unschedule(jobid) from cron.job where jobname = 'calendar-nudge-mevduat-vade';
select cron.schedule('calendar-nudge-mevduat-vade', '30 6 * * *',
  $$select public.trigger_calendar_nudge_mevduat_vade()$$);

-- Projede tüm cron işleri kapalıysa (yerel yığın / donmuş proje) bu iş de
-- kapalı kurulur (0087/0119/0142 kuralı).
do $$
begin
  if exists (select 1 from cron.job where jobname <> 'calendar-nudge-mevduat-vade')
     and not exists (select 1 from cron.job
                      where jobname <> 'calendar-nudge-mevduat-vade' and active) then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job where jobname = 'calendar-nudge-mevduat-vade';
    raise notice '0174: projede tum cron isleri kapali — calendar-nudge-mevduat-vade da kapali kuruldu.';
  end if;
end $$;

-- ── 4) Doğrulama ────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from cron.job
                  where jobname = 'calendar-nudge-mevduat-vade'
                    and schedule = '30 6 * * *') then
    raise exception '0174: calendar-nudge-mevduat-vade cron isi kurulmadi';
  end if;
  if has_function_privilege('authenticated', 'public.trigger_calendar_nudge_mevduat_vade()', 'EXECUTE')
     or has_function_privilege('anon', 'public.trigger_calendar_nudge_mevduat_vade()', 'EXECUTE') then
    raise exception '0174: trigger_calendar_nudge_mevduat_vade istemciden cagrilabilir olmamali';
  end if;
  if has_table_privilege('authenticated', 'public.mevduat_vade_bildirim_log', 'SELECT')
     or has_table_privilege('anon', 'public.mevduat_vade_bildirim_log', 'SELECT') then
    raise exception '0174: mevduat_vade_bildirim_log istemciye acik olmamali';
  end if;
  if not has_table_privilege('service_role', 'public.mevduat_vade_bildirim_log', 'INSERT') then
    raise exception '0174: service_role yazma grant eksik';
  end if;
  raise notice '0174 tamam: mevduat vade bildirimi kuruldu.';
end $$;
