-- 0178 — Kripto katalog işi 6 saatte bir (2026-11-10)
--
-- ## Neden (22 Eki kararı: "bir sonraki migration'la")
-- `kripto-katalog` (0074) saatte bir, günde 24 kez Binance'ten coin
-- listesini çekip katalogu yeniliyor. Katalog (hangi coinler var, adları)
-- nadiren değişir: yeni listeleme haftada birkaç kez, delist daha seyrek.
-- Saatlik ritim 0074'te yalnız ilk kurulumu hızlandırmak ve tek turluk
-- kesintiyi tolere etmek içindi; katalog kurulduktan sonra günde 24 edge
-- function çağrısı Free plan kotasından boşa gidiyor. 6 saatte bir hâlâ
-- günde 4 tur: tek tur kaçsa bile katalog aynı gün tazelenir.
--
-- ## Değişmeyen
-- Fonksiyon (`supabase/functions/kripto-katalog`) ve tetikleyici
-- (`trigger_kripto_katalog`) aynı; yalnız zamanlama. Dakika (10.) aynı
-- kalır: dakikalık `kripto-fiyat` ve 0164'teki hacim işiyle (7.) çakışmaz.
-- Fiyatlar etkilenmez (`kripto-fiyat` her dakika sürer).
--
-- ## Eski sürümler
-- İstemci tarafı yok. 0164 deseni: `alter_job` işin `active` bayrağına
-- DOKUNMAZ, adı ve komutu korur; iş yoksa (taze yığın, 0074 öncesi)
-- hiçbir şey yapılmaz.

do $$
declare
  j bigint;
begin
  select jobid into j from cron.job where jobname = 'kripto-katalog';
  if j is null then
    raise notice '0178: kripto-katalog isi yok, atlandi.';
    return;
  end if;
  perform cron.alter_job(job_id := j, schedule := '10 */6 * * *');
end $$;

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from cron.job
              where jobname = 'kripto-katalog'
                and schedule <> '10 */6 * * *') then
    raise exception '0178: kripto-katalog zamanlamasi 6 saate inmedi';
  end if;
end $$;
