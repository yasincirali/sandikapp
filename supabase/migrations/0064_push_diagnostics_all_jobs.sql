-- 0064 — Teşhis körlüğü: `push_cron_jobs()` yalnızca analyze-signals'ı görüyordu
--
-- ## Belirti
--
-- "Push'ların hiçbiri çalışmıyor" şikayetinde Ayarlar → Push Teşhisi ekranı
-- yalnızca `analyze-signals%` job'larını listeliyordu. Sabah brifingi,
-- haftalık özet, fiyat alarmı, takvim dürtüsü ve canlı etkinlik cron'ları
-- ekranda HİÇ GÖRÜNMÜYORDU — kurulu olup olmadıkları, aktif olup olmadıkları
-- oradan okunamıyordu.
--
-- Bu, aracın tam da en çok ihtiyaç duyulduğu soruyu ("hangi iş çalışmıyor?")
-- cevaplayamaması demekti: ekran "her şey yolunda" görünürken beş cron'un
-- durumu hakkında hiçbir şey söylemiyordu.
--
-- ## Sebep
--
-- `0021`'de filtre bilinçliydi — o tarihte yalnızca sinyal cron'u vardı.
-- Sonradan altı cron daha eklendi (`0033` live activity, `0044` daily-brief,
-- `0046` price-alerts, `0048` calendar-nudge, `0052` weekly-summary,
-- `0053` fetch-inflation, `0063` observe-tefas-nav) ama filtre hiç
-- genişletilmedi. `push_cron_runs` `0022`'de zaten tüm job'lara açılmıştı;
-- `push_cron_jobs` geride kaldı ve ikisi ayrıştı.
--
-- ## Çözüm
--
-- Filtre kaldırılır: cron.job'daki TÜM işler döner. Teşhis ekranı zaten
-- salt okunur ve admin'e kilitli; job adları sır değildir ve eksik
-- gösterilen bir job, gösterilmeyen bir arıza demektir.
--
-- Ayrıca `son_calisma` ve `son_durum` eklendi: job'un kurulu olması
-- çalıştığı anlamına gelmez (`0054`'ün dersi — tetikleyici kuruluydu,
-- gövdesi hiç koşmamıştı). Kurulu/aktif/en son ne zaman ve nasıl bitti
-- bilgisini yan yana görmek, ikinci bir sorgu gerektirmeden ayrımı yapar.

-- ⚠️ DROP ŞART — `create or replace` BURADA YETMEZ.
--
-- Postgres bir fonksiyonun DÖNÜŞ TİPİNİ `create or replace` ile
-- değiştirmeye izin vermez. `returns table (...)` sütunları OUT
-- parametresi sayılır, yani iki sütun eklemek dönüş tipini değiştirmektir:
--
--     ERROR: 42P13: cannot change return type of existing function
--     DETAIL: Row type defined by OUT parameters is different.
--     HINT: Use DROP FUNCTION push_cron_jobs() first.
--
-- `if exists` eklidir: taze yığında (CI, `supabase start`) fonksiyon henüz
-- yoktur ve drop'un orada patlaması migration'ı kırardı.
--
-- Drop GRANT'ları da götürür; aşağıdaki `grant execute` bu yüzden bu
-- dosyada tekrar yazılır — kaldırma, yoksa teşhis ekranı "Yetkisiz" der.
drop function if exists public.push_cron_jobs();

create or replace function public.push_cron_jobs()
returns table (
  jobid       bigint,
  jobname     text,
  schedule    text,
  active      boolean,
  son_calisma timestamptz,
  son_durum   text
)
language plpgsql
stable
security definer
set search_path = public, cron
as $$
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;

  return query
  select
    j.jobid,
    j.jobname::text,
    j.schedule::text,
    j.active,
    -- En son çalışma: job kurulu ama hiç koşmamışsa null döner ve bu
    -- ayrım tam olarak aranan bilgidir.
    (select d.start_time
       from cron.job_run_details d
      where d.jobid = j.jobid
      order by d.start_time desc
      limit 1),
    (select d.status::text
       from cron.job_run_details d
      where d.jobid = j.jobid
      order by d.start_time desc
      limit 1)
  from cron.job j
  order by j.jobname;
end;
$$;

revoke all on function public.push_cron_jobs() from public, anon;
grant execute on function public.push_cron_jobs() to authenticated;

comment on function public.push_cron_jobs() is
  'Push teşhisi: TÜM cron işleri + son çalışma zamanı/durumu. 0021''deki '
  'analyze-signals filtresi kaldırıldı (0064) — eksik gösterilen job, '
  'gösterilmeyen arıza demekti. Admin only.';

-- ── Kendini doğrula ─────────────────────────────────────────────────────────
--
-- `0054`'ün dersi: sessizce uygulanmamış migration en pahalı hata sınıfı.
do $$
begin
  -- Fonksiyon gerçekten yeni imzayı taşıyor mu? (6 sütun)
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'push_cron_jobs'
      and pg_get_functiondef(p.oid) like '%son_calisma%'
  ) then
    raise exception '0064 uygulanamadi: push_cron_jobs hala eski imzada.';
  end if;

  -- Eski filtre gerçekten gitti mi?
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'push_cron_jobs'
      and pg_get_functiondef(p.oid) like '%analyze-signals%%'
  ) then
    raise exception '0064: analyze-signals filtresi hala yerinde.';
  end if;

  raise notice '0064 tamam: push_cron_jobs artik tum cron isleri gosteriyor.';
end;
$$;
