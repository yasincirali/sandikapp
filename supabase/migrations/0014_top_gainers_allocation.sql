-- Top Gainers Allocation — anonim, agregat portföy dağılımı feature'ı
--
-- UX: "Bu hafta en çok kazanan 5 portföy ne tutuyor?" — kullanıcı
-- kimliği asla görünmez; sadece rank (1, 2, ...), o dönem ROI'si ve
-- tür bazlı yüzdesel dağılım (%40 hisse, %30 altın, ...) gösterilir.
--
-- KVKK/gizlilik guardrails:
--   1. Miktar (quantity) ve TL toplam ASLA dönmez — sadece yüzdeler.
--   2. Ticker/asset adı ASLA dönmez — sadece tür kategorisi.
--   3. k-anonymity: en az 20 katılımcı gerektirir, yoksa boş döner.
--   4. Min çeşitlilik: <2 farklı türü olan portföy fingerprint riski
--      taşır; agregattan hariç tutulur (tek varlıklı portföylerin
--      pattern'i identify edilebilir).
--   5. Sadece leaderboard'a opt-in olmuş (snapshot atmış) user'lar
--      dahil edilir.
--
-- Client user_allocation_snapshots'a kendi TL bazlı dağılımını yazar
-- (hem FX conversion hem sell/delete_log filtering client'ta yapıldığı
-- için tek doğru yer orası). Bu RPC top ROI'li kullanıcıların allocation
-- satırlarını okur.

CREATE TABLE IF NOT EXISTS user_allocation_snapshots (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- Tür bazlı yüzde: {"hisse":45.2, "doviz":30.1, "altin":15.5, "fon":9.2}
  -- Sum ≈ 100. Ticker/quantity/TL yok. Sadece top-level tür kategorisi.
  allocation_pct JSONB NOT NULL,
  -- Kaç farklı türü var? Client hesaplar; RPC min diversity filtresi için.
  type_count INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_user_allocation_snapshots_recent
  ON user_allocation_snapshots (user_id, created_at DESC);

ALTER TABLE user_allocation_snapshots ENABLE ROW LEVEL SECURITY;

-- Kullanıcı sadece kendi satırlarına yazar/okur; agregat RPC üzerinden
-- SECURITY DEFINER ile diğer user'ların satırlarına erişilir.
CREATE POLICY alloc_own_insert
  ON user_allocation_snapshots FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY alloc_own_select
  ON user_allocation_snapshots FOR SELECT
  USING (auth.uid() = user_id);

-- RPC: get_top_gainers_allocation
-- Verilen periyot için top N portföyün allocation'ını rank + ROI ile döner.
-- Ne user_id ne isim ne ticker döner — sadece rank, roi_pct, allocation_pct.
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
  v_total INTEGER;
BEGIN
  -- Yeterli katılımcı var mı? Son 24 saatte snapshot atmış distinct user.
  SELECT COUNT(DISTINCT user_id) INTO v_total
  FROM user_roi_snapshots
  WHERE period_days = p_period_days
    AND created_at >= now() - interval '24 hours';

  IF v_total < k_min THEN
    RETURN;
  END IF;

  -- Top N + allocation join. Sadece:
  --   1. Son 24 saatte ROI snapshot atmış (opt-in taze)
  --   2. Allocation snapshot'ı olan (paylaşmayı seçmiş)
  --   3. type_count >= 2 (tek varlıklı portföy fingerprint riski)
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
    LIMIT p_top_n
  )
  SELECT
    ROW_NUMBER() OVER (ORDER BY j.roi_pct DESC)::INTEGER AS rank,
    j.roi_pct,
    j.allocation_pct,
    j.type_count
  FROM joined j;
END;
$$;

REVOKE ALL ON FUNCTION get_top_gainers_allocation(INTEGER, INTEGER) FROM public;
GRANT EXECUTE ON FUNCTION get_top_gainers_allocation(INTEGER, INTEGER) TO authenticated;

COMMENT ON TABLE user_allocation_snapshots IS
  'Kullanıcının tür bazlı % dağılımı — miktar, TL, ticker YOK. Sadece leaderboard opt-in kullanıcılar yazar. get_top_gainers_allocation RPC top-N ROI kullanıcının allocation''ını agregat olarak döner (k=20, min type_count=2).';

COMMENT ON FUNCTION get_top_gainers_allocation(INTEGER, INTEGER) IS
  'Verilen periyot için top-N gainer''ın anonim portföy dağılımını döner. user_id/isim/ticker asla dönmez — sadece rank + roi% + tür yüzdeleri.';
