-- 0059_leaderboard_sybil_eligibility.sql
-- ============================================================
-- M1 (2026-09 değerlendirmesi): k=8 anonimliği Sybil'e karşı zayıftı.
--
-- ## Saldırı
-- k-anonymity, havuzdaki DİĞER katılımcıların bağımsız olduğunu varsayar.
-- Saldırgan 7 hesap açıp her birine bildiği bir ROI yazdırırsa (istemci
-- `user_roi_snapshots.roi_pct`'yi kendi hesaplayıp gönderir) 8 kişilik
-- havuzdaki 8. kişi hedefin kendisidir: `get_percentile_bucket` hedefin
-- sırasını, `get_top_gainers_allocation` ise dağılımını verir. Maliyet:
-- 7 e-posta + birkaç dakika.
--
-- ## Çözüm: havuza girmek ZAMAN ister, para değil
-- Katılımcı sayılmak için hesap "yaşamış" olmalı:
--   1. `auth.users.created_at` en az 7 gün önce,
--   2. son 30 günde en az 5 FARKLI takvim gününde ROI snapshot'ı atmış,
--   3. en az 2 varlık türü tutuyor (allocation snapshot `type_count >= 2`
--      şartı zaten vardı; percentile için de aynı kural).
-- Sahte hesap ordusu artık "hedefi gördüm, 7 hesap açayım" ile
-- KURULAMAZ: önce bir hafta boyunca her gün uygulamayı açan 7 hesap
-- büyütmek gerekir ve o hafta boyunca hedef kişi de kendi
-- portföyünü değiştirir (ROI hedefi kayar). Kesin çözüm değil (hiçbir
-- k-anonymity şeması kararlı bir saldırgana karşı öyle değildir) ama
-- saldırı maliyeti dakikalardan haftalara, sıfırdan bariz bir kötüye
-- kullanım izine (7 hesap × 5 gün × aynı cihaz/IP) çıkar.
--
-- Kendi kendine tutarlılık: ÇAĞIRAN da uygun değilse boş döner —
-- yeni kullanıcı ilk haftasında "Yakında" görür. Bu kabul edilen bir
-- ürün maliyeti: şerit zaten "Son 30 günde…" diyor, 7 gün beklemek
-- metinle çelişmiyor.
--
-- ## Neden tek fonksiyon
-- Uygunluk iki RPC'de de aynı olmalı (0031: "aynı havuzu sayan iki
-- fonksiyonun eşiği ayrışmamalı"). Bu yüzden `leaderboard_eligible_users`
-- tek kaynaktır; sabitler yalnızca orada.
--
-- ## k_min / n_max değişmiyor
-- k_min=8, n_max=4 ve `n_max = floor(k_min/2)` değişmezi aynen duruyor
-- (test/percentile_strip_test.dart bunu 0051 üstünden de doğrular).
-- Havuz küçülür ama k eşiği aynı; sadece havuza girme maliyeti arttı.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1) Uygun katılımcı kümesi.
--
-- SECURITY DEFINER: `auth.users` istemciye kapalı; fonksiyon yalnızca
-- user_id listesi döner, e-posta/oluşturma tarihi sızmaz. Doğrudan
-- çağrılmasın diye authenticated'a GRANT VERİLMİYOR; yalnızca aşağıdaki
-- iki RPC (aynı owner) çağırır.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.leaderboard_eligible_users()
RETURNS TABLE (user_id UUID)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH aged AS (
    SELECT u.id
    FROM auth.users u
    WHERE u.created_at <= now() - interval '7 days'
      AND u.deleted_at IS NULL
  ),
  active AS (
    SELECT s.user_id
    FROM public.user_roi_snapshots s
    WHERE s.created_at >= now() - interval '30 days'
    GROUP BY s.user_id
    HAVING COUNT(DISTINCT (s.created_at AT TIME ZONE 'Europe/Istanbul')::date) >= 5
  ),
  diversified AS (
    SELECT DISTINCT ON (a.user_id) a.user_id, a.type_count
    FROM public.user_allocation_snapshots a
    WHERE a.created_at >= now() - interval '24 hours'
    ORDER BY a.user_id, a.created_at DESC
  )
  SELECT aged.id
  FROM aged
  JOIN active      ON active.user_id = aged.id
  JOIN diversified ON diversified.user_id = aged.id
  WHERE diversified.type_count >= 2;
$$;

REVOKE ALL ON FUNCTION public.leaderboard_eligible_users() FROM public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- 2) get_percentile_bucket — havuz = uygun katılımcılar.
-- Gövde 0051 ile aynı; `latest_per_user` uygunluk kümesiyle JOIN'lenir
-- ve çağıranın kendisi de uygun olmalı.
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
  k_min INTEGER := 8;  -- 0031 ile aynı; top-gainers ile hizalı
BEGIN
  IF p_period_days NOT IN (7, 30, 180, 365) THEN
    RETURN;
  END IF;

  -- Çağıran uygun değilse (yeni hesap, seyrek kullanım, tek tür) boş.
  IF NOT EXISTS (
    SELECT 1 FROM public.leaderboard_eligible_users() e WHERE e.user_id = auth.uid()
  ) THEN
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
    SELECT DISTINCT ON (s.user_id) s.user_id, s.roi_pct
    FROM user_roi_snapshots s
    JOIN public.leaderboard_eligible_users() e ON e.user_id = s.user_id
    WHERE s.period_days = p_period_days
      AND s.created_at >= now() - interval '24 hours'
    ORDER BY s.user_id, s.created_at DESC
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
-- 3) get_top_gainers_allocation — aynı havuz.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_top_gainers_allocation(
  p_period_days INTEGER,
  p_top_n INTEGER DEFAULT 3
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
  k_min INTEGER := 8;  -- k-anonymity minimum (0029'da 20 idi)
  n_min INTEGER := 3;  -- tekil ifşa koruması: asla 3'ten az satır dönme
  n_max INTEGER := 4;  -- havuzun yarısından fazlası dökülmesin (k_min/2)
  v_total INTEGER;
  v_top_n INTEGER;
BEGIN
  IF p_period_days NOT IN (7, 30, 180, 365) THEN
    RETURN;
  END IF;

  v_top_n := LEAST(GREATEST(COALESCE(p_top_n, 3), n_min), n_max);

  -- Havuz: uygun katılımcılar arasından son 24 saatte snapshot atanlar.
  SELECT COUNT(DISTINCT s.user_id) INTO v_total
  FROM user_roi_snapshots s
  JOIN public.leaderboard_eligible_users() e ON e.user_id = s.user_id
  WHERE s.period_days = p_period_days
    AND s.created_at >= now() - interval '24 hours';

  IF v_total < k_min THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH latest_roi AS (
    SELECT DISTINCT ON (s.user_id) s.user_id, s.roi_pct
    FROM user_roi_snapshots s
    JOIN public.leaderboard_eligible_users() e ON e.user_id = s.user_id
    WHERE s.period_days = p_period_days
      AND s.created_at >= now() - interval '24 hours'
    ORDER BY s.user_id, s.created_at DESC
  ),
  latest_alloc AS (
    SELECT DISTINCT ON (a.user_id) a.user_id, a.allocation_pct, a.type_count
    FROM user_allocation_snapshots a
    WHERE a.created_at >= now() - interval '24 hours'
      AND a.type_count >= 2
    ORDER BY a.user_id, a.created_at DESC
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

REVOKE ALL ON FUNCTION get_top_gainers_allocation(INTEGER, INTEGER)
  FROM public, anon;
GRANT EXECUTE ON FUNCTION get_top_gainers_allocation(INTEGER, INTEGER)
  TO authenticated;

COMMENT ON FUNCTION public.leaderboard_eligible_users() IS
  'Yaris/yuzdelik havuzuna girebilen hesaplar: >=7 gunluk hesap, son 30 gunde >=5 farkli gun snapshot, >=2 varlik turu. Sybil maliyetini dakikadan haftaya cikarir (0059).';

-- Doğrulama: authenticated uygunluk fonksiyonunu doğrudan çağıramamalı.
DO $$
BEGIN
  IF has_function_privilege('authenticated', 'public.leaderboard_eligible_users()', 'EXECUTE') THEN
    RAISE EXCEPTION 'leaderboard_eligible_users authenticated tarafindan cagrilabilir olmamali';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.get_percentile_bucket(integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'get_percentile_bucket GRANT eksik';
  END IF;
END $$;
