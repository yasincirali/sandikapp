-- ============================================================
-- 0061 — get_percentile_bucket: medyan farkı
--
-- TECHNICAL_DEBT "Yatırımcı karşılaştırması medyan farkı ve metrik etiketi
-- taşımıyor". RPC yalnızca (percentile, total_participants) dönüyordu; şerit
-- "yatırımcıların %X'inden iyi getirdin" diyebiliyor ama "medyandan 4,2 puan
-- öndesin" gibi kavraması kolay cümleyi kuramıyordu.
--
-- ## Ne değişti
-- Dönüş tipine iki sütun eklendi:
--   · median_roi_pct — havuzun (uygun katılımcılar, son 24 saat) medyan ROI'si
--   · my_roi_pct     — çağıranın kendi snapshot'ı (fark sunucuda hesaplanan
--                      aynı değerden alınsın; istemci ROI'yi ayrıca hesaplıyor
--                      ama iki sayı yuvarlama/zamanlama yüzünden ayrışabilir)
-- Havuz, sıralama, k_min=8 ve allowlist 0059 ile BİREBİR aynı; yalnızca
-- ek sütunlar hesaplanıyor.
--
-- ## Anonimlik
-- Medyan bir toplu istatistik; tek n'de bir katılımcının tam ROI'sine eşit
-- olabilir ama kime ait olduğu görünmez. `get_top_gainers_allocation` zaten
-- ilk 3'ün ham roi_pct'sini anonim döndürüyor — medyan ondan daha az ifşa
-- eder. Yine de 1 ondalığa yuvarlanır: "%12,3" yeter, "%12,3417" tekil
-- eşleştirmeye yardım etmekten başka işe yaramaz.
--
-- ## Geriye uyumluluk
-- `CREATE OR REPLACE` dönüş tipini değiştiremez → DROP + CREATE. İstemci
-- alanları ADLA okur (`row['percentile']`), yeni sütunlar eski sürümleri
-- kırmaz; yeni istemci ise `median_roi_pct` yoksa (eski sunucu) satırı
-- medyansız kabul eder.
-- ============================================================

DROP FUNCTION IF EXISTS public.get_percentile_bucket(INTEGER);

CREATE FUNCTION public.get_percentile_bucket(p_period_days INTEGER)
RETURNS TABLE (
  percentile INTEGER,
  total_participants INTEGER,
  median_roi_pct NUMERIC,
  my_roi_pct NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_my_roi NUMERIC;
  v_total INTEGER;
  v_rank INTEGER;
  v_median NUMERIC;
  k_min INTEGER := 8;  -- 0031 ile aynı; top-gainers ile hizalı
BEGIN
  IF p_period_days NOT IN (7, 30, 180, 365) THEN
    RETURN;
  END IF;

  -- Çağıran uygun değilse (yeni hesap, seyrek kullanım, tek tür) boş (0059).
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
    COUNT(*) FILTER (WHERE roi_pct > v_my_roi)::INTEGER + 1,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY roi_pct)::NUMERIC, 1)
  INTO v_total, v_rank, v_median
  FROM latest_per_user;

  IF v_total < k_min THEN
    RETURN;
  END IF;

  RETURN QUERY SELECT
    GREATEST(1, LEAST(100, (v_rank * 100 / v_total)))::INTEGER,
    v_total,
    v_median,
    ROUND(v_my_roi, 1);
END;
$$;

REVOKE ALL ON FUNCTION public.get_percentile_bucket(INTEGER) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_percentile_bucket(INTEGER) TO authenticated;

-- DROP sonrası yetkiler sıfırdan kuruldu; yanlış imzaya GRANT verilmiş
-- olsaydı istemci sessizce "veri yok" görürdü (0036/0042 dersi).
do $$
begin
  if not has_function_privilege(
    'authenticated', 'public.get_percentile_bucket(integer)', 'EXECUTE'
  ) then
    raise exception 'get_percentile_bucket: authenticated EXECUTE eksik';
  end if;
  if has_function_privilege(
    'anon', 'public.get_percentile_bucket(integer)', 'EXECUTE'
  ) then
    raise exception 'get_percentile_bucket: anon EXECUTE olmamali';
  end if;
end $$;
