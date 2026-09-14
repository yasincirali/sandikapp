-- 0056 — Derinlemesine savunma: FORCE RLS + db_logs 30 gün saklama
--
-- ## FORCE ROW LEVEL SECURITY
-- RLS "enable" edilmiş bir tabloda tablo SAHİBİ politikalardan muaftır.
-- Supabase'de sahip `postgres` (superuser) olduğu için bu pratikte
-- kapalı bir kapı değil; ama bir gün tablo sahipliği başka bir role
-- devredilirse ya da bir SECURITY DEFINER fonksiyon sahibi role düşerse
-- politika sessizce devre dışı kalır. FORCE bunu kapatır. 2026-09
-- denetimi L9: yalnızca `disclaimer_acceptances` (0008) ve
-- `rate_limit_attempts` (0028) FORCE'luydu.
--
-- `service_role` BYPASSRLS taşır — edge function'lar etkilenmez.
--
-- ## db_logs saklama
-- 2026-05 şemasında "30 gün retention: pg_cron varsa aktif edilebilir"
-- YORUM SATIRINDAYDI; release'te hata satırları süresiz birikiyordu
-- (2026-09 denetimi L6). Günde bir kez 03:15 UTC'de 30 günden eski
-- satırlar silinir.

do $$
declare
  t text;
begin
  foreach t in array array[
    'profiles', 'assets', 'snapshots', 'partner_invites', 'partnerships',
    'user_push_tokens', 'disclaimer_acceptances', 'db_logs',
    'watchlist', 'price_alerts', 'signal_preferences', 'signal_notifications',
    'signal_state', 'milestones', 'live_activity_sessions',
    'user_roi_snapshots', 'user_allocation_snapshots', 'inflation_index',
    'rate_limit_attempts'
  ] loop
    if to_regclass('public.' || t) is not null then
      execute format('alter table public.%I force row level security', t);
    end if;
  end loop;
end $$;

create extension if not exists pg_cron with schema pg_catalog;

create or replace function public.cleanup_db_logs()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.db_logs where ts < now() - interval '30 days';
$$;

revoke all on function public.cleanup_db_logs() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'db-logs-retention';
select cron.schedule('db-logs-retention', '15 3 * * *',
  $$select public.cleanup_db_logs()$$);
