-- 0019_asset_commission.sql
-- ============================================================
-- İşlem komisyonu / masrafı.
--
--   commission : işlem başına ödenen komisyon+masraf, varlığın PARA
--                BİRİMİNDE (purchase_price ile aynı birim).
--
-- Neden: komisyon maliyete girmediğinde kâr olduğundan yüksek görünür.
-- Alımda maliyeti ARTIRIR, satışta net getiriyi AZALTIR.
--
-- Geriye dönük uyumluluk: mevcut kayıtlar 0 alır — hesaplar bugünküyle
-- birebir aynı kalır, kullanıcı girmedikçe hiçbir rakam değişmez.
-- ============================================================

ALTER TABLE public.assets
  ADD COLUMN IF NOT EXISTS commission NUMERIC NOT NULL DEFAULT 0;

-- Negatif komisyon anlamsız (iade/indirim ayrı bir kavram).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'assets_commission_check'
  ) THEN
    ALTER TABLE public.assets
      ADD CONSTRAINT assets_commission_check
      CHECK (commission >= 0);
  END IF;
END$$;
