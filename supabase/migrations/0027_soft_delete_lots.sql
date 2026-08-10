-- 0027_soft_delete_lots.sql
-- ============================================================
-- Varlık silmeyi KALICI SİLME'den YUMUŞAK SİLME'ye çevirir.
--
--   deleted_at : NULL  → kayıt aktif (portföye ve hesaplara girer)
--                dolu  → kayıt silinmiş (hesaplardan düşer ama hareket
--                        geçmişinde DURUR)
--
-- Neden: Silme lot satırlarını fiziksel olarak siliyordu. Hareket listesi
-- ham ledger'dan beslendiği için o varlığın Alım/Satım/Temettü satırları
-- da listeden kayboluyor, geriye yalnızca tek bir "Silindi" mezar taşı
-- kalıyordu. Kullanıcı geçmişi okuyamıyordu: "ne aldım, ne sattım, sonra
-- sildim" zinciri kopuyordu.
--
-- Artık lot'lar yerinde kalır, `deleted_at` damgalanır. Hareket listesi
-- hepsini gösterir; toplamlar/grafik/aggregate `deleted_at IS NULL`
-- filtresiyle çalışır. Silme işlemi ayrıca kendi `delete_log` satırını
-- yazmaya devam eder → geçmişte "en son silindi" kaydı olarak görünür.
--
-- Geriye dönük: mevcut satırlarda NULL = aktif, davranış değişmez.
-- Daha önce fiziksel silinmiş kayıtlar geri gelmez (veri yok).
-- ============================================================

ALTER TABLE public.assets
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Aktif kayıt sorguları en sık çalışan sorgulardır; kısmi indeks yalnızca
-- aktif satırları taşır ve silinen kayıtlar büyüdükçe küçük kalır.
CREATE INDEX IF NOT EXISTS assets_active_idx
  ON public.assets (user_id)
  WHERE deleted_at IS NULL;
