-- 0179 — `analiz-topla` yalnız batch günlerinde (2026-11-10)
--
-- ## Neden (Ar-Ge 22 Eki 17:15 #2; 0178 kripto-katalog ile aynı karar)
-- `analiz-topla` (0117) saatte bir, haftanın her günü koşuyor; oysa
-- toplayacağı bir şey yalnız iki pencerede olur:
--   * `analiz-hazirla-haftalik` Pazar 17:00'de (cron saati UTC) Message Batch gönderir,
--   * `analiz-hazirla-aylik` ayın 1'i 03:00'te gönderir.
-- Anthropic bir batch'i en geç 24 saatte bitirir. Kalan günlerde her
-- çağrı boş döner ve Free plan edge function kotasından düşer (ayda ~720
-- çağrının ~550'si boşa).
--
-- Yeni zamanlama `25 * 1,2 * 0,1`: pg_cron (Vixie cron gibi) ayın günü
-- ve haftanın günü İKİSİ de kısıtlıysa "ya biri ya öteki" eşler. Yani
-- Pazar + Pazartesi her saat (haftalık batch Pazar 17:00 → Pazartesi
-- 17:00 arası biter) ve ayın 1–2'si her saat (aylık batch 1'i 03:00 →
-- 2'si 03:00). Dakika (25.) aynı. 26 saatlik "bitmedi → hata" kontrolü
-- de pencere içinde kalır: haftalıkta 30 saat, aylıkta 44 saat koşar.
--
-- ## Dikkat: elle gönderim
-- `select public.trigger_analiz_hazirla(...)` batch günü dışında elle
-- koşulursa sonuç kendiliğinden toplanmaz; ardından birkaç saat içinde
-- `select public.trigger_analiz_topla();` elle koşulur ya da sonraki
-- Pazar'ı bekler (batch sonucu Anthropic'te 29 gün durur, kayıp olmaz).
--
-- ## Değişmeyen
-- Fonksiyonlar ve tetikleyiciler aynı; yalnız zamanlama. İstemci tarafı
-- yok. 0164/0178 deseni: `alter_job` `active` bayrağına dokunmaz; iş yoksa
-- (taze yığın) hiçbir şey yapılmaz.

do $$
declare
  j bigint;
begin
  select jobid into j from cron.job where jobname = 'analiz-topla';
  if j is null then
    raise notice '0179: analiz-topla isi yok, atlandi.';
    return;
  end if;
  perform cron.alter_job(job_id := j, schedule := '25 * 1,2 * 0,1');
end $$;

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from cron.job
              where jobname = 'analiz-topla'
                and schedule <> '25 * 1,2 * 0,1') then
    raise exception '0179: analiz-topla zamanlamasi batch gunlerine inmedi';
  end if;
end $$;
