-- 0051_percentile_180d.sql
-- ============================================================
-- Dönem Özeti'nin 6A bloğu için 180 günlük yüzdelik dilim kovası.
--
-- `PeriodSummaryView` 6A döneminde bir benchmark şeridi çiziyor ve
-- `percentile` / `percentileKatilimci` parametrelerini bekliyor. Ekran
-- tarafı bunları DOLDURAMIYORDU: `get_percentile_bucket` yalnızca
-- (7, 30, 365) kovalarını kabul ediyor ve tablo CHECK'i de 180'i
-- reddediyordu (bkz. TECHNICAL_DEBT.md "6A yüzdelik dilimi bağlı değil").
--
-- Bu migration üç yeri birlikte açar — üçü ayrışırsa özellik SESSİZCE
-- çalışmaz:
--   1. `user_roi_snapshots.period_days` CHECK'i,
--   2. `get_percentile_bucket` allowlist'i,
--   3. `get_top_gainers_allocation` allowlist'i (aynı havuzu sayıyor).
--
-- ## 180 kovası GERÇEKTEN dolar mı?
-- Endişe şuydu: 180 günlük getirisi olan kullanıcı azdır, kova k=8
-- eşiğini hiç geçmez. Ama `donemGetirisiPct` seriyi `simulate: true` ile
-- üretiyor — BUGÜNKÜ net pozisyon dönemin tamamına yayılıyor. Yani
-- kullanıcının 180 gündür varlık TUTMASI gerekmiyor; yalnızca
-- sembollerinin 180 günlük FİYAT geçmişi gerekiyor ve onu Yahoo/TEFAS
-- zaten veriyor. Kova bu yüzden 30 günlükle neredeyse aynı kullanıcı
-- kümesinden beslenir.
--
-- ## k_min DEĞİŞMİYOR
-- 0031'deki 8 aynen korunuyor ve `n_max = floor(k_min / 2)` değişmezi de
-- öyle (o dosyadaki UYARI: ikisi bağımsız sabitler değil). Bu migration
-- yalnızca yeni bir KOVA ekliyor, eşik matematiğine dokunmuyor.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1) Tablo CHECK'i — 180 kabul edilsin.
--
-- Inline `CHECK (period_days IN (7,30,365))` sistem adı taşıyor
-- (`user_roi_snapshots_period_days_check`). Yeniden koşulabilir olsun
-- diye varlık kontrolüyle sarılıyor; aykırı satır SİLİNMİYOR çünkü
-- kısıt GENİŞLİYOR, daralmıyor — mevcut her satır yeni kısıtı da geçer.
-- ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'user_roi_snapshots_period_days_check'
  ) THEN
    ALTER TABLE public.user_roi_snapshots
      DROP CONSTRAINT user_roi_snapshots_period_days_check;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'user_roi_snapshots_period_days_allowed'
  ) THEN
    ALTER TABLE public.user_roi_snapshots
      ADD CONSTRAINT user_roi_snapshots_period_days_allowed
      CHECK (period_days IN (7, 30, 180, 365));
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- 2) get_percentile_bucket — allowlist'e 180 eklenir.
--
-- Gövde 0031 ile BİREBİR aynı; yalnızca `NOT IN` listesi genişliyor.
-- Fonksiyon `CREATE OR REPLACE` ile aynı imzada (INTEGER) kalıyor:
-- yeni bir parametre EKLENMİYOR, çünkü parametre eklemek imzayı
-- değiştirir ve eski 1-argümanlı fonksiyon kendi GRANT'leriyle
-- ayakta kalırdı (overload, replace değil).
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_percentile_bucket(p_period_days INTEGER)
RETURNS TABLE (percentile INTEGER, total_participants INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
-- search_path sabitleniyor: security definer fonksiyonda arama yolu
-- kaçırılırsa yetki yükseltme vektörü olur.
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
-- 3) get_top_gainers_allocation — AYNI allowlist.
--
-- İki fonksiyon aynı havuzu sayıyor. Yalnızca percentile'a 180 eklemek
-- tutarsızlık üretirdi: kullanıcı kendi 6A dilimini görür ama Yarış
-- ekranı 180 günlük listeyi "geçersiz periyot" sayıp boş dönerdi.
-- 0031'deki gerekçenin aynısı (eşik ayrışmamalı), burada allowlist için.
--
-- Gövde 0031 ile BİREBİR aynı — yalnızca `NOT IN` listesi genişliyor.
-- k_min / n_min / n_max üçlüsü ve aralarındaki `n_max = floor(k_min/2)`
-- değişmezi aynen korunuyor.
--
-- **Neden tam gövde yazılıyor:** ilk denemede `pg_get_functiondef` ile
-- canlı tanımı okuyup tek satırı `replace` etmek düşünüldü. Reddedildi:
-- string eşleşmezse (boşluk, biçim, ileride 0031'in yeniden yazılması)
-- blok SESSİZCE hiçbir şey yapmaz ve 180 kovası Yarış ekranında geçersiz
-- kalır — çalıştığı sanılan, aslında çalışmayan bir migration. Açık
-- tanım uzun ama ne yaptığı okunabilir.
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
  IF p_period_days NOT IN (7, 30, 180, 365) THEN
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

REVOKE ALL ON FUNCTION get_top_gainers_allocation(INTEGER, INTEGER)
  FROM public, anon;
GRANT EXECUTE ON FUNCTION get_top_gainers_allocation(INTEGER, INTEGER)
  TO authenticated;

COMMENT ON FUNCTION get_percentile_bucket(INTEGER) IS
  'Caller''in anonim genel siralamadaki percentile''ini doner. Kovalar: 7/30/180/365 gun. Son 24 saatte snapshot atmis <8 kullanici varsa bos doner (KVKK k-anonymity).';
