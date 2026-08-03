-- 0020_dividend_tracking.sql
-- ============================================================
-- Nakit temettü takibi.
--
--   kind = 'dividend'  : temettü satırı. Miktarı DEĞİŞTİRMEZ.
--   dividend_amount    : ele geçen NET tutar (stopaj sonrası), varlığın
--                        para biriminde.
--
-- Neden: BIST'te temettü getirinin büyük parçasıdır. Girilemediğinde
-- uygulama getiriyi olduğundan DÜŞÜK gösterir.
--
-- Kur notu: temettü satırında `purchase_fx_rate` ödeme günü kurunu taşır
-- (alım kurunu değil) — temettü o gün TL'ye çevrilmiş sayılır.
--
-- DİKKAT: 0009'daki assets_kind_check kısıtı 'dividend'ı kabul etmiyor;
-- kısıt yeniden kurulmalı yoksa INSERT reddedilir.
-- ============================================================

ALTER TABLE public.assets
  ADD COLUMN IF NOT EXISTS dividend_amount NUMERIC NOT NULL DEFAULT 0;

-- kind kısıtını 'dividend' içerecek şekilde genişlet.
ALTER TABLE public.assets
  DROP CONSTRAINT IF EXISTS assets_kind_check;

ALTER TABLE public.assets
  ADD CONSTRAINT assets_kind_check
  CHECK (kind IN ('buy','sell','delete_log','dividend'));

-- Temettü negatif olamaz.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'assets_dividend_amount_check'
  ) THEN
    ALTER TABLE public.assets
      ADD CONSTRAINT assets_dividend_amount_check
      CHECK (dividend_amount >= 0);
  END IF;
END$$;

-- Temettü satırlarını hızlı toplamak için (portföy başına getiri hesabı).
CREATE INDEX IF NOT EXISTS assets_dividend_idx
  ON public.assets (user_id, kind)
  WHERE kind = 'dividend';
