-- 0052_weekly_summary.sql
-- ============================================================
-- Haftalık özet bildirimi.
--
-- Akış `daily-brief` ile birebir aynı: cron → trigger fonksiyonu →
-- net.http_post → edge function → FCM.
--
-- Vault'ta `weekly_summary_cron_secret` adıyla, edge function'daki
-- WEEKLY_SUMMARY_CRON_SECRET ile AYNI string bulunmalıdır. Eşleşmezse
-- fonksiyon 401 "Yetkisiz cron cagrisi" döner.
--
-- ## ⚠️ EN KRİTİK PARÇA: aynı gün İKİ push gitmemeli
-- Haftalık özet Pazartesi TR 09:45'te gidiyor — sabah brifinginin TAM
-- OLARAK aynı slotu. Bu yüzden brifing cron'u `1-5` → `2-5` daraltılıyor
-- ve Pazartesi SÖZÜ haftalık özete bırakılıyor. Yeni bir bildirim slotu
-- açılmıyor (RETENTION_STRATEJISI.md §7: haftalık tavan 5, günde tek
-- proaktif mesaj).
--
-- `0044`'ü yerinde DÜZENLEMEK işe yaramaz: Supabase uygulanmış
-- migration'ları sürümle izliyor, dosyayı değiştirmek onu yeniden
-- koşturmaz ve üretimde `1-5` kalırdı. Bu yüzden yeniden zamanlama
-- BURADA yapılıyor — `0024_signal_frequency.sql`'in `0017`'yi
-- değiştirirken kullandığı desenin aynısı.
-- ============================================================

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net;

-- ── Gönderim defteri ────────────────────────────────────────────────────────
--
-- `daily_brief_log` ile aynı gerekçe: cron haftada bir koşar ama yeniden
-- deneme, elle tetikleme ya da bir dağıtım sonrası çift çalıştırma mümkün.
-- Aynı haftaya ikinci bildirim, bütçeyi harcamanın ötesinde güven
-- kaybettirir.
--
-- `sent_on` DATE'tir ve Pazartesi tarihini taşır: "bu hafta gönderildi mi"
-- sorusu takvim günü sorusudur.
create table if not exists public.weekly_summary_log (
  user_id uuid not null references auth.users(id) on delete cascade,
  sent_on date not null default (now() at time zone 'Europe/Istanbul')::date,
  created_at timestamptz not null default now(),
  primary key (user_id, sent_on)
);

-- Retention: defterin geçmişi bir işe yaramıyor, yalnızca "bu hafta"
-- sorusuna cevap veriyor. 90 günden eskisini temizle (haftalık kayıt
-- olduğu için brifingin 30 gününden uzun bir pencere yeter).
create or replace function public.cleanup_weekly_summary_log()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.weekly_summary_log
   where sent_on < (now() at time zone 'Europe/Istanbul')::date - 90;
$$;

alter table public.weekly_summary_log enable row level security;

-- İstemcinin bu tabloda hiçbir işi yok: yalnızca edge function
-- (service role, RLS'yi baypas eder) yazar ve okur. Politika TANIMLANMAZ,
-- yani RLS altında anon/authenticated hiçbir satır göremez.
revoke all on table public.weekly_summary_log from anon, authenticated;

-- ── Kullanıcı tercihi ───────────────────────────────────────────────────────
--
-- Tercih `profiles`ta çünkü SUNUCU okuyor; cihaz tercihleri
-- (SharedPreferences) edge function'dan görünmez. `0049`
-- (`partner_activity_push`) ile aynı desen.
--
-- ⚠️ `profiles_select_partner` politikası ortağın tüm profil satırını
-- okumasına izin veriyor. Bu kolon hassas değil (yalnızca bir bildirim
-- tercihi), o yüzden sorun yok — ama buraya hassas bir şey eklenmemeli.
alter table public.profiles
  add column if not exists weekly_summary_push boolean not null default true;

comment on column public.profiles.weekly_summary_push is
  'Haftalik ozet bildirimi gonderilsin mi. Pazartesi TR 09:45, sabah '
  'brifinginin YERINE gider — ayri bir slot degil.';

-- ── Tetikleyici ─────────────────────────────────────────────────────────────
create or replace function public.trigger_weekly_summary()
returns void
language plpgsql
security definer
-- search_path sabitleniyor: security definer fonksiyonda arama yolu
-- kaçırılırsa yetki yükseltme vektörü olur.
set search_path = public, vault, net
as $$
declare
  function_url text := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/weekly-summary';
  cron_secret  text;
begin
  select decrypted_secret into cron_secret
  from vault.decrypted_secrets
  where name = 'weekly_summary_cron_secret';

  if cron_secret is null then
    raise exception 'Vault secret weekly_summary_cron_secret bulunamadi';
  end if;

  perform net.http_post(
    url := function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || cron_secret
    ),
    body := jsonb_build_object('source', 'cron'),
    -- timeout_milliseconds AÇIKÇA verilmeli: pg_net varsayılanı 5 sn ve
    -- bu tur için yetersiz. Süre aşımında pg_net yalnızca YANITI beklemeyi
    -- bırakır — fonksiyon sunucuda çalışmaya devam eder ve bildirimleri
    -- gönderir; sonuç "bazen çalışıyor" gibi görünür ve teşhis edilemez
    -- (bkz. 0040_cron_http_timeout.sql).
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.trigger_weekly_summary() from public, anon, authenticated;
revoke all on function public.cleanup_weekly_summary_log() from public, anon, authenticated;

-- ── Zamanlama ───────────────────────────────────────────────────────────────
-- Yeniden çalıştırılabilir olsun: varsa önce kaldır.
select cron.unschedule(jobid) from cron.job
 where jobname in ('weekly-summary', 'weekly-summary-cleanup');

-- pg_cron UTC ile çalışır. TR 09:45 = 06:45 UTC, PAZARTESİ (1).
--
-- Brifingle AYNI saat ve bu kasıtlı: Pazartesi sözü haftalık özete ait,
-- brifing o gün susuyor (aşağıda `2-5`'e daraltılıyor). İki ayrı saat
-- seçmek ikinci bir bildirim slotu açmak olurdu.
select cron.schedule('weekly-summary', '45 6 * * 1',
  $$select public.trigger_weekly_summary()$$);

select cron.schedule('weekly-summary-cleanup', '20 22 * * 0',
  $$select public.cleanup_weekly_summary_log()$$);

-- ── Sabah brifingini PAZARTESİ sustur ───────────────────────────────────────
--
-- `0044:103`'te `45 6 * * 1-5` idi. Pazartesi haftalık özete bırakılıyor;
-- kullanıcı o gün İKİ bildirim almamalı.
--
-- Geri kalan gerekçe `0044`'teki gibi: 09:45'te BIST açılmamıştır ve son
-- kapanış bir önceki işlem günüdür; hafta sonu yeni kapanış olmadığı için
-- brifing de yoktur.
select cron.unschedule(jobid) from cron.job
 where jobname = 'daily-brief';

select cron.schedule('daily-brief', '45 6 * * 2-5',
  $$select public.trigger_daily_brief()$$);

-- ── Kendi kendini doğrula ───────────────────────────────────────────────────
--
-- Sessizce uygulanmamış bir cron, "çalıştığı sanılan ama çalışmayan"
-- en pahalı hata sınıfı. `0040`'ın deseni: migration kendi sonucunu
-- denetler ve tutmuyorsa YÜKSEK SESLE patlar.
do $$
begin
  if not exists (
    select 1 from cron.job
     where jobname = 'weekly-summary' and schedule = '45 6 * * 1'
  ) then
    raise exception 'weekly-summary cron kurulamadi';
  end if;

  if not exists (
    select 1 from cron.job
     where jobname = 'daily-brief' and schedule = '45 6 * * 2-5'
  ) then
    raise exception 'daily-brief Pazartesi susturulamadi — ayni gun iki push riski';
  end if;
end $$;
