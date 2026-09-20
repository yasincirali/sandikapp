-- 0067_monthly_summary_pool_size.sql
-- ============================================================
-- İki küçük parça (2026-09-20 büyüme turu):
--
-- 1) AYLIK ÖZET cron'u. `weekly-summary` fonksiyonu `{"period":"month"}`
--    gövdesiyle geçen takvim ayını anlatır (fonksiyon başlığındaki
--    "Aylık özet" notu). Ayrı fonksiyon ve ayrı secret YOK: aynı
--    `weekly_summary_cron_secret` header'ı, aynı tercih sütunu
--    (`profiles.weekly_summary_push`).
--
--    Saat 06:30 UTC = TR 09:30, ayın 1'i. Brifing (06:45, Salı–Cuma) ve
--    haftalık (06:45, Pazartesi) ile AYNI GÜN ikinci push gitmesin diye
--    fonksiyon gönderdiği kullanıcıyı hem `weekly_summary_log`'a hem
--    `daily_brief_log`'a yazar; 15 dakika sonraki cron'lar o kullanıcıyı
--    "bugün gönderildi" görüp atlar. Bütçe kuralı korunur
--    (RETENTION_STRATEJISI.md §7: günde tek proaktif mesaj).
--
-- 2) `leaderboard_pool_size()` — yarış havuzunda kaç kişi var. Ana
--    ekrandaki "Katıl" kartı eşik dolana kadar "3 kişi katıldı · sıralama
--    8 kişide açılır" yazar; boş bir özelliğin "ölü" görünmesi yerine
--    dürüst bir sayı. Yalnızca SAYI döner (kimlik yok), k-anonimliği
--    (0031, k_min=8) etkilemez.
-- ============================================================

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net;

-- ── 1) Aylık özet tetikleyicisi ────────────────────────────────────────────
create or replace function public.trigger_monthly_summary()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/weekly-summary',
    headers := public.cron_headers('weekly_summary_cron_secret'),
    body := jsonb_build_object('source', 'cron', 'period', 'month'),
    -- Ay penceresi için 365 günlük snapshot taraması; 5 sn yetmez (0040).
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.trigger_monthly_summary() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job
 where jobname = 'monthly-summary';

-- pg_cron UTC: '30 6 1 * *' = her ayın 1'i TR 09:30.
select cron.schedule('monthly-summary', '30 6 1 * *',
  $$select public.trigger_monthly_summary()$$);

-- Çan sayfası kaydı: `app_notifications.type` CHECK kısıtı (0066) yeni türü
-- tanımalı; yoksa `recordAppNotification` her aylık push'ta düşer ve
-- bildirim çanda görünmez (push yine gider — sessiz eksiklik).
-- 0066'daki kısıt satır içi ve adsız → Postgres adı `<tablo>_<sütun>_check`.
alter table public.app_notifications
  drop constraint if exists app_notifications_type_check;
alter table public.app_notifications
  add constraint app_notifications_type_check check (type in (
    'partner_invite', 'daily_brief', 'weekly_summary', 'monthly_summary',
    'calendar_nudge'));

-- ── 2) Yarış havuzu boyutu ─────────────────────────────────────────────────
--
-- Tanım `get_percentile_bucket`/`get_top_gainers` ile AYNI havuz: son 24
-- saatte 30 günlük ROI snapshot'ı yazmış tekil kullanıcı. Farklı bir
-- tanım "8 kişi var ama sıralama açılmadı" çelişkisi üretirdi.
create or replace function public.leaderboard_pool_size()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(distinct user_id)::integer
    from public.user_roi_snapshots
   where period_days = 30
     and created_at >= now() - interval '24 hours';
$$;

revoke all on function public.leaderboard_pool_size() from public, anon;
grant execute on function public.leaderboard_pool_size() to authenticated;

-- ── Kendi kendini doğrula (0040/0052 deseni) ───────────────────────────────
do $$
begin
  if not exists (
    select 1 from cron.job
     where jobname = 'monthly-summary' and schedule = '30 6 1 * *'
  ) then
    raise exception 'monthly-summary cron kurulamadi';
  end if;

  if not has_function_privilege('authenticated', 'public.leaderboard_pool_size()', 'execute') then
    raise exception 'leaderboard_pool_size: authenticated EXECUTE yetkisi yok';
  end if;
  if has_function_privilege('anon', 'public.leaderboard_pool_size()', 'execute') then
    raise exception 'leaderboard_pool_size: anon EXECUTE yetkisi olmamali';
  end if;
end $$;
