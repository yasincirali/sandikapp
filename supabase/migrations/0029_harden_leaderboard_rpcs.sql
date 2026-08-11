-- 0029_harden_leaderboard_rpcs.sql
-- ============================================================
-- SECURITY: Leaderboard RPC'lerinde k-anonymity bypass'ı ve
-- snapshot veri doğrulama eksikliğini kapat.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- S2 (yüksek): get_top_gainers_allocation — p_top_n sınırsızdı.
--
-- k=20 kontrolü "en az 20 katılımcı var mı?" sorusunu yanıtlıyor,
-- ama kaç satır DÖNDÜĞÜNÜ sınırlamıyordu. İki yönlü sızıntı vardı:
--
--   1. p_top_n = 1  → tek bir kullanıcının ROI'si + tam varlık
--      dağılımı izole edilir. k-anonymity'nin amacı tam olarak
--      bunu engellemekti; "20 kişi var" demek, o 20 kişinin
--      içinden birini tek başına göstermeyi meşrulaştırmaz.
--      Saldırgan p_top_n=1 ile en iyi portföyü, ardından ROI
--      eşiklerini gözleyerek sıradakileri ayrıştırabilir.
--
--   2. p_top_n = 100000 → "top-N" agregatı fiilen tüm katılımcı
--      havuzunun dökümüne dönüşür. (roi_pct, allocation) çiftleri
--      zamanla izlenerek kullanıcılar birbirinden ayırt edilebilir
--      (fingerprinting) — user_id dönmese bile.
--
-- Çözüm: p_top_n sunucuda [3, 10] aralığına clamp edilir. Alt
-- sınır 3, tekil ifşayı imkânsız kılar; üst sınır 10, k=20
-- havuzunun yarısından fazlasının dökülmesini engeller.
-- İstemcinin geçtiği değere GÜVENİLMEZ.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_top_gainers_allocation(
  p_period_days INTEGER,
  p_top_n INTEGER DEFAULT 5
)
RETURNS TABLE (
  rank INTEGER,
  roi_pct NUMERIC,
  allocation_pct JSONB,
  type_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  k_min INTEGER := 20; -- k-anonymity minimum
  n_min INTEGER := 3;  -- tekil ifşa koruması: asla 3'ten az satır dönme
  n_max INTEGER := 10; -- havuzun yarısından fazlası dökülmesin
  v_total INTEGER;
  v_top_n INTEGER;
BEGIN
  -- Yalnızca beklenen periyotlar. Rastgele p_period_days ile
  -- havuz bölünüp k eşiğinin altına düşürülemesin (bkz. S4).
  IF p_period_days NOT IN (7, 30, 365) THEN
    RETURN;
  END IF;

  -- İstemciden gelen p_top_n güvenli aralığa zorlanır.
  v_top_n := LEAST(GREATEST(COALESCE(p_top_n, 5), n_min), n_max);

  SELECT COUNT(DISTINCT user_id) INTO v_total
  FROM user_roi_snapshots
  WHERE period_days = p_period_days
    AND created_at >= now() - interval '24 hours';

  IF v_total < k_min THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH latest_roi AS (
    SELECT DISTINCT ON (user_id) user_id, roi_pct
    FROM user_roi_snapshots
    WHERE period_days = p_period_days
      AND created_at >= now() - interval '24 hours'
    ORDER BY user_id, created_at DESC
  ),
  latest_alloc AS (
    SELECT DISTINCT ON (user_id) user_id, allocation_pct, type_count
    FROM user_allocation_snapshots
    WHERE created_at >= now() - interval '24 hours'
      AND type_count >= 2
    ORDER BY user_id, created_at DESC
  ),
  joined AS (
    SELECT r.roi_pct, a.allocation_pct, a.type_count
    FROM latest_roi r
    INNER JOIN latest_alloc a ON a.user_id = r.user_id
    ORDER BY r.roi_pct DESC
    LIMIT v_top_n
  )
  SELECT
    ROW_NUMBER() OVER (ORDER BY j.roi_pct DESC)::INTEGER AS rank,
    j.roi_pct,
    j.allocation_pct,
    j.type_count
  FROM joined j;
END;
$$;

REVOKE ALL ON FUNCTION get_top_gainers_allocation(INTEGER, INTEGER) FROM public, anon;
GRANT EXECUTE ON FUNCTION get_top_gainers_allocation(INTEGER, INTEGER) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- S4 (orta): get_percentile_bucket — p_period_days doğrulanmıyordu.
--
-- Tabloda CHECK (period_days IN (7,30,365)) var, yani sahte bir
-- periyot yazılamaz; ama RPC yine de doğrulamalı: aksi halde
-- p_period_days=9999 sessizce boş sonuç döner ve gelecekte tabloya
-- yeni bir periyot eklendiğinde havuz istemeden bölünebilir.
-- Derinlemesine savunma.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_percentile_bucket(p_period_days INTEGER)
RETURNS TABLE (percentile INTEGER, total_participants INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_my_roi NUMERIC;
  v_total INTEGER;
  v_rank INTEGER;
  k_min INTEGER := 20;
BEGIN
  IF p_period_days NOT IN (7, 30, 365) THEN
    RETURN;
  END IF;

  SELECT roi_pct INTO v_my_roi
  FROM user_roi_snapshots
  WHERE user_id = auth.uid()
    AND period_days = p_period_days
    AND created_at >= now() - interval '24 hours'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_my_roi IS NULL THEN
    RETURN;
  END IF;

  WITH latest_per_user AS (
    SELECT DISTINCT ON (user_id) user_id, roi_pct
    FROM user_roi_snapshots
    WHERE period_days = p_period_days
      AND created_at >= now() - interval '24 hours'
    ORDER BY user_id, created_at DESC
  )
  SELECT
    COUNT(*)::INTEGER,
    COUNT(*) FILTER (WHERE roi_pct > v_my_roi)::INTEGER + 1
  INTO v_total, v_rank
  FROM latest_per_user;

  IF v_total < k_min THEN
    RETURN;
  END IF;

  RETURN QUERY SELECT
    GREATEST(1, LEAST(100, (v_rank * 100 / v_total)))::INTEGER,
    v_total;
END;
$$;

REVOKE ALL ON FUNCTION get_percentile_bucket(INTEGER) FROM public, anon;
GRANT EXECUTE ON FUNCTION get_percentile_bucket(INTEGER) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- S5 (orta): snapshot tablolarında girdi doğrulaması yoktu.
--
-- user_roi_snapshots.roi_pct ve user_allocation_snapshots.*
-- doğrudan istemciden geliyor ve RLS yalnızca "user_id = auth.uid()"
-- kontrolü yapıyor — DEĞERİ denetleyen hiçbir şey yoktu. Kötü niyetli
-- bir istemci roi_pct = 999999999 yazıp leaderboard'un tepesine
-- yerleşebilir, top_gainers agregatını kalıcı olarak zehirleyebilirdi.
--
-- NUMERIC(10,4) taşma hatası verir ama bu bir doğrulama değil;
-- 999999.9999 hâlâ kabul edilirdi. Gerçekçi bir tavan koyuyoruz:
-- ROI %-100 (tamamen kayıp) ile %100000 arasında olmalı.
-- ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'user_roi_snapshots_roi_range_check'
  ) THEN
    -- Mevcut aykırı satırları önce temizle, yoksa ALTER başarısız olur.
    DELETE FROM public.user_roi_snapshots
    WHERE roi_pct < -100 OR roi_pct > 100000;

    ALTER TABLE public.user_roi_snapshots
      ADD CONSTRAINT user_roi_snapshots_roi_range_check
      CHECK (roi_pct >= -100 AND roi_pct <= 100000);
  END IF;
END $$;

-- CHECK constraint'ten çağrılabilmesi için IMMUTABLE olmalı.
-- jsonb_object_keys üzerinde saf bir sayım — girdi aynıysa sonuç aynı.
CREATE OR REPLACE FUNCTION public.jsonb_key_count(p_data JSONB)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT CASE
    WHEN jsonb_typeof(p_data) = 'object'
      THEN (SELECT COUNT(*)::INTEGER FROM jsonb_object_keys(p_data))
    ELSE 0
  END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'user_allocation_type_count_check'
  ) THEN
    DELETE FROM public.user_allocation_snapshots
    WHERE type_count < 0 OR type_count > 50;

    ALTER TABLE public.user_allocation_snapshots
      ADD CONSTRAINT user_allocation_type_count_check
      CHECK (type_count >= 0 AND type_count <= 50);
  END IF;

  -- allocation_pct bir JSON NESNESİ olmalı (dizi/string/sayı değil).
  -- Aksi halde RPC'yi tüketen istemci beklenmedik tip alır.
  --
  -- NOT: CHECK içinde alt-sorgu (SELECT ... FROM jsonb_object_keys(...))
  -- kullanılamaz — Postgres bunu reddeder:
  --   ERROR 0A000: cannot use subquery in check constraint
  -- Bu yüzden anahtar sayımı aşağıdaki IMMUTABLE yardımcı fonksiyona
  -- sarılıyor; CHECK yalnızca fonksiyon çağırıyor.
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'user_allocation_pct_is_object_check'
  ) THEN
    DELETE FROM public.user_allocation_snapshots
    WHERE jsonb_typeof(allocation_pct) <> 'object'
       OR public.jsonb_key_count(allocation_pct) > 50;

    ALTER TABLE public.user_allocation_snapshots
      ADD CONSTRAINT user_allocation_pct_is_object_check
      CHECK (
        jsonb_typeof(allocation_pct) = 'object'
        AND public.jsonb_key_count(allocation_pct) <= 50
      );
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- S6 (düşük): snapshot tablolarında INSERT sınırı yoktu — bir
-- kullanıcı milyonlarca satır yazarak hem depolamayı şişirebilir
-- hem de DISTINCT ON sorgularını yavaşlatabilirdi (DoS).
-- Kullanıcı+periyot başına dakikada 1 snapshot yeter.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.throttle_snapshot_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_recent INTEGER;
BEGIN
  IF TG_TABLE_NAME = 'user_roi_snapshots' THEN
    SELECT COUNT(*) INTO v_recent
    FROM public.user_roi_snapshots
    WHERE user_id = NEW.user_id
      AND period_days = NEW.period_days
      AND created_at >= now() - interval '1 minute';
  ELSE
    SELECT COUNT(*) INTO v_recent
    FROM public.user_allocation_snapshots
    WHERE user_id = NEW.user_id
      AND created_at >= now() - interval '1 minute';
  END IF;

  IF v_recent >= 1 THEN
    RAISE EXCEPTION 'snapshot_throttled'
      USING HINT = 'Dakikada en fazla bir snapshot yazılabilir.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_throttle_roi_snapshot ON public.user_roi_snapshots;
CREATE TRIGGER trg_throttle_roi_snapshot
  BEFORE INSERT ON public.user_roi_snapshots
  FOR EACH ROW EXECUTE FUNCTION public.throttle_snapshot_insert();

DROP TRIGGER IF EXISTS trg_throttle_alloc_snapshot ON public.user_allocation_snapshots;
CREATE TRIGGER trg_throttle_alloc_snapshot
  BEFORE INSERT ON public.user_allocation_snapshots
  FOR EACH ROW EXECUTE FUNCTION public.throttle_snapshot_insert();

COMMENT ON FUNCTION get_top_gainers_allocation(INTEGER, INTEGER) IS
  'Verilen periyot için top-N gainer''ın anonim portföy dağılımını döner. p_top_n sunucuda [3,10] aralığına clamp edilir — p_top_n=1 ile tekil kullanıcı izole edilemez, büyük değerle havuz dökülemez. user_id/isim/ticker asla dönmez.';
