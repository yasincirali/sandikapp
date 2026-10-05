-- 0112 — cron çalışma geçmişine saklama süresi (2026-10-05)
--
-- ⚠️ NUMARA GEÇİCİ (0109 notu): dağıtımdan ÖNCE iki sunucunun defterine
-- bakılır; 0112 doluysa sıradaki boş numaraya yeniden adlandırılır. Gövde
-- numaradan bağımsızdır.
--
-- ## İstek
-- Kullanıcı (2026-10-05), Supabase Free plan kullanım ekranı: Database size
-- 342 / 500 MB, Log Ingestion 1.22 / 1 GB, Log Query 206 / 100 GB.
-- "Bunu rahatlatmak için neler yapmalıyız?"
--
-- ## Bulgu
-- `cron.job_run_details` HİÇ silinmiyordu. pg_cron her çalışmada bir satır
-- yazar (komut metni + dönüş mesajı) ve kendiliğinden temizlemez. Bugünkü
-- takvimle günde ~1.900 çalışma: `kripto-fiyat` her dakika (1.440, 0074),
-- `yurt-ici-kotasyon` 5 dakikada bir (288, 0101), gerisi saatlik/günlük.
-- 0017'den beri biriken satırlar veritabanı boyutuna gidiyor ve teşhis
-- RPC'lerinin (`push_cron_jobs`, `push_cron_runs`; 0022/0064) her çağrıda
-- taradığı tabloyu büyütüyor (tabloda `jobid`/`start_time` indeksi yok).
--
-- ## Karar
-- * **7 gün** tutulur, ölçüt `start_time`. Teşhis ekranı son 100 çalışmayı
--   gösterir (`push_cron_runs`, üst sınır 100); dakikalık iş yüzünden o 100
--   satır zaten son ~1 saattir. Bir haftalık pay hafta sonu arızasını
--   Pazartesi görmeye yeter.
-- * **Her işin en son çalışması süre dolsa da kalır.** `push_cron_jobs` iş
--   başına "son çalışma"yı okur ve null'ı "hiç koşmamış" diye gösterir;
--   aylık/yıllık işler (fetch-inflation, calendar-nudge-year-end) 7 günden
--   eski tek satırlarını kaybetseydi teşhis yalan söylerdi.
-- * Desen 0056 / 0105: SECURITY DEFINER silme fonksiyonu (`set
--   search_path`, tam nitelikli adlar) + günlük pg_cron işi; anon /
--   authenticated için EXECUTE yok. cron şemasında YALNIZ DELETE — Supabase
--   belgeleri bu temizliği `postgres` rolüyle önerir; tablo/şema değişmez.
-- * Saat 03:35 UTC: mevcut saklama işlerinin arasında (03:15 db_logs,
--   03:25 snapshots, 03:45 yasal onaylar, 03:55 auth kaydı).
--
-- ## Eski sürümler
-- İstemci `cron` şemasını okumaz; teşhis RPC'lerinin imzası ve yanıt biçimi
-- değişmez. Yalnız EKLER.
--
-- ## Boyut notu
-- DELETE yeri Postgres'e geri verir, işletim sistemine değil: panelin
-- "Database size" sayısı ilk temizlikten sonra kendiliğinden düşmez, tablo
-- yeniden büyümez. Sayıyı düşürmek için bir kez `vacuum full
-- cron.job_run_details;` (YAPMAN_GEREKENLER.md). VACUUM işlem bloğunda
-- koşamadığı için migration'a yazılamaz.

create or replace function public.cron_gecmisi_saklama_temizle()
returns integer
language plpgsql
security definer
set search_path = cron, pg_temp
as $$
declare
  v_n integer;
begin
  delete from cron.job_run_details d
   where d.start_time < now() - interval '7 days'
     and d.runid not in (
       select max(x.runid) from cron.job_run_details x group by x.jobid
     );
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function public.cron_gecmisi_saklama_temizle() from public, anon, authenticated;

comment on function public.cron_gecmisi_saklama_temizle() is
  'cron.job_run_details 7 gun; her isin son calismasi korunur (push_cron_jobs '
  'null''i "hic kosmamis" okur). Yalniz DELETE (0112).';

select cron.unschedule(jobid) from cron.job where jobname = 'cron-gecmisi-saklama';
select cron.schedule('cron-gecmisi-saklama', '35 3 * * *',
  $$select public.cron_gecmisi_saklama_temizle()$$);

-- İki sunucu birebir: proje "tüm cron kapalı" kipindeyse (Frankfurt,
-- geçişe kadar) yeni iş de kapalı doğar (0102/0105 deseni birebir).
do $$
begin
  if exists (select 1 from cron.job where jobname <> 'cron-gecmisi-saklama')
     and not exists (select 1 from cron.job
                      where jobname <> 'cron-gecmisi-saklama' and active) then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job
      where jobname = 'cron-gecmisi-saklama';
    raise notice '0112: projede tum cron isleri kapali — saklama isi de kapali kuruldu.';
  end if;
end $$;

-- ── Doğrulama ──────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from cron.job
                  where jobname = 'cron-gecmisi-saklama'
                    and schedule = '35 3 * * *') then
    raise exception 'cron-gecmisi-saklama isi 35 3 * * * ile kurulmali';
  end if;
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'cron_gecmisi_saklama_temizle'
      and p.prosecdef
      and p.proconfig @> array['search_path=cron, pg_temp']
  ) then
    raise exception 'cron_gecmisi_saklama_temizle SECURITY DEFINER + search_path olmali';
  end if;
  if has_function_privilege('authenticated', 'public.cron_gecmisi_saklama_temizle()', 'execute')
     or has_function_privilege('anon', 'public.cron_gecmisi_saklama_temizle()', 'execute') then
    raise exception 'cron_gecmisi_saklama_temizle anon/authenticated tarafindan cagrilamamali';
  end if;
end $$;
