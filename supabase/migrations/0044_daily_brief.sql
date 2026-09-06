-- 0044_daily_brief.sql
-- ============================================================
-- Sabah brifingi: günde bir kez, kullanıcının KENDİ portföyüne dair
-- tek cümlelik bildirim.
--
-- Akış `analyze-signals` ile aynı: cron → trigger fonksiyonu → net.http_post
-- → edge function → FCM. Cihazın açık olması gerekmez.
--
-- Vault'ta `daily_brief_cron_secret` adıyla, edge function'daki
-- DAILY_BRIEF_CRON_SECRET ile AYNI string bulunmalıdır. Eşleşmezse
-- fonksiyon 401 "Yetkisiz cron cagrisi" döner.
-- ============================================================

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net;

-- ── Gönderim defteri ────────────────────────────────────────────────────────
--
-- Neden gerekli: cron günde bir koşar ama yeniden deneme, elle tetikleme ya
-- da bir dağıtım sonrası çift çalıştırma mümkün. Aynı güne ikinci bildirim
-- bildirim bütçesini harcamanın ötesinde güven kaybettirir (haftalık tavan
-- 5 bildirim, sinyaller dahil).
--
-- `sent_on` DATE'tir, timestamp değil: "bugün gönderildi mi" sorusu takvim
-- günü sorusudur ve saat karşılaştırması gereksiz kenar durumlar üretirdi.
create table if not exists public.daily_brief_log (
  user_id uuid not null references auth.users(id) on delete cascade,
  sent_on date not null default (now() at time zone 'Europe/Istanbul')::date,
  created_at timestamptz not null default now(),
  primary key (user_id, sent_on)
);

-- Retention: defterin geçmişi bir işe yaramıyor, yalnızca "bugün" sorusuna
-- cevap veriyor. 30 günden eskisini temizle ki tablo kullanıcı × gün
-- hızıyla sonsuza büyümesin.
create or replace function public.cleanup_daily_brief_log()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.daily_brief_log
   where sent_on < (now() at time zone 'Europe/Istanbul')::date - 30;
$$;

alter table public.daily_brief_log enable row level security;

-- İstemcinin bu tabloda hiçbir işi yok: yalnızca edge function
-- (service role, RLS'yi baypas eder) yazar ve okur. Politika TANIMLANMAZ,
-- yani RLS altında anon/authenticated hiçbir satır göremez.
revoke all on table public.daily_brief_log from anon, authenticated;

-- ── Tetikleyici ─────────────────────────────────────────────────────────────
create or replace function public.trigger_daily_brief()
returns void
language plpgsql
security definer
-- search_path sabitleniyor: security definer fonksiyonda arama yolu
-- kaçırılırsa yetki yükseltme vektörü olur.
set search_path = public, vault, net
as $$
declare
  function_url text := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/daily-brief';
  cron_secret  text;
begin
  select decrypted_secret into cron_secret
  from vault.decrypted_secrets
  where name = 'daily_brief_cron_secret';

  if cron_secret is null then
    raise exception 'Vault secret daily_brief_cron_secret bulunamadi';
  end if;

  perform net.http_post(
    url := function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || cron_secret
    ),
    body := jsonb_build_object('source', 'cron')
  );
end;
$$;

revoke all on function public.trigger_daily_brief() from public, anon, authenticated;
revoke all on function public.cleanup_daily_brief_log() from public, anon, authenticated;

-- ── Zamanlama ───────────────────────────────────────────────────────────────
-- Yeniden çalıştırılabilir olsun: varsa önce kaldır.
select cron.unschedule(jobid) from cron.job
 where jobname in ('daily-brief', 'daily-brief-cleanup');

-- pg_cron UTC ile çalışır. TR 09:45 = 06:45 UTC.
--
-- Neden sabah ve neden hafta içi:
--   · 09:45'te BIST henüz açılmamıştır; `price_history_cache` günlük kapanış
--     tutar, yani serinin son noktası bir önceki İŞLEM GÜNÜdür. Mesaj bu
--     yüzden "son kapanışta" der — "dün" pazartesi günü yanlış olurdu.
--   · Cache TTL'i 12 saat. Son `analyze-signals` turu 12:00 UTC; ertesi gün
--     06:45'te kayıt bayattır ve seri tazelenir, yani son kapanış GERÇEKTEN
--     serinin içindedir.
--   · Hafta sonu yeni kapanış olmadığı için brifing de yoktur (1-5).
select cron.schedule('daily-brief', '45 6 * * 1-5',
  $$select public.trigger_daily_brief()$$);

select cron.schedule('daily-brief-cleanup', '30 22 * * 0',
  $$select public.cleanup_daily_brief_log()$$);
