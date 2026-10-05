-- 0114 — db_logs: başarılı çağrı satırları 1 gün, hatalar 30 gün (2026-10-05)
--
-- ⚠️ NUMARA GEÇİCİ (0109 notu): dağıtımdan ÖNCE iki sunucunun defterine
-- bakılır; doluysa sıradaki boş numaraya yeniden adlandırılır.
--
-- ## Ölçüm (kullanıcı, Tokyo, 2026-10-05)
-- Veritabanı 342 / 500 MB (Free plan). En büyük tablo `public.db_logs`:
-- 198 MB, ~305.600 satır — 30 günlük pencerede günde ~10.000 satır, 27
-- aylık aktif kullanıcıyla. Sonraki tablo 42 MB.
--
-- ## Neden başarılı satırlar
-- Yayın build'i (`kReleaseMode`) yalnız HATALARI yazar (`DbLogger.
-- _persistAsync`); yasal metin de "db_logs, yalnızca hatalar, 30 gün" der.
-- Başarılı (`is_error = false`) satırı yalnız debug/profile build'ler
-- (geliştirici cihazı, emülatör) yazar ve her 30 sn'lik fiyat nabzı
-- birkaç satır demektir. Bu satırlar teşhiste yalnız "şu an ne oluyor"
-- sorusuna yarar; 30 gün tutulmaları hem metne aykırı hem de tablonun
-- büyük kısmı olabilir.
--
-- ## Karar
-- * `is_error = false` satırları **1 gün**, hatalar eskisi gibi **30 gün**.
--   Destek panelinin `log_24h` sayacı (0071) 24 saate bakar; etkilenmez.
--   `seans_7g` / `cihazlar` özetleri artık hata satırlarından ve son günün
--   satırlarından beslenir — yayın build'inde zaten yalnız hata vardı.
-- * Fonksiyon adı, imzası ve cron işi (`db-logs-retention`, 03:15 UTC)
--   aynı kalır; yalnız gövde değişir. İstemci değişmez, eski sürümler
--   etkilenmez.
--
-- ## Boyut notu (0112 ile aynı)
-- DELETE yeri diske geri vermez; "Database size" düşsün diye ilk temizlikten
-- sonra bir kez `vacuum full public.db_logs;` (YAPMAN_GEREKENLER.md).

create or replace function public.cleanup_db_logs()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.db_logs
   where ts < now() - interval '30 days'
      or (not is_error and ts < now() - interval '1 day');
$$;

revoke all on function public.cleanup_db_logs() from public, anon, authenticated;

comment on function public.cleanup_db_logs() is
  'db_logs saklama: hatalar 30 gun (0056), basarili cagri satirlari 1 gun (0114).';

-- ── Doğrulama ──────────────────────────────────────────────────────────────
do $$
begin
  if position('1 day' in pg_get_functiondef('public.cleanup_db_logs()'::regprocedure)) = 0 then
    raise exception 'cleanup_db_logs basarili satirlari 1 gunde silmeli';
  end if;
  if not exists (select 1 from cron.job where jobname = 'db-logs-retention') then
    raise exception 'db-logs-retention isi yok (0056)';
  end if;
  if has_function_privilege('authenticated', 'public.cleanup_db_logs()', 'execute') then
    raise exception 'cleanup_db_logs authenticated tarafindan cagrilamamali';
  end if;
end $$;
