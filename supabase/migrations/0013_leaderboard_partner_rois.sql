-- Leaderboard senkronizasyonu: partner ROI'leri de Supabase'ten okunsun.
--
-- Sorun: Şu ana kadar her cihaz karşı tarafın ROI'sini kendi lokal
-- partnerAssets snapshot'ından hesaplıyordu. İki cihaz aynı user için
-- farklı sayı gösteriyordu (fiyat cache, hesap zamanı farkı).
--
-- Çözüm: Her user kendi ROI'sini `user_roi_snapshots`'a yazıyor (mevcut).
-- Bu RPC, caller'ın aktif ortaklık kurduğu tüm partner'ların **son
-- snapshot'ını** güvenli şekilde döner. Client artık hesap yapmıyor,
-- sadece okuyor → iki cihaz aynı satırı görüyor.
--
-- KVKK: Sadece nihai ROI% değeri döner (varlık, TL toplam yok). Zaten
-- kullanıcı opt-in vermiş ve aktif partnerlik var.

CREATE OR REPLACE FUNCTION get_partner_rois(p_period_days INTEGER)
RETURNS TABLE (user_id UUID, roi_pct NUMERIC, updated_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Caller'ın aktif ortaklıkları — hem user_id_1 hem user_id_2 tarafı
  RETURN QUERY
  WITH my_partners AS (
    SELECT CASE
      WHEN p.user_id_1 = auth.uid() THEN p.user_id_2
      ELSE p.user_id_1
    END AS partner_id
    FROM partnerships p
    WHERE (p.user_id_1 = auth.uid() OR p.user_id_2 = auth.uid())
  ),
  latest AS (
    SELECT DISTINCT ON (s.user_id)
      s.user_id, s.roi_pct, s.created_at
    FROM user_roi_snapshots s
    INNER JOIN my_partners mp ON mp.partner_id = s.user_id
    WHERE s.period_days = p_period_days
    ORDER BY s.user_id, s.created_at DESC
  )
  SELECT l.user_id, l.roi_pct, l.created_at FROM latest l;
END;
$$;

REVOKE ALL ON FUNCTION get_partner_rois(INTEGER) FROM public;
GRANT EXECUTE ON FUNCTION get_partner_rois(INTEGER) TO authenticated;

COMMENT ON FUNCTION get_partner_rois(INTEGER) IS
  'Caller''ın aktif ortaklarının son ROI snapshot''larını döner. Sadece opt-in olmuş partnerler görünür (snapshot atmayan partner satırı yoktur). Client bunu okuyup kendi ROI''si ile birleştirir — iki cihaz aynı sayıyı görür.';
