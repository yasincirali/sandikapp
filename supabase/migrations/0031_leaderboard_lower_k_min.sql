-- 0031_leaderboard_lower_k_min.sql
-- ============================================================
-- ÜRÜN KARARI: Zirvedeki Portföyler eşikleri düşürüldü.
--   k_min: 20 → 8   (liste kaç katılımcıda açılır)
--   gösterilen satır: 5 → 3 (istemci tarafında, aşağıya bkz.)
--
-- Gerekçe: kullanıcı tabanı henüz 20 aktif/gün eşiğine ulaşmıyor
-- ve liste periyotların çoğunda hiç açılmıyordu. 24 saatlik pencere
-- KAYAN olduğu için eşik "20 kayıtlı kullanıcı" değil "20 kişi bugün
-- uygulamayı açtı" demekti — pratikte ulaşılması çok daha zor.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- GİZLİLİK NOTU — n_max neden 10'dan 4'e iniyor?
--
-- 0029'da n_max=10 seçilirken gerekçe şuydu: "üst sınır 10, k=20
-- havuzunun YARISINDAN FAZLASININ dökülmesini engeller". Yani 10
-- mutlak bir güvenlik değeri değil, k_min'e GÖRE türetilmiş bir
-- orandı (10/20 = %50).
--
-- k_min 8'e inerken n_max=10 bırakılsaydı bu değişmez sessizce
-- kırılırdı: 8 kişilik bir havuzdan 10 satır istenebilir, yani
-- havuzun TAMAMI dökülebilirdi. k-anonymity fiilen yok olurdu.
--
-- Bu yüzden oran korunur: n_max = floor(k_min / 2) = 4.
-- Alt sınır n_min=3 aynen korunuyor (tekil ifşa koruması) ve
-- istenen "top 3" bu aralığın içinde kalır.
--
-- UYARI: k_min ileride tekrar değiştirilirse n_max da birlikte
-- güncellenmeli. İkisi bağımsız sabitler DEĞİL.
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
  -- Yalnızca beklenen periyotlar. Rastgele p_period_days ile
  -- havuz bölünüp k eşiğinin altına düşürülemesin (bkz. S4).
  IF p_period_days NOT IN (7, 30, 365) THEN
    RETURN;
  END IF;

  -- İstemciden gelen p_top_n güvenli aralığa zorlanır.
  v_top_n := LEAST(GREATEST(COALESCE(p_top_n, 3), n_min), n_max);

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
-- get_percentile_bucket de AYNI k_min'i kullanıyordu (0029'da 20).
--
-- Bu fonksiyon kullanıcının kendi yüzdelik dilimini döndürür.
-- Yalnızca top-gainers'ı 8'e çekseydik tutarsız bir durum doğardı:
-- zirve listesi 8 katılımcıda açılır, ama kullanıcının kendi
-- sıralaması 20'ye kadar "Yakında" demeye devam ederdi. Aynı
-- havuzu sayan iki fonksiyonun eşiği ayrışmamalı.
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
  k_min INTEGER := 8;  -- 0029'da 20 idi; top-gainers ile hizalı
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
