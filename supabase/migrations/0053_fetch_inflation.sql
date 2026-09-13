-- 0053_fetch_inflation.sql
-- ============================================================
-- TÜFE endeksi otomatik çekimi + takvim kancasının kurtarılması.
--
-- İki açık borcu birden kapatır (bkz. TECHNICAL_DEBT.md):
--   1. "TÜFE endeksi elle dolduruluyor",
--   2. "Takvim kancasında gönderim defteri yok".
--
-- ## ⏰ SAAT SIRASI — bu dosyanın en kritik parçası
-- `calendar-nudge` ayın 3'ünde TR 10:15'te koşuyor ve tabloda BU AYIN
-- satırını arıyor; yoksa sessizce hiçbir şey göndermiyor.
--
-- Çekim bu yüzden TR 10:05'e kuruluyor — NUDGE'DAN 10 DAKİKA ÖNCE.
-- Borç kaydı `0 8 3 * *` (TR 11:00) öneriyordu ama o sıralama nudge'ı
-- hep bayat veriyle karşılaştırırdı ve otomatikleştirmenin asıl kazancı
-- kaybolurdu. Sıra: TÜİK 10:00 açıklar → 10:05 çekim → 10:15 bildirim.
--
-- ## Gönderim defteri — ayın 4'ü turunu AÇAN şey
-- `0048` ikinci turu (ayın 4'ü) YAZDI ama KAPALI bıraktı: defter olmadan,
-- veri 3'ünde zamanında girilirse iki bildirim giderdi.
--
-- Defter geldiği için ikinci tur artık AÇILIYOR. Çekim de iki gün koşuyor:
-- EVDS seriyi 3'ünde yayımlamazsa 4'ünde yakalanır.
--
-- `calendar_nudge_log` kullanıcı bazlı DEĞİL: kanca herkese aynı rakamı
-- gönderiyor, dolayısıyla "bu ay gönderildi mi" tek satırlık bir soru.
-- `occasion` + `period` yeter (borç kaydının önerdiği şekil).
-- ============================================================

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net;

-- ── Takvim kancası gönderim defteri ─────────────────────────────────────────
--
-- ⚠️ Bu tabloyu `calendar-nudge` fonksiyonu OKUMAK ve YAZMAK zorunda;
-- aksi halde ikinci tur çift bildirim gönderir. Fonksiyon güncellenmeden
-- ikinci turu açmak, kapatılma sebebinin aynısını geri getirir.
create table if not exists public.calendar_nudge_log (
  occasion text not null,
  -- Endeksin AİT OLDUĞU ay (`YYYY-MM-01`), gönderim günü değil: kanca
  -- ayın 3'ünde ya da 4'ünde gitse de aynı ayı anlatıyor.
  period date not null,
  sent_at timestamptz not null default now(),
  primary key (occasion, period)
);

comment on table public.calendar_nudge_log is
  'Takvim kancasi gonderim defteri. Kullanici bazli DEGIL: kanca herkese '
  'ayni rakami gonderir, "bu ay gonderildi mi" tek satirlik bir soru.';

alter table public.calendar_nudge_log enable row level security;

-- İstemcinin bu tabloda hiçbir işi yok: yalnızca edge function
-- (service role, RLS'yi baypas eder) yazar ve okur.
revoke all on table public.calendar_nudge_log from anon, authenticated;

create or replace function public.cleanup_calendar_nudge_log()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.calendar_nudge_log
   where period < (now() at time zone 'Europe/Istanbul')::date
                  - interval '18 months';
$$;

revoke all on function public.cleanup_calendar_nudge_log() from public, anon, authenticated;

-- ── Çekim tetikleyicisi ─────────────────────────────────────────────────────
create or replace function public.trigger_fetch_inflation()
returns void
language plpgsql
security definer
-- search_path sabitleniyor: security definer fonksiyonda arama yolu
-- kaçırılırsa yetki yükseltme vektörü olur.
set search_path = public, vault, net
as $$
declare
  function_url text := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/fetch-inflation';
  cron_secret  text;
begin
  select decrypted_secret into cron_secret
  from vault.decrypted_secrets
  where name = 'inflation_fetch_cron_secret';

  if cron_secret is null then
    raise exception 'Vault secret inflation_fetch_cron_secret bulunamadi';
  end if;

  perform net.http_post(
    url := function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || cron_secret
    ),
    body := jsonb_build_object('source', 'cron'),
    -- EVDS turu + 24 aylık upsert 5 saniyede bitmez. Süre aşımında
    -- pg_net yalnızca YANITI beklemeyi bırakır — fonksiyon sunucuda
    -- çalışmaya devam eder ve tabloyu yazar; sonuç "bazen çalışıyor" gibi
    -- görünür ve teşhis edilemez (bkz. 0040_cron_http_timeout.sql).
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.trigger_fetch_inflation() from public, anon, authenticated;

-- ── Zamanlama ───────────────────────────────────────────────────────────────
-- Yeniden çalıştırılabilir olsun: varsa önce kaldır.
select cron.unschedule(jobid) from cron.job
 where jobname in (
   'fetch-inflation', 'fetch-inflation-retry', 'calendar-nudge-log-cleanup'
 );

-- pg_cron UTC. TR 10:05 = 07:05 UTC, ayın 3'ü.
--
-- Nudge 07:15'te koşuyor; çekim ONDAN ÖNCE olmak ZORUNDA (dosya
-- başındaki saat sırası notu).
select cron.schedule('fetch-inflation', '5 7 3 * *',
  $$select public.trigger_fetch_inflation()$$);

-- İkinci tur: ayın 4'ü. EVDS seriyi 3'ünde yayımlamazsa burada yakalanır.
--
-- Çift YAZMA riski yok: fonksiyon `period` üzerinden upsert ediyor, aynı
-- ay ikinci kez yazılsa da tek satır kalır (üstelik TÜİK revizyonu
-- böylece otomatik yakalanır).
select cron.schedule('fetch-inflation-retry', '5 7 4 * *',
  $$select public.trigger_fetch_inflation()$$);

select cron.schedule('calendar-nudge-log-cleanup', '40 22 * * 0',
  $$select public.cleanup_calendar_nudge_log()$$);

-- ── Takvim kancasının ikinci turu ───────────────────────────────────────────
--
-- `0048`'de yazılmış ama KAPALI bırakılmıştı; defter geldiği için açılıyor.
--
-- ⚠️ ÖN KOŞUL: `calendar-nudge` fonksiyonu `calendar_nudge_log`'u okuyup
-- yazmalı. Fonksiyon güncellenmeden bu cron açılırsa veri 3'ünde zamanında
-- girildiğinde İKİ bildirim gider — yani `0048`'in kapatma sebebinin
-- aynısı geri gelir.
select cron.unschedule(jobid) from cron.job
 where jobname = 'calendar-nudge-inflation-retry';

select cron.schedule('calendar-nudge-inflation-retry', '15 7 4 * *',
  $$select public.trigger_calendar_nudge()$$);

-- ── Kendi kendini doğrula ───────────────────────────────────────────────────
--
-- Sessizce uygulanmamış bir cron, "çalıştığı sanılan ama çalışmayan" en
-- pahalı hata sınıfı (`0040` deseni).
do $$
declare
  v_fetch text;
  v_nudge text;
begin
  select schedule into v_fetch from cron.job where jobname = 'fetch-inflation';
  select schedule into v_nudge from cron.job
   where jobname = 'calendar-nudge-inflation';

  if v_fetch is null then
    raise exception 'fetch-inflation cron kurulamadi';
  end if;

  -- SIRA denetimi: çekim nudge'dan ÖNCE olmalı. İkisi de ayın 3'ünde
  -- koşuyor; dakika karşılaştırması yeter (07:05 < 07:15).
  if v_nudge is not null and v_fetch = v_nudge then
    raise exception
      'fetch-inflation ve calendar-nudge AYNI saatte — nudge bayat veri gorur';
  end if;

  if not exists (
    select 1 from cron.job where jobname = 'fetch-inflation-retry'
  ) then
    raise exception 'fetch-inflation-retry cron kurulamadi';
  end if;
end $$;
