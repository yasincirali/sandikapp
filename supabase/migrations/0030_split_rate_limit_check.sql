-- 0030_split_rate_limit_check.sql
-- ============================================================
-- S8 (sahada gözlendi): Rate limit meşru kullanıcıyı kilitliyordu.
--
-- 0028'deki check_and_record_rate_limit kontrol ile kaydı tek çağrıda
-- birleştiriyordu. Bu, TOCTOU yarışını kapatmak için doğruydu; ancak
-- Edge Function bu tek çağrıyı daveti aramadan ÖNCE yapıyordu, yani
-- isteğin sonucu ne olursa olsun sayaç artıyordu:
--
--   - kod bulunamadı        → gerçek tahmin denemesi ✓ sayılmalı
--   - kendi kodunu girdi    → kullanıcı hatası ✗ sayılmamalı
--   - zaten ortak           → kullanıcı hatası ✗ sayılmamalı
--   - zaten talep edilmiş   → kullanıcı hatası ✗ sayılmamalı
--   - BAŞARILI eşleşme      → ✗ kesinlikle sayılmamalı
--
-- Sonuç: doğru kodu girip "zaten ortaksınız" alan bir kullanıcı beş
-- denemede kilitleniyordu. Gerçek kullanıcı 10 dakika bekletildi.
--
-- Ayrıca istemcideki kod giriş alanında biçimlendirme olmadığı için
-- (bkz. partner_code_formatter.dart) kullanıcılar "geçersiz format"
-- hatasını aşmaya çalışırken de sayacı tüketiyordu.
--
-- Çözüm: kontrol ve kayıt ayrıştırılır.
--   peek_rate_limit            → yalnız okur, YAZMAZ
--   record_rate_limit_attempt  → yalnız yazar
-- Edge Function önce peek eder, sonra YALNIZCA kod bulunamadığında
-- record çağırır.
--
-- TOCTOU notu: Kontrol ile kayıt arasına artık bir sorgu giriyor, yani
-- eşzamanlı istekler teorik olarak limiti birkaç deneme aşabilir.
-- Bu kabul edilebilir: rate limit'in amacı binlerce denemeyi
-- engellemek, tam olarak 5'te kesmek değil. Yanlış kilitlenen meşru
-- kullanıcının maliyeti, birkaç fazladan denemeden çok daha yüksek.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- peek_rate_limit — YALNIZCA kontrol eder, kayıt eklemez.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.peek_rate_limit(
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
    RETURN QUERY SELECT
      FALSE,
      GREATEST(
        1,
        CEIL(EXTRACT(EPOCH FROM (v_oldest + make_interval(secs => p_window_seconds) - now())))
      )::INTEGER;
    RETURN;
  END IF;

  RETURN QUERY SELECT TRUE, 0;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- record_rate_limit_attempt — YALNIZCA başarısız denemeyi kaydeder.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.record_rate_limit_attempt(
  p_subject TEXT,
  p_scope TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.rate_limit_attempts (subject, scope)
  VALUES (p_subject, p_scope);
END;
$$;

-- Yalnızca service-role çağırabilir; kullanıcı kendi sayacını
-- okuyamaz/sıfırlayamaz.
REVOKE ALL ON FUNCTION public.peek_rate_limit(TEXT, TEXT, INTEGER, INTEGER)
  FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_rate_limit_attempt(TEXT, TEXT)
  FROM public, anon, authenticated;

COMMENT ON FUNCTION public.peek_rate_limit(TEXT, TEXT, INTEGER, INTEGER) IS
  'Rate limit durumunu YALNIZCA okur, sayacı artırmaz. Çağıran, isteğin gerçekten başarısız bir tahmin olduğunu doğruladıktan sonra record_rate_limit_attempt ile ayrıca kaydeder.';

COMMENT ON FUNCTION public.record_rate_limit_attempt(TEXT, TEXT) IS
  'Başarısız tahmin denemesini kaydeder. Yalnızca gerçek tahmin hatalarında çağrılmalı — kullanıcı hataları (kendi kodu, zaten ortak) sayılmamalı, aksi halde meşru kullanıcı kilitlenir.';

-- check_and_record_rate_limit (0028) korunuyor: başka akışlar için
-- tek çağrılık atomik biçim hâlâ doğru seçim olabilir.
