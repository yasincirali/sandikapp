-- 0009_asset_kind_audit_trail.sql
-- ============================================================
-- Faz B: İşlem türü (kind) + audit trail için gerekli sütunlar.
--
--   kind          : 'buy' (default) | 'sell' | 'delete_log'
--   ref_asset_id  : sell / delete_log satırının bağlı olduğu buy lot'u
--   sell_price    : sell satırında gerçekleşen birim satış fiyatı
--
-- Mevcut kayıtlar için `kind` default 'buy' olarak geriye dönük uyumludur.
-- Portföy net pozisyonu: SUM(buy.qty) - SUM(sell.qty) formülüyle hesaplanır.
-- delete_log satırları ana portföy görünümünde ilgili buy lot'unu gizler.
-- ============================================================

ALTER TABLE public.assets
  ADD COLUMN IF NOT EXISTS kind          TEXT   NOT NULL DEFAULT 'buy',
  ADD COLUMN IF NOT EXISTS ref_asset_id  TEXT,
  ADD COLUMN IF NOT EXISTS sell_price    NUMERIC;

-- Enum benzeri kısıt: sadece bilinen değerlere izin ver
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'assets_kind_check'
  ) THEN
    ALTER TABLE public.assets
      ADD CONSTRAINT assets_kind_check
      CHECK (kind IN ('buy','sell','delete_log'));
  END IF;
END$$;

-- Hızlı filtre için index (portföy görüntülerken sık sorulacak)
CREATE INDEX IF NOT EXISTS assets_user_kind_idx
  ON public.assets (user_id, kind);

CREATE INDEX IF NOT EXISTS assets_ref_idx
  ON public.assets (ref_asset_id)
  WHERE ref_asset_id IS NOT NULL;
