-- 0028_server_side_rate_limit.sql
-- ============================================================
-- SECURITY: Sunucu taraflı rate limiting altyapısı.
--
-- Sorun (S1 — kritik): Davet kodu deneme limiti YALNIZCA istemcide,
-- SharedPreferences üzerinde tutuluyordu (auth_service.dart
-- _checkRateLimit). Bu koruma hiçbir şey ifade etmiyor:
--   - Uygulama verisini temizlemek sayacı sıfırlar,
--   - Kod istemciyi hiç çalıştırmadan Edge Function'a doğrudan
--     curl ile istek atabilir,
--   - Sayaç anahtarı `key.hashCode` — çakıştırılabilir, taşınabilir.
--
-- Sonuç: 10 karakterlik davet kodu (32^10 ≈ 1.1e15) teorik olarak
-- güçlü olsa da, aktif kod havuzu küçükken (24 saat geçerli, az
-- sayıda açık davet) sınırsız deneme hakkı ile taranabilir hale
-- geliyordu. Rate limit güvenlik sınırının YANLIŞ tarafındaydı.
--
-- Çözüm: Sayaç veritabanına taşınır. Edge Function service-role ile
-- bu tabloya yazar; istemci ne okuyabilir ne yazabilir (RLS policy
-- YOK = authenticated erişemez, service-role bypass eder).
--
-- Tablo genel amaçlıdır: `scope` alanı ile başka akışlar da
-- (OTP, hesap silme denemesi) aynı altyapıyı kullanabilir.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.rate_limit_attempts (
  id BIGSERIAL PRIMARY KEY,
  -- Kimi sınırlıyoruz: genelde auth.users(id), ama anonim akışlar
  -- için IP hash'i de olabilir. FK YOK — bu tablo kullanıcı silinse
  -- de kısa süre yaşayabilmeli (silme sonrası spam koruması).
  subject TEXT NOT NULL,
  -- Hangi akış: 'redeem_invite', 'delete_account', ...
  scope TEXT NOT NULL,
  -- Başarısız deneme zamanı.
  attempted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Pencere sorgusu bu indeksle çalışır: (subject, scope, zaman DESC).
CREATE INDEX IF NOT EXISTS ix_rate_limit_lookup
  ON public.rate_limit_attempts (subject, scope, attempted_at DESC);

-- Temizlik taraması için ayrı indeks.
CREATE INDEX IF NOT EXISTS ix_rate_limit_cleanup
  ON public.rate_limit_attempts (attempted_at);

ALTER TABLE public.rate_limit_attempts ENABLE ROW LEVEL SECURITY;
-- FORCE: tablo sahibi bile RLS'yi atlayamaz. Politika tanımlı
-- olmadığı için authenticated/anon rolleri hiçbir satıra erişemez.
-- Yalnızca service-role (Edge Function) okur/yazar.
ALTER TABLE public.rate_limit_attempts FORCE ROW LEVEL SECURITY;

REVOKE ALL ON public.rate_limit_attempts FROM anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- check_and_record_rate_limit
--
-- Tek çağrıda hem kontrol eder hem sayar (TOCTOU yarışını kapatır):
-- pencere içindeki deneme sayısı limite ulaştıysa `allowed=false`
-- döner ve YENİ kayıt EKLEMEZ (kilitli kullanıcı sayacı süresiz
-- uzatamaz — aksi halde saldırgan kendini kalıcı kilitleyip
-- pencerenin hiç kapanmamasına yol açabilirdi).
--
-- Döner: (allowed BOOLEAN, retry_after_seconds INTEGER)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.check_and_record_rate_limit(
  p_subject TEXT,
  p_scope TEXT,
  p_max_attempts INTEGER DEFAULT 5,
  p_window_seconds INTEGER DEFAULT 600
)
RETURNS TABLE (allowed BOOLEAN, retry_after_seconds INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cutoff TIMESTAMPTZ;
  v_count INTEGER;
  v_oldest TIMESTAMPTZ;
BEGIN
  -- Parametre sağlamlaştırma: çağıran taraf saçma değer geçse bile
  -- pencere/limit mantıklı sınırlarda kalsın.
  p_max_attempts := GREATEST(1, LEAST(COALESCE(p_max_attempts, 5), 100));
  p_window_seconds := GREATEST(1, LEAST(COALESCE(p_window_seconds, 600), 86400));

  v_cutoff := now() - make_interval(secs => p_window_seconds);

  SELECT COUNT(*), MIN(attempted_at)
  INTO v_count, v_oldest
  FROM public.rate_limit_attempts
  WHERE subject = p_subject
    AND scope = p_scope
    AND attempted_at >= v_cutoff;

  IF v_count >= p_max_attempts THEN
    -- Pencerenin en eski denemesi düştüğünde tekrar hak doğar.
    RETURN QUERY SELECT
      FALSE,
      GREATEST(
        1,
        CEIL(EXTRACT(EPOCH FROM (v_oldest + make_interval(secs => p_window_seconds) - now())))
      )::INTEGER;
    RETURN;
  END IF;

  INSERT INTO public.rate_limit_attempts (subject, scope)
  VALUES (p_subject, p_scope);

  RETURN QUERY SELECT TRUE, 0;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- clear_rate_limit — başarılı işlemden sonra sayacı sıfırlar.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.clear_rate_limit(
  p_subject TEXT,
  p_scope TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  DELETE FROM public.rate_limit_attempts
  WHERE subject = p_subject AND scope = p_scope;
END;
$$;

-- Bu fonksiyonlar YALNIZCA service-role tarafından çağrılır.
-- authenticated'a EXECUTE verilmez — aksi halde kullanıcı
-- clear_rate_limit çağırarak kendi limitini sıfırlayabilirdi.
REVOKE ALL ON FUNCTION public.check_and_record_rate_limit(TEXT, TEXT, INTEGER, INTEGER) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.clear_rate_limit(TEXT, TEXT) FROM public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- Eski kayıtları temizle — tablo sınırsız büyümesin.
-- pg_cron kuruluysa saatlik çalışır (0017'de extension zaten var).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.purge_old_rate_limit_attempts()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  DELETE FROM public.rate_limit_attempts
  WHERE attempted_at < now() - interval '24 hours';
END;
$$;

REVOKE ALL ON FUNCTION public.purge_old_rate_limit_attempts() FROM public, anon, authenticated;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- cron.unschedule bilinmeyen job adında hata verir; 0017'deki gibi
    -- yalnızca var olan job id'leri üzerinden kaldır.
    PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname = 'purge-rate-limit-attempts';

    PERFORM cron.schedule(
      'purge-rate-limit-attempts',
      '17 * * * *',
      $cron$SELECT public.purge_old_rate_limit_attempts();$cron$
    );
  END IF;
END $$;

COMMENT ON TABLE public.rate_limit_attempts IS
  'Sunucu taraflı rate limit sayacı. Yalnızca service-role (Edge Function) erişir; RLS politikası tanımlı değildir, bu yüzden anon/authenticated hiçbir satırı göremez. İstemci tarafındaki SharedPreferences sayacının yerini alır (bypass edilebiliyordu).';

COMMENT ON FUNCTION public.check_and_record_rate_limit(TEXT, TEXT, INTEGER, INTEGER) IS
  'Atomik kontrol+kayıt. Limit aşıldıysa allowed=false döner ve yeni kayıt EKLEMEZ (kilit süresiz uzamasın). retry_after_seconds istemciye gösterilecek bekleme süresidir.';
