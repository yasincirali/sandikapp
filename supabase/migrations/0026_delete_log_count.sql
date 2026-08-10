-- 0026_delete_log_count.sql
-- ============================================================
-- Silme kaydında "kaç kayıt silindi" bilgisi.
--
--   deleted_count : yalnızca kind = 'delete_log' satırlarında anlamlı.
--                   O silme işleminde kaldırılan ledger kaydı sayısı
--                   (alım + satım + temettü toplamı).
--
-- Neden: Parça parça eklenmiş bir varlık silindiğinde eskiden LOT BAŞINA
-- bir delete_log yazılıyordu. Hareket listesi ham ledger'a bağlanınca bu
-- satırlar tek tek görünür oldu: üç lot'lu bir varlığı silmek listeye üç
-- ayrı "Silindi" satırı bırakıyordu.
--
-- Artık silme işlemi başına TEK satır yazılır ve kaç kaydın gittiği bu
-- sütunda taşınır → hareket listesinde "Silindi · 3 kayıt" olarak okunur.
--
-- Geriye dönük: eski delete_log satırlarında sütun 0 kalır; uygulama 0'ı
-- "sayı bilinmiyor" sayıp yalnızca "Silindi" gösterir.
-- ============================================================

ALTER TABLE public.assets
  ADD COLUMN IF NOT EXISTS deleted_count INTEGER NOT NULL DEFAULT 0;

-- Negatif sayı anlamsız.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'assets_deleted_count_check'
  ) THEN
    ALTER TABLE public.assets
      ADD CONSTRAINT assets_deleted_count_check
      CHECK (deleted_count >= 0);
  END IF;
END$$;
