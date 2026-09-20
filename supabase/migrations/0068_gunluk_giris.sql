-- 0068_gunluk_giris.sql
-- ============================================================
-- Günlük giriş turu (2026-09-20) — üç bildirim, bir tercih:
--
-- 1) TAKİP LİSTESİ HAREKETİ. Kapanış sonrası (TR 18:25, hafta içi)
--    `check-price-alerts` fonksiyonu `{"watchlist":true}` gövdesiyle çağrılır;
--    kullanıcının izlediği varlıklardan %5'ten fazla oynayanları tek push'ta
--    söyler (`_shared/watchlist_moves.ts`). Aynı fonksiyon ve aynı
--    `price_alerts_cron_secret`: yeni secret AÇILMADI — alarm kanalının
--    doğal uzantısı, kullanıcı seçimli bildirim.
--    Defter: `watchlist_move_log(user_id, sent_on)` — günde tek push.
--
-- 2) TÜFE GÜNÜ. `fetch-inflation` yeni ay yazdığında herkese oranı gönderir
--    (`_shared/tufe_push.ts`). Defter: `inflation_push_log(period)` — cron
--    aynı gün birkaç kez koşsa da (0053) ikinci push yok.
--
-- 3) BRİFİNG SAATİ. `profiles.brief_slot` ('morning' | 'evening').
--    `daily-brief` sabah koşusu yalnızca 'morning', akşam koşusu (TR 18:30,
--    hafta içi, `{"slot":"evening"}`) yalnızca 'evening' kullanıcılarına
--    gönderir. Bütçe (günde tek proaktif push) korunur: her kullanıcı iki
--    slotun yalnızca birinde. Pazartesi haftalık özet sabah gider; akşam
--    slotundaki kullanıcı o gün ayrıca brifing almaz (fonksiyon
--    `weekly_summary_log`'a bakar).
--
-- `app_notifications.type` CHECK kısıtı iki yeni türle genişletilir.
-- ============================================================

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net;

-- ── Defterler ──────────────────────────────────────────────────────────────
create table if not exists public.watchlist_move_log (
  user_id uuid not null references auth.users(id) on delete cascade,
  sent_on date not null default (now() at time zone 'Europe/Istanbul')::date,
  created_at timestamptz not null default now(),
  primary key (user_id, sent_on)
);
alter table public.watchlist_move_log enable row level security;
revoke all on table public.watchlist_move_log from anon, authenticated;

create table if not exists public.inflation_push_log (
  period date primary key,
  sent_at timestamptz not null default now()
);
alter table public.inflation_push_log enable row level security;
revoke all on table public.inflation_push_log from anon, authenticated;

create or replace function public.cleanup_watchlist_move_log()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.watchlist_move_log
   where sent_on < (now() at time zone 'Europe/Istanbul')::date - 30;
$$;
revoke all on function public.cleanup_watchlist_move_log() from public, anon, authenticated;

-- ── Bildirim türleri ───────────────────────────────────────────────────────
alter table public.app_notifications
  drop constraint if exists app_notifications_type_check;
alter table public.app_notifications
  add constraint app_notifications_type_check check (type in (
    'partner_invite', 'daily_brief', 'weekly_summary', 'monthly_summary',
    'watchlist_move', 'inflation_day', 'calendar_nudge'));

-- ── Brifing saati tercihi ──────────────────────────────────────────────────
-- `profiles`ta çünkü SUNUCU okuyor (0049/0052 deseni). Ortak politikası
-- profil satırını okuyabilir; bu sütun hassas değil.
alter table public.profiles
  add column if not exists brief_slot text not null default 'morning';
alter table public.profiles
  drop constraint if exists profiles_brief_slot_check;
alter table public.profiles
  add constraint profiles_brief_slot_check check (brief_slot in ('morning', 'evening'));
comment on column public.profiles.brief_slot is
  'Gunluk brifing slotu: morning = TR 09:45 (hafta ici), evening = TR 18:30 (kapanis).';

-- ── Tetikleyiciler ─────────────────────────────────────────────────────────
create or replace function public.trigger_watchlist_moves()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/check-price-alerts',
    headers := public.cron_headers('price_alerts_cron_secret'),
    body := jsonb_build_object('source', 'cron', 'watchlist', true),
    timeout_milliseconds := 60000
  );
end;
$$;
revoke all on function public.trigger_watchlist_moves() from public, anon, authenticated;

create or replace function public.trigger_daily_brief_evening()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/daily-brief',
    headers := public.cron_headers('daily_brief_cron_secret'),
    body := jsonb_build_object('source', 'cron', 'slot', 'evening'),
    timeout_milliseconds := 60000
  );
end;
$$;
revoke all on function public.trigger_daily_brief_evening() from public, anon, authenticated;

-- ── Zamanlama (pg_cron UTC; TR = UTC+3) ────────────────────────────────────
select cron.unschedule(jobid) from cron.job
 where jobname in ('watchlist-moves', 'watchlist-moves-cleanup', 'daily-brief-evening');

-- BIST kapanış seansı 18:10'da biter; 18:25 TR = 15:25 UTC, hafta içi.
select cron.schedule('watchlist-moves', '25 15 * * 1-5',
  $$select public.trigger_watchlist_moves()$$);
select cron.schedule('watchlist-moves-cleanup', '40 22 * * 0',
  $$select public.cleanup_watchlist_move_log()$$);
-- Akşam brifingi 18:30 TR = 15:30 UTC, hafta içi.
select cron.schedule('daily-brief-evening', '30 15 * * 1-5',
  $$select public.trigger_daily_brief_evening()$$);

-- ── Kendi kendini doğrula ──────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from cron.job where jobname = 'watchlist-moves' and schedule = '25 15 * * 1-5') then
    raise exception 'watchlist-moves cron kurulamadi';
  end if;
  if not exists (select 1 from cron.job where jobname = 'daily-brief-evening' and schedule = '30 15 * * 1-5') then
    raise exception 'daily-brief-evening cron kurulamadi';
  end if;
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'profiles' and column_name = 'brief_slot'
  ) then
    raise exception 'profiles.brief_slot eklenemedi';
  end if;
end $$;
