-- Leaderboard: global percentile için gerekli altyapı
--
-- Client kendi ROI'sini hesapladıktan sonra bu tabloya snapshot atar.
-- RPC get_percentile_bucket son 24 saatteki snapshot'lar arasında
-- caller'ın percentile'ini hesaplar; k-anonymity için <20 katılımcıda null döner.
--
-- ROI değeri anonim değildir (user_id ile ilişkili) ama RPC dışında hiç
-- exposelanmaz — RLS ile sadece kullanıcının kendi satırlarına erişim var.
-- Percentile hesabı SECURITY DEFINER RPC üstünden yapılır, agregat sonucu
-- döner, ham satırlar client'a hiç sızmaz.

CREATE TABLE IF NOT EXISTS user_roi_snapshots (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  period_days INTEGER NOT NULL CHECK (period_days IN (7, 30, 365)),
  roi_pct NUMERIC(10, 4) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Aynı kullanıcı aynı gün aynı period için birden fazla snapshot atarsa
  -- sadece en son değer sayılır (UNIQUE constraint yok — history istatistik
  -- için tutulabilir; RPC en yeni satırı okuyor).
  UNIQUE (user_id, period_days, created_at)
);

CREATE INDEX IF NOT EXISTS ix_user_roi_snapshots_lookup
  ON user_roi_snapshots (period_days, created_at DESC);

CREATE INDEX IF NOT EXISTS ix_user_roi_snapshots_user
  ON user_roi_snapshots (user_id, period_days, created_at DESC);

ALTER TABLE user_roi_snapshots ENABLE ROW LEVEL SECURITY;

-- Kullanıcı sadece kendi snapshot'larını INSERT/SELECT edebilir.
-- Percentile hesabı RPC (SECURITY DEFINER) üstünden yapılır, bu RLS'yi
-- bypass ederek tüm satırlara erişir ama SADECE agregat sonuç döner.
CREATE POLICY user_roi_snapshots_own_insert
  ON user_roi_snapshots FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY user_roi_snapshots_own_select
  ON user_roi_snapshots FOR SELECT
  USING (auth.uid() = user_id);

-- RPC: get_percentile_bucket
-- Caller'ın son snapshot'ını alır, aynı period için son 24 saatte snapshot
-- atmış diğer kullanıcıların ROI'leriyle karşılaştırır.
-- Döner: (percentile INT 0-100, total_participants INT) veya null.
-- k-anonymity: total_participants < 20 ise null döner (KVKK safe).
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
BEGIN
  -- k-anonymity min bucket size — bunun altında hiç sonuç dönmez.
  DECLARE k_min INTEGER := 20;
  BEGIN
    -- Caller'ın son 24 saatteki en güncel ROI'si
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

    -- Aynı period için son 24 saatte snapshot atmış her user'ın en güncel değeri
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

    -- percentile: 1 = en üst, 100 = en alt. UI "ilk %X" olarak gösterecek.
    RETURN QUERY SELECT
      GREATEST(1, LEAST(100, (v_rank * 100 / v_total)))::INTEGER,
      v_total;
  END;
END;
$$;

REVOKE ALL ON FUNCTION get_percentile_bucket(INTEGER) FROM public;
GRANT EXECUTE ON FUNCTION get_percentile_bucket(INTEGER) TO authenticated;

COMMENT ON TABLE user_roi_snapshots IS
  'Client-side hesaplanan portföy ROI% snapshot''ları. Sadece opted-in leaderboard kullanıcıları yazar. get_percentile_bucket RPC bu tabloyu okur ve k=20 threshold ile agregat percentile döner.';

COMMENT ON FUNCTION get_percentile_bucket(INTEGER) IS
  'Caller''ın anonim genel sıralamadaki percentile''ını döner. Son 24 saatte snapshot atmış <20 kullanıcı varsa null döner (KVKK k-anonymity).';
